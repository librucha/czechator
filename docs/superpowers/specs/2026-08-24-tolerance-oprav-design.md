# Tolerance drobných oprav — design

**Stav:** návrh k implementaci
**Datum:** 2026-08-24
**Nahrazuje:** část §8 v `docs/design.md`

## 1. Motivace a co se tím ztrácí

Dosud platilo, že model smí změnit **výhradně** diakritiku, a `DiacriticVerifier`
to dokazoval přesnou rovností `fold(output) == fold(input)`. V praxi se ukázalo,
že schopnější modely umí opravit i překlep nebo chybějící čárku, a je škoda to
zahazovat — jenže právě tyhle opravy invariant boří.

Tenhle dokument zavádí **tři nezávislé knoby per profil**, které to umožní, a
poctivě popisuje, co se tím ztrácí.

**Cena je reálná a musí být pojmenovaná:** věta z `DiacriticVerifier.swift:1`
(*„the tool's single hard guarantee"*) přestává platit bezpodmínečně. V režimech
`minorFixes` a `proofread` nástroj **už nedokáže dokázat**, že model nepřepsal
slovo. Dokáže jen ohraničit, kolik toho směl přepsat. To je slabší tvrzení a
README i `docs/design.md` ho musí přestat slibovat.

Konkrétní riziko: `qwen3:4b-instruct` v režimu Korektura bude tiše přepisovat
slova a uživatel se to nedozví. Proto vestavěný profil `local` zůstává `strict`
a `strict` je default každého nového profilu.

## 2. Konfigurační model

Tři knoby, každý dělá právě jednu věc. Všechny **per profil**, protože
důvěryhodnost je vlastnost modelu, ne nástroje.

| pole | co řídí |
|---|---|
| `corrections: CorrectionMode` | co se po modelu **chce** — prompt a volnost velikosti písmen |
| `editBudget: EditBudget` | kolik se **toleruje** |
| `verification: Bool` | jestli se **kontroluje** |

`corrections` a `verification` jsou ortogonální, ne dva stupně jedné škály:
první řídí prompt, druhý existenci kontrolní větve. Proto samostatný `if`.

### 2.1 CorrectionMode

```swift
/// What the model is asked to do. Drives both the prompt and how much the
/// verifier tolerates — the two must move together, or loosening verification
/// only widens the hole without gaining any fixes.
public enum CorrectionMode: String, Sendable, Codable, Equatable, CaseIterable {
    case strict
    case minorFixes = "minor-fixes"
    case proofread

    public var label: String {
        switch self {
        case .strict: return "Přísný"
        case .minorFixes: return "Drobné opravy"
        case .proofread: return "Korektura"
        }
    }

    /// Only `strict` can prove that nothing but diacritics changed.
    public var isTolerant: Bool { self != .strict }
}
```

### 2.2 EditBudget

Rozpočet je **na slovo**, ne na segment. Rozpočet na segment se nafukuje s
délkou — 300 znaků při 5 % je 15 editů, dost na přepsání celé věty. Na slovo
omezuje škodu lokálně a nezávisle na délce odstavce.

```swift
/// Per-word edit allowance. Clamped on every write rather than at validation
/// time, matching TriggerConfig.intervalMs: a hand-edited YAML must never
/// reach a state the code does not expect.
public struct EditBudget: Sendable, Codable, Equatable {
    public var percent: Int { didSet { percent = percent.clamped(to: Self.percentRange) } }
    public var minimum: Int { didSet { minimum = minimum.clamped(to: Self.minimumRange) } }

    static let percentRange = 0...100
    static let minimumRange = 0...5

    public static let builtIn = EditBudget(percent: 20, minimum: 1)

    /// `didSet` does not fire during initialisation, so the memberwise init
    /// must clamp explicitly — exactly as TriggerConfig.init does, and for the
    /// same reason: a value built in code must not get past a range a decoded
    /// one could not.
    public init(percent: Int, minimum: Int) {
        self.percent = percent.clamped(to: Self.percentRange)
        self.minimum = minimum.clamped(to: Self.minimumRange)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = EditBudget.builtIn
        self.init(
            percent: try container.decodeIfPresent(Int.self, forKey: .percent)
                ?? defaults.percent,
            minimum: try container.decodeIfPresent(Int.self, forKey: .minimum)
                ?? defaults.minimum)
    }

    /// Integer arithmetic, floored. A 3-letter word at 20% floors to 0, so the
    /// minimum is what actually carries short words.
    public func allowance(forWordOfLength n: Int) -> Int {
        Swift.max(minimum, (n * percent) / 100)
    }
}
```

**`clamped(to:)` je dnes `fileprivate` v `TriggerConfig.swift:72`** a z jiného
souboru není vidět. Prvním krokem implementace je přesunout ho do vlastního
`Config/IntClamping.swift` jako `internal`, aby ho `EditBudget` mohl použít bez
druhé kopie. Změna je mechanická a `TriggerConfig` se jí nedotkne jinak než
zmizením osmi řádků na konci souboru.

Defaulty `(20 %, 1)` jsou ověřené proti reálným příkladům, ne odhadnuté:

| vstup → výstup | slovo | délka | edity | povoleno |
|---|---|---|---|---|
| `kdy zjsem` → `kdyz jsem` | `kdy` | 3 | 1 | 1 ✅ |
| `kndeliky` → `knedliky` | — | 8 | 1 | 1 ✅ |
| `bil` → `byl` | — | 3 | 1 | 1 ✅ |
| `myslim ze` → `myslím, že` | `myslim` | 6 | 1 | 1 ✅ |

Vycházejí **těsné**, ne velkorysé — každý z těch případů projde přesně na hranu.

Posun mezery v prvním řádku je pro Damerau-Levenshtein **jedna** transpozice
mezery a `z`, ne dva samostatné edity, a přiřadí se slovu `kdy` (pravidlo pro
edit na mezeře viz §3.1). Slovo `zjsem` tak neutratí nic.

### 2.3 Metrika: Damerau-Levenshtein, ne Levenshtein

Řádek `kndeliky → knedliky` výše je jedničkový jen díky transpozici. Prostý
Levenshtein počítá prohození dvou písmen jako **2** edity, což by při rozpočtu 1
zablokovalo nejtypičtější překlep vůbec. Metrika je proto **optimal string
alignment** (Damerau-Levenshtein bez opakovaných úprav) — jedna podmínka v DP
navíc:

```
if i > 1, j > 1, a[i-1] == b[j-2], a[i-2] == b[j-1] {
    d[i][j] = min(d[i][j], d[i-2][j-2] + 1)   // transposition
}
```

### 2.4 Vynucení v přísném režimu

`strict` rozpočet **ignoruje a vynutí nulu**, nikoli jen respektuje uloženou
hodnotu. Jinak si uživatel přepnutím do Přísného a nastavením `percent: 30`
vyrobí režim, který se jmenuje Přísný a přísný není. Jeden `if`, ušetřený
matoucí stav.

### 2.5 Rozšíření Profile a migrace

```swift
public struct Profile: Sendable, Codable, Equatable {
    // ... existing fields ...
    public var corrections: CorrectionMode   // default .strict
    public var editBudget: EditBudget        // default .builtIn
    public var verification: Bool            // default true
}
```

Ve **veřejném memberwise inicializátoru** dostanou všechna tři pole výchozí
hodnotu (`corrections: CorrectionMode = .strict`, `editBudget: EditBudget =
.builtIn`, `verification: Bool = true`), stejně jako už má `apiKey`. Tím zůstanou
všechna volání v `Config.builtIn` i v testech beze změny.

**Pozor — tohle je rozbíjející změna, pokud se přehlédne.** `Profile` dnes
používá **syntetizovaný** `Codable` (na rozdíl od `Config`, `FeatureFlags`,
`Limits` a `PromptConfig`, které všechny mají ruční `init(from:)`). Přidání
nevolitelných polí by způsobilo, že se **existující konfigurační soubory
přestanou dekódovat**. Proto `Profile` dostane ruční `init(from:)` se
`decodeIfPresent` a defaulty, stejně jako sousední typy:

```swift
public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // ... existing fields unchanged ...
    corrections =
        try container.decodeIfPresent(CorrectionMode.self, forKey: .corrections) ?? .strict
    editBudget =
        try container.decodeIfPresent(EditBudget.self, forKey: .editBudget) ?? .builtIn
    verification =
        try container.decodeIfPresent(Bool.self, forKey: .verification) ?? true
}
```

Starý config se tím dekóduje do dnešního chování beze změny.

## 3. EditAlignment — jedna DP, tři konzumenti

Jádro celé změny. Tatáž matice, ze které padá vzdálenost, dá po trasování zpět
i mapování indexů.

```swift
/// Optimal string alignment between two grapheme arrays.
public struct EditAlignment: Sendable, Equatable {
    /// Damerau-Levenshtein distance.
    public let distance: Int
    /// Old grapheme index -> new grapheme index. A key missing from the map
    /// means that grapheme was deleted.
    public let map: [Int: Int]
    /// Index in the ORIGINAL where each edit applies. One entry per edit;
    /// an insertion is attributed to the position it follows.
    public let editPositions: [Int]

    /// Returns nil when either side exceeds `limit` — the DP is O(n*m) and is
    /// not worth running on a paragraph that size. Callers fall back to strict.
    public static func compute(
        _ a: [Character], _ b: [Character], limit: Int = 2_000
    ) -> EditAlignment?
}
```

Konzumenti:

1. **`DiacriticVerifier`** — `distance` a `editPositions` na **normalizované**
   dvojici, pro atribuci ke slovům.
2. **`FragileWhitespace.restore`** — `map` na **surové** dvojici
   `(masked, corrected)`, aby NBSP šel zpět na správnou pozici.
3. **`MarkupEntities.escape` / `JSONEscaping.escape`** — `map` na surové
   dvojici, aby `&amp;` a `é` šly zpět na správnou pozici.

**Dvě různá zarovnání, ne jedno.** Verifikační běží na normalizovaném textu
(fold, case, sloučené mezery), remapovací na surovém. Míchat je nelze —
normalizace posouvá indexy. Znamená to, že u tolerantního segmentu proběhne DP
dvakrát; je to vědomá cena za správnost a u segmentů do 2000 znaků nehraje roli.

### 3.1 Atribuce editů ke slovům

Znakové zarovnání dá atribuci zadarmo a **samo vyřeší změnu počtu slov**, což by
párové porovnání `zip`em neuneslo — a přesně to je případ `kdy zjsem → kdyz jsem`.

```
1. Slova = split normalizovaného ORIGINÁLU na whitespace.
   Interpunkce zůstává přilepená k tokenu ("myslim," je jedno slovo).
2. Každá pozice z editPositions se přiřadí slovu, do jehož rozsahu padne.
   Vložení na hranici se přiřadí PŘEDCHÁZEJÍCÍMU slovu; vložení na pozici 0
   následujícímu.
3. Segment projde <=> pro každé slovo platí
   početEditů(slovo) <= budget.allowance(forWordOfLength: slovo.count)
```

## 4. Verifikace segmentu — nový průběh

```
Pro každý segment:

  je-li corrections == .strict:
      dnešní chování beze změny — policy.normalize(original) == policy.normalize(correction)

  je-li délka segmentu > 2000 znaků:
      spadne zpět na přísné porovnání (DP se nepouští)

  jinak:
      n_o = normalizeTolerant(original)
      n_c = normalizeTolerant(correction)
      je-li n_o == n_c: PŘIJATO   (case, sloučené mezery — bez rozpočtu)
      jinak:
          alignment = EditAlignment.compute(n_o, n_c) ?? return ODMÍTNUTO
          PŘIJATO <=> každé slovo je ve svém rozpočtu
      navíc:
          raw = EditAlignment.compute(original, correction) ?? return ODMÍTNUTO
          každý chráněný index musí mít záznam v raw.map, jinak ODMÍTNUTO
```

```swift
/// fold + lowercase + runs of whitespace collapsed to a single space.
///
/// Deliberately does NOT strip whitespace or punctuation wholesale: stripping
/// them would accept a model that glued "ahoj svete" into "ahojsvete". The
/// budget covers those edits instead, and bounds them from above.
static func normalizeTolerant(_ s: String) -> String
```

### 4.1 Chráněné indexy

Aby se ztráta entity nebo NBSP dala **zopakovat** místo tvrdého pádu, kontroluje
se už při verifikaci. `FormatHandler` dostane novou metodu s výchozí implementací:

```swift
extension FormatHandler {
    /// Grapheme indices in the segment's unescaped text that must survive a
    /// length-changing correction. Default: none.
    func protectedIndices(in segment: Segment) -> Set<Int> { [] }
}
```

- `PlainTextHandler` — prázdné (výchozí)
- `JSONHandler` — klíče `JSONEscapeStyle.detect(in: segment.raw).spellings`
- `HTMLHandler` / `XMLHandler` — klíče `MarkupEntityStyle.detect(...).spellings`

Cena: `detect` proběhne dvakrát (verifikace + escape). Přijatelné.

Fail-closed z `MarkupEntities.swift:97` tím **zůstává zachovaný**, jen se posune
z „jakákoli změna délky" na „změna délky přes chráněnou pozici".

### 4.2 Selhání obnovy NBSP

`FragileWhitespace.restore` se volá v `Pipeline.fill`, tedy **před** verifikací.
Nemůže tedy použít alignment spočítaný při verifikaci a počítá si vlastní.

```swift
/// Returns nil when a masked position did not survive the correction — the
/// caller must reject the segment rather than silently drop the character.
public func restore(into corrected: String, alignment: EditAlignment?) -> String?
```

`nil` **nesmí** vést k uložení původního textu jako opravy — to by prošlo
verifikací jako „nezměněno". `fill` proto vede `Set<Int>` indexů, u kterých
obnova selhala, a verifikace je bezpodmínečně označí za vadné. Retry větev je
pak obslouží normálně.

`alignment: nil` znamená identitu — přísný režim jede dnešní cestou bajt za
bajtem beze změny.

### 4.3 Retry a zarovnání velikosti písmen

Retry zůstává: vadné segmenty **jednou** zopakovat, pak chyba. Beze změny.

`Pipeline.alignCase` se v tolerantních režimech **přeskakuje** — vnucovalo by
zpět case, který má model podle promptu právo změnit. Důsledek, který je nutné
uvést: `letterCase` (`preserve` / `segmentStart` / `model`) je v tolerantních
režimech **mrtvé nastavení** a působí jen v Přísném. V UI se podle toho zašedí.

Ztrácí se tím i ochrana proti `PRAHA → Praha` a `iPhone → IPhone`, popsaná
v `LetterCasePolicy.swift:3`.

## 5. Kontrola dokumentu

Dnešní `documentMatches` staví na fold-rovnosti, kterou tolerance ruší.
Nahrazuje ji **rovnost mezer**: text **mimo** rozsahy segmentů musí být mezi
vstupem a výstupem bajt po bajtu shodný.

```swift
/// The bytes between segments must survive untouched.
///
/// `expected` is built with the same range arithmetic Reassembler.splice uses
/// to build `output`, so this equals `output` whenever segments are reported
/// in document order — which the pipeline always does. The only production
/// error it can catch is a handler reporting segments out of order; it is not
/// an independent check on splice itself.
public static func gapsMatch(
    original: String, output: String, segments: [Segment], replacements: [String]
) -> Bool
```

Zůstává **přesná ve všech režimech**, včetně vypnuté verifikace — segmentová
posloupnost je náš vlastní kontrakt, ne chyba modelu, a tu chceme hlídat
vždycky. Není to ale nezávislá druhá implementace skládání: staví na stejné
aritmetice rozsahů jako `Reassembler.splice` a volá se na jeho vlastním
výstupu, takže v produkci chytí jen segmenty nahlášené mimo pořadí dokumentu.

Buď si vědom, že je to **slabší** hlídač než ten, který nahrazuje.

## 6. Prompty

`PromptBuilder.defaultSystem` se rozpadne na tři konstanty a
`PromptBuilder.system(for: CorrectionMode)`. Požadavek z
`PromptBuilder.swift:12` — *„MUST stay byte-identical between calls"* — zůstává
splněn: tři stabilní konstanty, režim se během běhu nemění, takže prefill cache
v Ollamě drží. `promptOverride` má i nadále přednost před všemi třemi.

### 6.1 strict

Beze změny, dnešní znění.

### 6.2 minorFixes

```
You restore Czech diacritics and fix small typing mistakes.

Rules:
- Output ONLY the numbered list, with the same count and numbering as the input.
- You MAY add Czech accents: a->á, e->é/ě, i->í, o->ó, u->ú/ů, y->ý,
  c->č, d->ď, n->ň, r->ř, s->š, t->ť, z->ž.
- You MAY fix an obvious typing mistake: a swapped, missing or doubled letter,
  a misplaced space, a missing comma or period, a wrong i/y or s/z.
- You MAY fix capitalization at the start of a sentence.
- NEVER replace a word with a different word, a synonym or a translation.
- NEVER reorder, reword, reformat, shorten or explain anything.
- Change as little as possible. If a word is already correct, leave it alone.
- Preserve all other non-letter characters exactly.
- The sequences \n, \r, \t and \\ are literal two-character escapes. Keep them as-is.
- Leave text that is not Czech unchanged.

Example
input:
1. Prilis zlutoucky kun upel dabelske ody.
2. kdy zjsem sel domu bylo uz pozde
3. This is English, leave it alone.
output:
1. Příliš žluťoučký kůň úpěl ďábelské ódy.
2. Když jsem šel domů, bylo už pozdě.
3. This is English, leave it alone.
```

### 6.3 proofread

```
You are a Czech proofreader.

Rules:
- Output ONLY the numbered list, with the same count and numbering as the input.
- Restore Czech accents, fix typing mistakes, spelling, punctuation,
  capitalization and grammatical agreement.
- NEVER replace a word with a synonym, and never translate.
- NEVER reorder sentences, reword for style, shorten, expand or explain.
- Change as little as possible. If a sentence is already correct, repeat it verbatim.
- The sequences \n, \r, \t and \\ are literal two-character escapes. Keep them as-is.
- Leave text that is not Czech unchanged.

Example
input:
1. Prilis zlutoucky kun upel dabelske ody.
2. kdy zjsem sel domu bilo uz pozde a dvere bili zamcene
3. This is English, leave it alone.
output:
1. Příliš žluťoučký kůň úpěl ďábelské ódy.
2. Když jsem šel domů, bylo už pozdě a dveře byly zamčené.
3. This is English, leave it alone.
```

## 7. Vypnutá verifikace

`verification == false`:

- **vynechá** se porovnání segmentů i retry větev
- **vynechá** se kontrola chráněných indexů
- **zachová** se kontrola mezer z §5
- `PipelineError.verificationFailed` už nemůže nastat, tedy ani `!` v menu

Protože kontrola chráněných indexů odpadá, může se v tomhle režimu tiše ztratit
NBSP nebo přemístit HTML entita. To je vlastnost vypnuté verifikace, ne chyba;
UI na to musí upozornit (§8).

## 8. Nastavení

Vše v editoru profilu na kartě **Pokročilé**, protože `corrections` je per profil.

| prvek | typ | viditelnost |
|---|---|---|
| Režim oprav | popup, 3 položky přes `CorrectionMode.label` | vždy |
| Rozpočet — % délky slova | číselné pole 0–100 | jen když `corrections != .strict` |
| Rozpočet — nejméně editů | číselné pole 0–5 | jen když `corrections != .strict` |
| Ověřovat výsledek | toggle | vždy |
| Velikost písmen (`letterCase`) | stávající popup | zašedlé když `corrections != .strict` |

Při přepnutí režimu se rozpočet **předvyplní** na `(20 %, 1)` pro Drobné opravy
a `(35 %, 2)` pro Korekturu. Předvyplnění je jednorázový návrh — uložená hodnota
je vždy ta explicitní, ne odvozená z režimu.

Varovný text pod toggle, když je verifikace vypnutá:

> Bez ověření se do schránky zapíše cokoli, co model vrátí.

Varovný text pod popupem, když je zvolena Korektura:

> U malých lokálních modelů může model tiše přepsat slova.

`SettingsFormState` dostane pole v `editedProfileFields` a validaci rozsahů;
`canSave` se nemění, protože clamp v `didSet` znemožňuje neplatný stav.

## 9. CLI

Bez nových přepínačů — profil v configu stačí. `czechator fix --debug` doplní do
hlavičky reportu režim, rozpočet a stav verifikace, aby bylo z výstupu poznat,
podle čeho se rozhodovalo. `DebugReporter` u odmítnutého segmentu navíc vypíše
slovo, které rozpočet přečerpalo, a o kolik.

## 10. Testy

Jednotky:

- `EditBudget.allowance` — tabulka délek proti očekávaným rozpočtům, včetně
  podlahy u krátkých slov a clampu na hranicích
- `EditAlignment.compute` — vzdálenost proti známým dvojicím; **transpozice
  stojí 1**, ne 2; `nil` nad limitem
- atribuce editů ke slovům — tabulka z §2.2 jako testovací případy
- `normalizeTolerant` — sloučení běhů mezer; **`ahoj svete` vs `ahojsvete` se
  nesmí normalizovat na shodu**
- `CorrectionMode.strict` vynutí nulový rozpočet i při `percent: 30`

Regresní — obojí by bez zarovnání selhalo **tiše**:

- **NBSP přežije opravu měnící délku** (`FragileWhitespace` + `EditAlignment`)
- **HTML entita přežije opravu měnící délku** (`MarkupEntities` + `EditAlignment`)
- chráněný index, který oprava smaže → segment odmítnut, ne poškozen

Integrační:

- starý config bez nových klíčů se dekóduje do `strict` / `builtIn` / `true`
- `verification == false` přeskočí retry a projde i vadnou opravu
- kontrola mezer platí i při vypnuté verifikaci
- přepnutí profilu přepne režim
- `PromptBuilder.system(for:)` vrací tři různé konstanty

U každého testu **mutační ověření** — chybu znovu zavést a potvrdit, že test
zčervená. Stejný postup jako u triggeru a segmentace.

## 11. Dotčené soubory

Nové:

- `Sources/CzechatorCore/Config/CorrectionMode.swift`
- `Sources/CzechatorCore/Config/EditBudget.swift`
- `Sources/CzechatorCore/Verification/EditAlignment.swift`
- `Sources/CzechatorCore/Verification/WordBudget.swift` (atribuce ze §3.1)

Měněné:

- `Config/Config.swift` — `Profile` + ruční `init(from:)`
- `Verification/DiacriticVerifier.swift` — tolerantní větev, `gapsMatch`
- `Pipeline.swift` — průběh ze §4, přeskočení `alignCase`, `Set` selhaných obnov
- `Providers/FragileWhitespace.swift` — `restore` s alignmentem, návrat `String?`
- `Handlers/MarkupEntities.swift`, `Handlers/JSONEscaping.swift` — escape s alignmentem
- `Handlers/FormatHandler.swift` a čtyři handlery — `protectedIndices`
- `Providers/PromptBuilder.swift` — tři konstanty
- `CzechatorApp/SettingsFormState.swift`, `SettingsView.swift` — §8
- `czechator/DebugReporter.swift` — §9
- `README.md` (řádky 25–40), `docs/design.md` (§8) — §1

## 12. Vědomě odložené

**Strop na počet změněných slov v segmentu.** Rozpočet je čistě lokální: v
padesátislovném odstavci může každé slovo utratit svůj edit a model tak
nenápadně přepíše všechno, aniž by kterékoli slovo rozpočet překročilo. Strop
typu „nejvýš 30 % slov segmentu se smí změnit" by díru zavřel. Neděláme ho teď —
je to čtvrtý knob v UI a není jisté, že to v praxi vadí. Pokud se ukáže, že
Korektura na slabém modelu takhle uklouzne, tohle je první věc, kterou přidat.

**Zarovnání jako jediný průchod.** Verifikace a remapování počítají DP zvlášť,
na normalizované a surové dvojici. Sjednotit to by šlo přemapováním indexů mezi
normalizovanou a surovou podobou; není to teď potřeba a byl by to netriviální
zdroj chyb.

# Měření kvality profilů a režimů oprav — design

**Stav:** návrh k implementaci
**Datum:** 2026-08-25
**Nahrazuje:** `Tools/quality.py` (bude smazán)

## 1. Motivace

`Tools/quality.py` měří, jak si model vede na 23 českých vzorcích, a vypisuje
dvě čísla — kolik vyšlo přesně a kolik prošlo verifikací. Má tři díry, které
dohromady znamenají, že **na polovinu dnešní konfigurace se nedá změřit nic**:

1. **Umí jen Ollamu.** `config_for` (`Tools/quality.py:127`) přepisuje model
   podle prefixu řádku uvnitř bloku `  local:`. Proti OpenAI-kompatibilnímu
   profilu, tedy i proti Claude, se změřit nedá nic. Čísla v README proto
   existují výhradně pro lokální modely.
2. **Neví o režimech oprav.** `corrections`, `editBudget` ani `verification`
   neexistují. Funkce dodaná ve větvi `tolerance-oprav` nemá jediné naměřené
   číslo.
3. **Není doručitelná uživateli.** `make install-cli` kopíruje pouze binárku;
   kdo si nainstaloval CLI, `Tools/` nemá.

Zároveň přibyla uživatelská potřeba: kdo si přepíše `prompt.override`, nemá jak
zjistit, jestli si pomohl, nebo uškodil.

## 2. Rozsah

Nový podpříkaz **`czechator quality`**, plnohodnotná náhrada skriptu, dostupný
každému, kdo má nainstalované CLI.

Odpovídá na tři otázky:

- **Který backend je lepší?** — matice profilů vedle sebe.
- **Vyplatí se tolerantní režim?** — matice režimů vedle sebe, měřená ze dvou
  stran: kolikrát model sáhne na text, který byl v pořádku, a kolik skutečných
  chyb opraví.
- **Pomohl jsem si vlastním promptem?** — uživatel proti své konfiguraci a
  volitelně proti své vlastní sadě vzorků.

Výstup musí být **publikovatelný na GitHubu**, tedy Markdown, který nese
provenienci.

**Mimo rozsah:** tlačítko v okně nastavení. Měřicí jádro bude v `CzechatorCore`,
takže si ho okno může vzít později, ale tenhle spec ho nedodává.

## 3. Tvar příkazu

```
czechator quality [--profile NAME]... [--corrections MODE]...
                  [--fixtures-dir PATH] [--model M]
                  [--letter-case P] [--format F] [--config PATH] [--verbose]
```

| volba | výchozí | význam |
|---|---|---|
| `--profile` | aktivní profil z configu | opakovatelná; každý výskyt je řádek matice |
| `--corrections` | vlastní nastavení profilu | opakovatelná; `strict` \| `minor-fixes` \| `proofread` \| `all` |
| `--fixtures-dir` | vestavěné sady | nahradí obě vestavěné sady jednou uživatelskou |
| `--model` | model profilu | přepíše model u **všech** měřených profilů; kvůli levnému prohánění Ollamy |

`--model` má smysl u jednoho profilu nebo u několika profilů téhož poskytovatele.
Napsat ho k matici, která míchá Ollamu s OpenAI, znamená poslat jedno jméno
modelu oběma — nástroj to udělá a selže až na druhém volání. Není to hlídané:
je to zkratka pro srovnání modelů, ne pro srovnání backendů.
| `--letter-case` | `features.letterCase` z configu | `preserve` \| `segmentStart` \| `model`; působí jen v přísném režimu |
| `--format` | `terminal` | `terminal` \| `md` |
| `--config` | `~/.config/czechator/config.yaml` | jako u `fix` a `segments` |
| `--color` | `auto` | `auto` \| `always` \| `never`; jen pro `--format terminal` |
| `--verbose` | vypnuto | vypíše i vzorky, které prošly |

Výchozí hodnota `--corrections` je **vlastní nastavení profilu**, ne `strict`:
holé `czechator quality` má odpovědět „jak si vede to, co reálně používám".
`--corrections all` rozvine všechny tři.

Ze stejného důvodu je výchozí hodnota `--letter-case` **`features.letterCase` z
konfigurace**, ne natvrdo `preserve`. `fix` tu hodnotu čte; kdyby ji měření
ignorovalo, dostal by uživatel s `letterCase: segmentStart` čísla o sestavě,
kterou nepoužívá.

**Neplatná volba, neznámý profil ani nerozřešitelný klíč se nesmí objevit až
uprostřed měření.** Nástroj nemá žádnou pojistku proti útratě (§14), takže se
profily rozřeší a poskytovatelé postaví **před** prvním voláním modelu —
`--profile local --profile clode` musí stát nula, ne celé `local`.

Matice je kartézský součin profilů a režimů, spuštěný nad každou sadou vzorků.

## 4. Co se měří

Tři čísla na buňku matice, ne dvě:

| číslo | význam |
|---|---|
| `přesně` | výstup se shoduje s referencí |
| `přes verifikaci` | běh skončil úspěchem, tedy do schránky by se zapsalo |
| `odmítnuto` | běh skončil `verificationFailed` |

Třetí sloupec je nový a je to ten, kvůli kterému nepotřebují sady žádná
metadata. Přísný režim nad sadou s překlepy ukáže vysoké „odmítnuto" a to je
**správný výsledek**, ne selhání — model nemůže opravit překlep a zároveň projít
přesnou rovností. Nástroj tedy nemusí hádat, co uživatel svou sadou zamýšlel;
vypíše tři čísla a čtenář je přečte.

### 4.1 Chyba poskytovatele běh zastaví

`PipelineError.providerFailed` **ukončí celé měření chybou**, nezapočítá se jako
neúspěch vzorku. Nedostupná Ollama nebo 401 znamená, že měření je neplatné, ne
že model dopadl špatně. Dnešní skript to tiše počítá jako neúspěch a výsledkem
je tabulka samých nul, která vypadá jako verdikt o modelu.

Totéž pro `noText`, `unparsableStructure` a `inputTooLarge`: to jsou vady
vzorku, ne modelu. Běh skončí chybou, která pojmenuje soubor.

A totéž pro **sadu, ve které se nic nezměří**. Adresář bez jediné dvojice
`.in`/`.want` je chyba, ne prázdná tabulka: jinak se tabulka samých nul vrátí
zadními vrátky, tentokrát s návratovým kódem 0. Načtení sady tedy musí být
uvnitř té části běhu, která chyby překládá do češtiny — jinak se uživateli
vypíše holý swiftový výčet.

## 5. Sady vzorků

Dvě vestavěné, obě se pouštějí a reportují **zvlášť**, protože odpovídají na
jinou otázku:

- **`clean`** — dnešních 23 vzorků z `Fixtures/quality/`. Čistý český text,
  kterému chybí jen diakritika. V tolerantním režimu měří, **kolikrát model
  sáhne na text, který byl v pořádku** — přesně to riziko, kvůli kterému
  zůstávají všechny dodávané profily přísné.
- **`typos`** — nová sada v `Fixtures/typos/`. Vstupy s úmyslnými překlepy,
  reference s jejich opravou. Měří, **kolik chyb režim skutečně spraví**.

Formát obou i uživatelské sady je stejný: `<jméno>.in` a `<jméno>.want` vedle
sebe. `--fixtures-dir` nahradí obě vestavěné jednou sadou pojmenovanou podle
adresáře.

Dvojice se kontroluje **v obou směrech**. `.in` bez `.want` je chyba zjevná —
není s čím porovnávat. `.want` bez `.in` je zákeřnější: načítání jde po `.in`
souborech, takže by osiřelá reference byla neviditelná a sada by se tiše
zmenšila z 12 na 11 — i se zlomkem, který se publikuje.

### 5.1 Nová sada `typos`

Nejméně 12 vzorků, každý s jedním druhem chyby, aby se z tabulky dalo poznat, co
model neumí:

- prohození písmen (`kndelíky`)
- chybějící písmeno (`kžda`)
- zdvojené písmeno (`slunnce`)
- posunutá mezera (`kdy zjsem sel`)
- i/y (`bil jsem doma`)
- s/z (`zpráva` vs `správa` v kontextu, který to rozhodne)
- chybějící čárka před spojkou
- mezera před tečkou
- malé písmeno na začátku věty
- překlep uvnitř slova ve strukturovaném JSON vzorku
- překlep v HTML textovém uzlu
- vzorek **bez** chyby, kontrolní — reference se rovná vstupu s diakritikou

Ten poslední je záměrný: sada s překlepy musí obsahovat i případ, kde není co
opravovat, jinak se z ní nepozná model, který opravuje všechno bez rozdílu.

### 5.2 Vestavění a ochrana proti zastarání

Zdrojem pravdy zůstávají soubory v `Fixtures/`. `make fixtures` z nich generuje
`Sources/CzechatorCore/Quality/QualityFixtures.swift` jako Swift literály s
explicitním escapováním (`\n`, `\r`, `\"`, `\\`).

**Ručně se ten soubor nepíše.** `Fixtures/quality/13-crlf.in` má opravdu CRLF a
`14-json.in` nese JSON escapy; přepisování takového obsahu do literálů rukou je
past, ve které se chyba pozná až jako špatné číslo v tabulce.

Proti zastarání generované kopie hlídá test, který načte `Fixtures/` z disku
přes `#filePath` (cesta k repozitáři odvozená ze souboru testu, protože pracovní
adresář testovacího běhu není zaručený) a porovná bajt po bajtu s vestavěnou
sadou. Kdo upraví vzorek a zapomene na `make fixtures`, dostane červený test.

## 6. Sestavení běhu

Žádná chirurgie na konfiguraci. `Config` se načte jednou, a pro každou buňku
matice se z ní udělá kopie s vloženými přepisy:

```swift
var profile = config.profiles[name]!
if let model { profile.model = model }
profile.corrections = mode
profile.verification = true          // měření bez verifikace nemá co reportovat
```

`CLIEnvironment` dostane druhý inicializátor poskytovatele, aby se dal postavit
pro libovolný profil, ne jen pro aktivní:

```swift
func makeProvider(for profile: Profile) throws -> any LLMProvider
```

Stávající `makeProvider()` se stane jednořádkovou obálkou nad ním. Klíče se řeší
beze změny stávající cestou přes `SecretResolver`, takže Keychain i proměnná
prostředí fungují jako dosud.

**`verification` se pro měření vždy zapíná**, i když ho profil má vypnuté: se
zapnutou verifikací mají sloupce „přes verifikaci" a „odmítnuto" smysl, bez ní
by byly konstantní. Do reportu se to napíše, aby to nebylo tiché.

## 7. Porovnání s referencí

```swift
public enum QualityComparison {
    /// Whether the output matches the reference, with case relaxed the way the
    /// run relaxes it.
    ///
    /// Deliberately does NOT fold diacritics. The reference already carries the
    /// correct accents, so folding would let a wrongly accented answer pass as
    /// right — which is the one thing this tool exists to measure.
    public static func matches(
        got: String, want: String, mode: CorrectionMode, policy: LetterCasePolicy
    ) -> Bool
}
```

Pravidla:

| režim | porovnání |
|---|---|
| tolerantní (`minor-fixes`, `proofread`) | bez ohledu na velikost písmen — `letterCase` tam nepůsobí |
| `strict` + `preserve` | přesná rovnost |
| `strict` + `model` | bez ohledu na velikost písmen |
| `strict` + `segmentStart` | řádek po řádku; první písmeno každého řádku se smí lišit |

`segmentStart` porovnává po řádcích včetně jejich zakončení, aby se CRLF vzorek
neporovnával jako LF.

## 8. Report jako hodnota, formátovače zvlášť

Běh vyprodukuje hodnotu; vykreslení je oddělené. Díky tomu jdou **oba
formátovače otestovat bez jediného volání modelu** — dnešní tabulku v Pythonu
netestuje nic.

```swift
public struct QualityCell: Sendable, Equatable {
    public let profileName: String
    public let model: String
    public let corrections: CorrectionMode
    /// nil in strict mode, where the budget is forced to zero.
    public let budget: EditBudget?
    public let exact: Int
    public let accepted: Int
    public let refused: Int
    public let total: Int
    public let misses: [QualityMiss]
}

public struct QualityMiss: Sendable, Equatable {
    public let sample: String
    public let got: String
    public let want: String
    public let refused: Bool
}

public struct QualitySetResult: Sendable, Equatable {
    public let setName: String
    public let sampleCount: Int
    public let cells: [QualityCell]
}

public struct QualityReport: Sendable, Equatable {
    public let version: String
    /// Injected rather than read from the clock, so the formatters are testable.
    public let measuredOn: String
    public let letterCase: LetterCasePolicy
    /// Reconstructed from the parsed options, never from CommandLine.arguments.
    public let invocation: String
    public let verificationForced: Bool
    public let sets: [QualitySetResult]
}
```

## 9. Markdown

`--format md` píše na stdout, takže `czechator quality --format md >
docs/quality.md` i vložení do schránky fungují bez další volby. `--out` není
potřeba, roura to umí.

Jedna tabulka na sadu, pod ní provenience:

```markdown
### clean — 23 vzorků

| profil | model | režim | rozpočet | přesně | přes verifikaci | odmítnuto |
|---|---|---|---|---|---|---|
| local | qwen3:4b-instruct | Přísný | — | 15/23 (65 %) | 22/23 (96 %) | 1/23 |
| claude | claude-sonnet-5 | Korektura | 35 %/2 | 21/23 (91 %) | 23/23 (100 %) | 0/23 |

<sub>czechator 1.0.0 · 2026-08-25 · letterCase: preserve · `czechator quality --profile local --profile claude --corrections all`</sub>
```

Bez nadpisu první úrovně, aby šel výstup vlepit do README i uložit samostatně.

Řádek provenience nese verzi, datum, `letterCase` a **příkaz, kterým se to dá
zopakovat**. Publikované číslo bez toho je tvrzení bez důkazu, a `CLAUDE.md`
tenhle projekt na to výslovně upozorňuje: zastaralý transkript vypadá jako
aktuální a nikdo ho nepřepočítá.

Je-li `verification` vynucené proti nastavení profilu (§6), přibude do řádku
`ověřování vynuceno`.

### 9.1 Endpoint se do Markdownu nedostane

Tabulka nese **jméno profilu a model, nikdy endpoint**. Kdo měří proti
firemní bráně na `https://ai.interni.firma.cz/v1` a výsledek vloží do veřejného
README, vysypal by interní adresu. V terminálovém formátu endpoint být může.

Ze stejného důvodu se `invocation` skládá z rozparsovaných voleb a **žádná
volba nesoucí cestu se do něj nedostane celá**. `--config` je ten zjevný případ
— cesta ke konfiguraci nese uživatelské jméno — ale `--fixtures-dir
~/Documents/moje-vzorky` nese přesně totéž. `--config` se vypouští úplně,
`--fixtures-dir` se zkracuje na poslední složku cesty; sada se podle ní jmenuje
v nadpisu tabulky nad tím, takže se nic nesrozumitelného neztratí. Každá další
volba s cestou musí projít stejným sítem.

## 10. Terminálový formát

Zachovává dnešní chování `Tools/quality.py`: barevné pruhy s teplotní škálou,
`NO_COLOR` a `--color auto|always|never`. Přibude třetí sloupec a řádky matice
se seskupí podle sady.

## 11. Odstranění `Tools/quality.py`

Skript se maže. Zmizí i jeho zmínky v `README.md`. Dvě měřidla vedle sebe
znamenají, že se jednou rozejdou a nikdo nebude vědět, kterému věřit — a
duplicitní `compare()` v Pythonu, který zrcadlí `LetterCasePolicy`, je přesně
ten druh kopie, co se rozejde tiše.

## 12. Testy

Bez volání modelu:

- `QualityComparison.matches` — tabulka režimů a politik proti známým dvojicím;
  **vzorek se špatně doplněnou diakritikou musí propadnout** (test proti tomu,
  aby někdo do porovnání přidal skládání)
- `segmentStart` nad CRLF vzorkem porovnává po řádcích včetně zakončení
- `MarkdownFormatter` — tabulka pro známý `QualityReport`; endpoint se ve
  výstupu **nesmí objevit**; `--config` se nesmí objevit v `invocation`
- `TerminalFormatter` — šířky sloupců a to, že `NO_COLOR` potlačí escapy
- rozpad voleb na buňky matice: `--corrections all` dá tři, dva profily krát
  dva režimy dají čtyři
- rozpočet je v buňce `nil` právě v přísném režimu
- `invocation` neobsahuje `--config` **ani absolutní cestu** (§9.1)
- osiřelá `.want` bez `.in` a adresář bez jediné dvojice jsou chyby (§4.1, §5)

Cíl `czechator` **nemá testovací target** a nedostane ho: proto ty dvě rozhodnutí
o matici — sestavení buněk a `invocation` — nesmějí bydlet v příkazu. Žijí v
`CzechatorCore/Quality/QualityMatrix.swift` jako čisté funkce nad hodnotami a
testují se tam. `QualityCommand` zůstává tenkou slupkou: I/O, sestavení
pipeline a smyčka.
- vestavěné vzorky se shodují s `Fixtures/` na disku (§5.2)

S falešným poskytovatelem (`FakeProvider` z `PipelineTests` už existuje):

- chyba poskytovatele **ukončí měření**, nezapočítá se jako neúspěch
- vzorek odmítnutý verifikací se počítá do `odmítnuto`, ne do `přesně`

U každého mutační ověření — chybu znovu zavést a potvrdit, že test zčervená.

## 13. Dotčené soubory

Nové:

- `Sources/CzechatorCore/Quality/QualityComparison.swift`
- `Sources/CzechatorCore/Quality/QualityReport.swift` (hodnoty ze §8)
- `Sources/CzechatorCore/Quality/QualityRunner.swift` (běh nad sadou)
- `Sources/CzechatorCore/Quality/QualityMatrix.swift` (buňky matice a
  `invocation` jako čisté funkce, §12)
- `Sources/CzechatorCore/Quality/MarkdownFormatter.swift`
- `Sources/CzechatorCore/Quality/TerminalFormatter.swift`
- `Sources/CzechatorCore/Quality/QualityFixtures.swift` (generovaný)
- `Sources/czechator/QualityCommand.swift`
- `Fixtures/typos/*.in|.want` (§5.1)
- `Tools/embed-fixtures.py` (generátor volaný z `make fixtures`)

Měněné:

- `Sources/czechator/Czechator.swift` — `QualityCommand` do `subcommands`
- `Sources/czechator/CLIEnvironment.swift` — `makeProvider(for:)`
- `Sources/CzechatorCore/ErrorMessages.swift` — `QualityError` a
  `QualityFixtureError` česky, ne přes větev `default`
- `Makefile` — cíl `fixtures`
- `README.md` — nová sekce, odstranění zmínek o `Tools/quality.py`

Mazané:

- `Tools/quality.py`

## 14. Dokumentace

Nová sekce v README popíše příkaz, oba formáty a obě sady. Musí obsahovat
**upozornění, že proti placenému API měření stojí peníze**, s konkrétním počtem
volání: dvě sady krát tři režimy krát počet profilů, u vestavěných sad zhruba
`(23 + 12) × 3 = 105` běhů na profil. Žádná pojistka v kódu proti tomu není —
je to vědomé rozhodnutí, dokumentace je jediné varování.

## 15. Vědomě odložené

**Tlačítko v okně nastavení.** Jádro je v `CzechatorCore`, takže si ho okno může
vzít, ale GUI tenhle spec nedodává.

**Cache odpovědí.** Opakované měření téhož profilu a modelu volá model znovu.
U placeného API to je opakovaná útrata. Cache klíčovaná vstupem, modelem a
promptem by to odstranila, ale zavádí otázku invalidace a není jasné, že to v
praxi vadí.

**Souběžnost.** Vzorky jdou po jednom. 105 běhů proti cloudovému API je řádově
minuty. Paralelizace by to zkrátila, ale rozbila by pořadí výpisu a u lokální
Ollamy by soupeřila o tentýž GPU.

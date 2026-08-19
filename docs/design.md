# Czechator — návrh

> **Návrh, jak vypadal před implementací.** Zachycuje uvažování a rozhodnutí,
> ne současný stav kódu — ten se od něj na několika místech vědomě odchýlil a
> každou odchylku vysvětluje příslušný commit. Autoritou je kód.
>
> Dokument je tu proto, že vysvětluje *proč*: proč jsou segmenty rozsahy a ne
> uzly stromu, proč se zamítla varianta s Hammerspoonem, proč jsou instrukce
> promptu anglicky a příklady česky. To všechno platí dál.
>
> Nejpodstatnější věci, které v návrhu nejsou a v kódu ano:
>
> - `FragileWhitespace` — model přepisuje nezalomitelnou mezeru na jiný znak,
>   takže se křehké znaky před odesláním maskují a po opravě vracejí podle pozic
> - `LetterCasePolicy` — konfigurovatelná strategie velikosti písmen
> - `Pipeline.alignEdgeWhitespace` a `alignCase` — deterministické srovnání toho,
>   co model mění nad rámec diakritiky
> - `PipelineError.unparsableStructure` — struktura, kterou parser odmítne, se
>   neopravuje jako próza, protože by se přejmenovaly klíče
> - `ClipboardWritePlan` — rozhodnutí, které reprezentace zapsat do schránky
> - `PipelineObserver` — podklad pro `czechator fix --debug`
> - `ProviderFailure` — chyba modelu jako kategorie, aby do notifikace neunikl
>   obsah schránky ani API klíč
>
> Escapování JSONu i entit se navíc přepsalo z příznaků na indexy podle grafémů.

Datum: 2026-08-19
Stav: schváleno, připraveno k rozpracování do implementačního plánu

## 1. Účel

Nástroj pro macOS, který na stisk globální klávesové zkratky vezme obsah schránky,
doplní do něj českou diakritiku pomocí jazykového modelu a výsledek zapíše zpět.

U strukturovaných formátů (JSON, XML, HTML) se opravuje výhradně textový obsah.
Klíče, tagy, atributy, odsazení a formátování zůstávají bajtově nedotčené.

Primárním cílem je lokální model přes Ollamu; konfigurace umožňuje i cloudové
poskytovatele s OpenAI-kompatibilním API.

### Co nástroj nedělá

- Neopravuje překlepy, gramatiku ani interpunkci.
- Nepřekládá a nepřeformátovává.
- Nepracuje s obrázky ani soubory ve schránce.

## 2. Rozsah MVP

| Oblast | MVP |
|---|---|
| Zkratka | jedna, výchozí `Cmd+Ctrl+D` |
| Zdroj vstupu | schránka |
| Cíl výstupu | schránka |
| Formáty | plain text, Markdown, JSON, XML, HTML |
| Poskytovatelé | Ollama, OpenAI-kompatibilní |
| UI | ikona v menu baru, historie, okno nastavení |
| Náhled změn | ne (backlog v1.1) |

Vše, co je mimo tuto tabulku, je v sekci 14 (Backlog).

## 3. Volba architektury

Zvažovaly se tři cesty:

**A) Go CLI + Hammerspoon jako trigger.** Zamítnuto — nechceme závislost na
externím nástroji.

**B) Go daemon s vlastní registrací zkratky.** Zamítnuto — rezidentní proces bez
viditelného stavu; když spadne, uživatel se to nedozví. Řešení by vyžadovalo
watchdog a notifikace, tedy práci navíc kvůli problému, který varianta C nemá.

**C) Swift aplikace v menu baru.** Zvoleno. Ikona v menu baru je sama o sobě
indikátorem stavu. Integrace s macOS je nejlepší a Swift 6.3.3 je v prostředí
k dispozici.

Balíček je rozdělen tak, aby jádro a CLI byly přenositelné na Linux.

### Vynucená pravidla

- `CzechatorCore` **nesmí** importovat `AppKit`, `SwiftUI` ani `Security`.
- Schránka, zkratky, notifikace a Keychain žijí výhradně v `CzechatorApp`.
- Vstupem jádra je řetězec a metadata, výstupem řetězec.

Linuxové CLI je zatím konvence vynucená strukturou a code review, nikoli
deliverable s CI runnerem (viz backlog).

## 4. Struktura balíčku

```
czechator/
├─ Package.swift
├─ Makefile                      sestavení .app bundle bez Xcode
├─ Sources/
│  ├─ CzechatorCore/             Linux-safe
│  │  ├─ Pipeline.swift
│  │  ├─ Detection/
│  │  │  ├─ ClipboardInput.swift
│  │  │  └─ FormatRegistry.swift
│  │  ├─ Handlers/
│  │  │  ├─ FormatHandler.swift
│  │  │  ├─ PlainTextHandler.swift
│  │  │  ├─ JSONHandler.swift
│  │  │  ├─ XMLHandler.swift
│  │  │  └─ HTMLHandler.swift
│  │  ├─ Assembly/
│  │  │  ├─ Segment.swift
│  │  │  └─ Reassembler.swift
│  │  ├─ Verification/
│  │  │  ├─ DiacriticFolding.swift
│  │  │  └─ Verifier.swift
│  │  ├─ Providers/
│  │  │  ├─ LLMProvider.swift
│  │  │  ├─ HTTPClient.swift
│  │  │  ├─ OllamaProvider.swift
│  │  │  └─ OpenAICompatProvider.swift
│  │  ├─ Batching/SegmentBatcher.swift
│  │  ├─ IO/
│  │  │  ├─ InputSource.swift
│  │  │  └─ OutputSink.swift
│  │  └─ Config/
│  │     ├─ Config.swift
│  │     ├─ Profile.swift
│  │     ├─ FeatureFlags.swift
│  │     └─ SecretResolver.swift
│  ├─ czechator/                 CLI (macOS + Linux)
│  └─ CzechatorApp/              macOS only
│     ├─ CzechatorApp.swift      MenuBarExtra
│     ├─ AppModel.swift
│     ├─ HotKeyManager.swift
│     ├─ PasteboardSource.swift
│     ├─ PasteboardSink.swift
│     ├─ KeychainSecretResolver.swift
│     ├─ Notifications.swift
│     └─ SettingsView.swift
└─ Tests/CzechatorCoreTests/
```

Závislosti: `swift-argument-parser`, `Yams`. Nic dalšího.

## 5. Datový tok

```
InputSource.read()
   → ClipboardInput { text, uti?, richHTML? }
   → FormatRegistry.select(input)      → FormatHandler
   → handler.segments(in: text)        → [Segment]
   → SegmentBatcher.batches(segments)  → [[Segment]]
   → provider.complete(batch)          sekvenčně, po dávkách
   → Reassembler.splice(text, results) → výstupní text
   → Verifier.check(input, output)     → ok | .structuralMismatch
   → OutputSink.write(result)
```

Zápis do schránky je poslední krok a proběhne **výhradně** po úspěšné verifikaci.

## 6. Detekce formátu

Dvoustupňová.

**Krok 1 — UTI.** `NSPasteboard` drží jednu položku ve více reprezentacích, každou
pod svým UTI. Podle nich se odfiltruje to, co nemá smysl zpracovávat, a odliší se
HTML od prostého textu.

| Zdroj | Typické reprezentace |
|---|---|
| Terminál, editor | `public.utf8-plain-text` |
| Prohlížeč | `public.html`, `public.utf8-plain-text`, `com.apple.webarchive` |
| Pages, Mail, Word | `public.rtf`, `public.html`, `public.utf8-plain-text` |
| Screenshot | `public.png`, `public.tiff` |
| Finder | `public.file-url`, `public.utf8-plain-text` |

Není-li k dispozici žádná textová reprezentace, zpracování končí hláškou.

**Krok 2 — obsah.** Pro JSON, XML a Markdown neexistuje UTI, které by aplikace
reálně nastavovaly. Rozhoduje se tedy podle obsahu: `{`/`[` → pokus o JSON parser,
`<?xml`/`<` → XML parser, jinak plain.

`FormatRegistry` volá `confidence(for:)` na všech registrovaných handlerech a vybírá
nejvyšší hodnotu. `PlainTextHandler` vrací konstantní nízkou hodnotu a slouží jako
fallback.

### Zápis zpět a bohaté reprezentace

`NSPasteboard.clearContents()` maže **všechny** reprezentace. Kdyby se zapsal jen
`public.utf8-plain-text`, vložení do Wordu by přišlo o formátování.

Pravidlo: pracuje se s nejbohatší reprezentací, kterou umíme (HTML), a zapisuje se
zpět **jak upravené HTML, tak upravený plain text**.

RTF se v MVP nezpracovává. Obsahuje-li schránka pouze RTF a žádný jiný textový typ,
nástroj ohlásí nepodporovaný formát.

## 7. Segmentace a skládání zpět

### Rozhodnutí: segmenty jsou rozsahy, nikoli uzly stromu

Parsování do stromu a serializace zpět je nepoužitelné: `JSONSerialization` ztrácí
pořadí klíčů, odsazení i formátování, takže by výstup nikdy neprošel verifikací.

Handler proto nic neserializuje. Pouze najde v původním řetězci rozsahy textových
uzlů:

```swift
public enum SegmentKind: Sendable {
    case plain, jsonString, xmlText, htmlText
}

public struct Segment: Sendable {
    public let range: Range<String.Index>   // in the original text
    public let text: String                 // unescaped content to correct
    public let kind: SegmentKind
}

public protocol FormatHandler: Sendable {
    static var id: String { get }
    static func confidence(for input: ClipboardInput) -> Double
    func segments(in text: String) throws -> [Segment]
    func escape(_ corrected: String, like original: Segment) -> String
}
```

Skládání zpět je **sdílený kód** v `Reassembler`: rozsahy se nahrazují odzadu
dopředu v původním řetězci. Vše mimo rozsahy zůstává bajtově nedotčené — klíče,
tagy, atributy, komentáře, odsazení, koncové řádky.

### Escapování

Jediné netriviální místo v handleru. JSON string může obsahovat `\n` nebo `\u00e1`,
HTML může obsahovat entity (`&nbsp;`, `&amp;`). Handler obsah pro model rozbalí
a při vkládání zpět jej zabalí **ve stejném stylu, v jakém byl** — pokud originál
používal `\u` escapy, výstup je použije také.

### Co se nesegmentuje — konfigurovatelné

Které tokeny, elementy a vzory se přeskakují, **není zadrátováno v kódu**. Každý
handler dostává `SegmentationRules` z konfigurace (sekce 10). Důvod je praktický:
seznam výjimek se dolaďuje empiricky podle toho, co model reálně kazí, a přestavovat
kvůli tomu aplikaci je zbytečně pomalé.

Výchozí hodnoty jsou vestavěné a při prvním spuštění se **zapíší do konfiguračního
souboru v plné podobě**, aby uživatel viděl, co edituje. Hodnota v konfiguraci pak
výchozí seznam **nahrazuje**, nikoli doplňuje — sloučení dvou seznamů je nečitelné
a ladění by ztížilo.

Postup: najde-li se při ručním testování nový problematický vzor, přidá se nejprve
do konfigurace, ověří se, a teprve pak se promítne do vestavěných výchozích hodnot.

### Ladicí příkaz

```
czechator segments <soubor|-> [--format json|xml|html|plain]
```

Vypíše segmenty, které by šly modelu — index, rozsah, druh a text — a nic nevolá.
Spolu s konfigurovatelnými pravidly je to hlavní nástroj pro ladění segmentace.
Doplňkově `czechator segments --show-skipped` ukáže i uzly, které byly vynechány,
a pravidlo, které je vyloučilo.

## 8. Verifikace

```swift
public func fold(_ s: String) -> String
```

Invariant: `fold(output) == fold(input)` — přesná rovnost řetězců.

Chytí tedy nejen změnu struktury, ale i změnu velikosti písmen, přeformátování,
přidané nebo ubrané mezery a jakýkoli komentář, který by model připsal navíc.

Skládací tabulka je **napsaná ručně pro českou abecedu**
(á é í ó ú ý č ď ě ň ř š ť ů ž a jejich velké varianty), nikoli přes
`String.folding(options: .diacriticInsensitive)`. Důvod: ta varianta závisí na ICU,
které se v `swift-corelibs-foundation` na Linuxu chová odlišně. Toto je jediná
funkce v nástroji, která musí být deterministická napříč platformami.

### Postup při neshodě

1. Porovnají se segmenty jednotlivě, identifikují se vadné.
2. Vadné segmenty se zopakují — **jednou**.
3. Neuspějí-li ani napodruhé, schránka zůstane beze změny a ohlásí se chyba.

Před verifikací běží levnější kontrola: model dostává číslovaný seznam segmentů
a musí vrátit stejný počet položek se stejným číslováním. Nesouhlasí-li počet,
dávka se opakuje bez volání verifikátoru.

### Známé omezení

Verifikace chrání proti změnám struktury, nikoli proti nesprávně doplněné
diakritice. Anglický text, do kterého by model omylem přidal diakritiku, projde —
`fold` obou variant je totožný. Řeší se kvalitou modelu a promptem, ne
architekturou. Pro MVP přijatelné.

## 9. Poskytovatelé modelu a dávkování

```swift
public protocol LLMProvider: Sendable {
    func complete(_ prompt: Prompt) async throws -> String
}
```

`OllamaProvider` (`POST /api/chat`) a `OpenAICompatProvider`
(`POST /v1/chat/completions`) sdílejí jeden `HTTPClient` nad `URLSession`.
Na Linuxu se importuje `FoundationNetworking` přes `#if canImport`.

### Dávkování

`SegmentBatcher` skládá segmenty do dávek podle `limits.maxBatchChars`.
Dávky se zpracovávají **sekvenčně** (paralelizace je v backlogu).
Verifikace probíhá vždy nad **celým** dokumentem, nikoli nad dávkou.

Celkový vstup nad `limits.maxInputBytes` se odmítne před jakýmkoli voláním modelu.

### Prompt

**Instrukce anglicky, příklady česky.** Malé instruct modely mají instruction-tuning
převážně v angličtině a česky formulovaná pravidla u nich měřitelně zhoršují jejich
dodržování. Few-shot příklady naopak musí být české, protože demonstrují úlohu, a na
výsledek mají u malého modelu větší vliv než znění instrukcí.

Vedlejší přínos: čeština se tokenizuje hůř (diakritika se štěpí na víc tokenů),
takže anglický systémový prompt je zhruba poloviční. Dopad na latenci je ale
zanedbatelný — jde o prefill, který si Ollama při stabilním prefixu cachuje.
Prompt se proto mezi voláními **nesmí měnit**; variabilní část patří výhradně do
uživatelské zprávy.

`temperature: 0`. Přepsatelný v konfiguraci (`prompt.override`). Vstup i výstup jsou
číslované seznamy segmentů.

Kostra systémové zprávy:

```
You restore Czech diacritics. Rules:
- Output ONLY the numbered list, same count and numbering as the input.
- Change nothing except adding Czech diacritical marks.
- Never translate, reword, reformat, or fix spelling, grammar or punctuation.
- Preserve casing, whitespace, and all non-letter characters exactly.
- Leave text that is not Czech unchanged.

Example
input:
1. Prilis zlutoucky kun upel dabelske ody.
2. Vcera jsem koupil novy pocitac.
output:
1. Příliš žluťoučký kůň úpěl ďábelské ódy.
2. Včera jsem koupil nový počítač.
```

### Výchozí model

Doporučený startovní bod: `qwen3:4b-instruct` nebo `gemma3:4b`. Reasoning modely
nejsou vhodné — generují úvahy a odezva roste na desítky sekund, což je pro nástroj
typu „stiskni a vlož" nepoužitelné. Konečná volba je empirická, viz sekce 12.

## 10. Konfigurace

`~/.config/czechator/config.yaml`

```yaml
activeProfile: local

profiles:
  local:
    kind: ollama
    endpoint: http://localhost:11434
    model: qwen3:4b-instruct
    temperature: 0
    timeoutSeconds: 30
  openai:
    kind: openai-compat
    endpoint: https://api.openai.com/v1
    model: gpt-4o-mini
    apiKey: { source: keychain, account: czechator-openai }

hotkeys:
  - shortcut: cmd+ctrl+d
    source: clipboard
    sink: clipboard

limits:
  maxInputBytes: 51200
  maxBatchChars: 1500

segmentation:
  common:                       # applies to every handler
    minLength: 2
    requireLetters: true
    skipPatterns:
      - 'https?://\S+'
      - '\S+@\S+\.\S+'
  html:
    skipElements: [script, style, code, pre, kbd, samp, var]
    skipAttributes: true
    skipComments: true
  xml:
    skipElements: []
    skipAttributes: true
    skipComments: true
    skipProcessingInstructions: true
    skipCDATA: false
  json:
    skipKeys: true
    skipValuesForKeys: [id, uuid, url, href, path, type, kind]
  plain:
    skipPatterns:
      - '`[^`]+`'               # inline code
      - '^```[\s\S]*?^```'      # fenced blocks

features:
  preview: false
  history: true
  historySize: 20

prompt:
  override: null
```

Aplikace konfiguraci čte i zapisuje (okno Nastavení ji edituje), přitom
**zachovává neznámé klíče** — ruční úpravy nezmizí po prvním otevření okna.

Blok `segmentation` se při prvním spuštění vypíše kompletní, s vestavěnými
výchozími hodnotami. Uživatel tak vidí celý seznam pravidel, aniž by musel číst
zdroják. Uvedená hodnota výchozí seznam nahrazuje (viz sekce 7).

### Zkratka jako dvojice zdroj/cíl

Zkratka není akce, ale kombinace `InputSource` a `OutputSink`:

```swift
public protocol InputSource: Sendable {
    func read() throws -> ClipboardInput
}

public protocol OutputSink: Sendable {
    func write(_ result: PipelineResult) throws
}
```

V MVP existují implementace `Clipboard → Clipboard`. Abstrakce je součástí MVP,
aby `Selection → PasteInPlace` (v1.1) šlo přidat bez zásahu do jádra.

### Tajemství

```swift
public protocol SecretResolver: Sendable {
    func resolve(_ ref: SecretRef) throws -> String
}
```

macOS implementace čte Keychain, Linuxová proměnné prostředí. `CzechatorCore` tak
neimportuje `Security.framework`.

### Volba výchozí zkratky

`Cmd+B` bylo zamítnuto: globální registrace by tu zkratku ukradla systémově a ve
všech aplikacích by přestalo fungovat tučné písmo. Výchozí je `Cmd+Ctrl+D`
(D jako diakritika), plně konfigurovatelná. Nastaví-li uživatel `Cmd+B` ručně,
aplikace jej upozorní, že jde o běžnou systémovou zkratku.

## 11. Chování při chybách

Společné pravidlo: **při jakékoli chybě se schránka nemění.**

| Situace | Reakce |
|---|---|
| Ve schránce není text | „Ve schránce není text" |
| Nepodporovaný formát (jen RTF) | Notifikace s názvem formátu |
| Vstup nad limit | Notifikace s velikostí a limitem |
| Poskytovatel nedostupný | „Model neodpovídá" + jméno profilu |
| Timeout | Zrušit, schránku nechat |
| Verifikace selhala i po opakování | „Výsledek neprošel kontrolou" + detail do logu |

### Stav ikony

Tři stavy: klidový, pracující, chyba.

| Událost | Reakce |
|---|---|
| Chyba | Notifikace (klikatelná) + odznak na ikoně |
| Klik na notifikaci | Otevře popover s detailem, odznak zmizí |
| Otevření menu z ikony | Položka „Poslední chyba: …", odznak zmizí |
| Další úspěšné použití | Odznak zmizí i bez potvrzení |

Chybový stav nikdy nepřežije jedno kliknutí. Detail zůstává dostupný v historii.

## 12. Testovací strategie

**Handlery.** Sada fixtur `vstup → očekávané segmenty` pro každý formát, včetně
escapovaných JSON stringů, HTML entit, CDATA, vnořených struktur a prázdných uzlů.
Fixtura nese i `SegmentationRules`, takže testy pokrývají jak výchozí pravidla, tak
netriviální konfigurace.
Klíčový test: `splice(segments)` bez modifikace musí vrátit **bajtově identický**
vstup. Chytne většinu chyb v extrakci rozsahů.

**Verifikace.** Property testy: pro náhodný text platí
`fold(addDiacritics(t)) == fold(t)`; libovolná změna mimo diakritiku musí být
zachycena.

**Pipeline.** S falešným poskytovatelem vracejícím předem dané odpovědi včetně
vadných (chybějící segment, přidaný komentář, přeformátovaný JSON). Ověřuje se,
že vadný výstup neprojde a schránka zůstane nedotčená.

**Kvalita modelu.** Samostatná sada ~50 českých vzorků s referenčním výstupem,
spouštěná ručně proti živé Ollamě. Neběží v CI. Slouží k volbě modelu a k porovnání
při změně promptu.

## 13. Sestavení

V prostředí jsou pouze Command Line Tools, nikoli plné Xcode. `.app` bundle se
proto skládá ručně v `Makefile`: SwiftPM postaví executable, skript k němu doplní
`Info.plist` a `Resources` do adresářové struktury bundlu a provede
`codesign --sign -`.

Důsledek: v repozitáři není `.xcodeproj`, build je reprodukovatelný z příkazové
řádky. Pro distribuci mimo vlastní stroj by bylo nutné Developer ID a notarizace —
mimo rozsah MVP.

### Rozhodnutí: Xcode se zatím neinstaluje

Ověřeno prakticky, co v CLT funguje: `swift build` (včetně SwiftUI `MenuBarExtra`
a `Carbon.HIToolbox`), `sourcekit-lsp`, `swift-format`, `lldb`/`lldb-dap`,
`codesign`, `notarytool`, `iconutil`. Nefungují `actool` a `ibtool` (shimy
vyžadující Xcode).

Vývojové prostředí je tedy VS Code se Swift rozšířením nad `sourcekit-lsp`
a `lldb-dap` — autocomplete, diagnostika, formátování i breakpointy.

#### Testy vyžadují dodatečné přepínače

`swift test` samo o sobě **selže**: `XCTest.framework` v CLT vůbec není a
`Testing.framework` sice je, ale mimo výchozí vyhledávací cesty.

Testovacím frameworkem je proto **swift-testing** (`import Testing`), nikoli
XCTest, a spouští se s doplněnými cestami:

```
FD=$(xcode-select -p)/Library/Developer/Frameworks
LD=$(xcode-select -p)/Library/Developer/usr/lib
swift test -Xswiftc -F -Xswiftc "$FD" \
           -Xlinker -F -Xlinker "$FD" \
           -Xlinker -rpath -Xlinker "$FD" \
           -Xlinker -rpath -Xlinker "$LD"
```

Ověřeno, že takto testy proběhnou a správně hlásí úspěch i selhání. Přepínače
zapouzdřuje `make test`, aby je nikdo nemusel opisovat. Po instalaci Xcode jsou
zbytečné, ale neškodí — `Makefile` je přidává jen tehdy, když ty adresáře
existují.

Z toho plynou dvě závazná omezení:

- **Žádné asset catalogy** (`.xcassets`). Ikona v menu baru musí být SF Symbol
  přes `MenuBarExtra(systemImage:)`, ikona aplikace se skládá z PNG přes
  `iconutil`. Návrh s tím počítá, reálná ztráta je nulová.
- **Žádné SwiftUI Previews.** Ladění UI probíhá cyklem přeložit–spustit.
  Okno Nastavení proto držet jednoduché; pokud se ukáže, že je iterace na UI
  příliš pomalá, instalace Xcode je kdykoli možná a nic v repozitáři nemění.

## 14. Backlog

### v1.1
- `Selection → PasteInPlace` na `Cmd+Ctrl+C`: syntetické `Cmd+C` přes `CGEventPost`,
  čekání na změnu `pasteboard.changeCount`, po zpracování syntetické `Cmd+V`.
  Vyžaduje oprávnění Accessibility. Ošetřit secure input (pole s hesly) a stav,
  kdy uživatel nemá nic označeno.
- Náhled s diffem před přepsáním schránky (`features.preview`).
- Ukazatel průběhu a zrušení dlouhého běhu.

### v1.2
- RTF handler.
- YAML a CSV handlery.
- Blokace zkratky podle aktivní aplikace.
- Více zkratek s různými profily (lokální / cloud).

### Později
- Automatický fallback lokální → cloud při timeoutu nebo selhání verifikace.
- Náhled spouštěný podle confidence modelu.
- Nativní Anthropic provider.
- Linux CI a release artefakty (Static Linux SDK, musl).
- Paralelní zpracování dávek.

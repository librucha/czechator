# Czechator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aplikace v menu baru macOS, která na stisk `Cmd+Ctrl+D` doplní do obsahu schránky českou diakritiku, aniž by u JSON/XML/HTML sáhla na strukturu.

**Architecture:** Rozdělený SwiftPM balíček. `CzechatorCore` je platformně neutrální jádro: handlery formátů vracejí **rozsahy** textových uzlů v původním řetězci, model opravuje jen jejich obsah a `Reassembler` je vkládá zpět, takže vše mimo rozsahy zůstává bajtově nedotčené. Před zápisem do schránky musí platit `fold(výstup) == fold(vstup)`. `czechator` je CLI nad jádrem, `CzechatorApp` je SwiftUI slupka s globální zkratkou.

**Tech Stack:** Swift 6.3, SwiftPM, SwiftUI (`MenuBarExtra`), `Carbon.HIToolbox` (globální zkratka), `AppKit` (`NSPasteboard`), `UserNotifications`, `Security` (Keychain), `Yams`, `swift-argument-parser`, testy přes **swift-testing**.

**Spec:** `docs/superpowers/specs/2026-08-19-czechator-design.md`

## Global Constraints

- **Swift tools version:** `6.0`, platforma `.macOS(.v14)`.
- **Závislosti:** pouze `swift-argument-parser` (from 1.5.0) a `Yams` (from 5.1.0). Žádné další.
- **`CzechatorCore` NESMÍ importovat `AppKit`, `SwiftUI`, `Security` ani `Carbon`.** Porušení je důvod k odmítnutí tasku.
- **Jazyk:** identifikátory a komentáře v kódu anglicky. Uživatelské hlášky česky. Commit messages česky.
- **Testy se spouštějí výhradně přes `make test`**, nikdy holým `swift test` — bez doplněných `-F` a `-rpath` přepínačů `Testing.framework` nenajde. Testovací framework je `import Testing` (swift-testing), **nikoli XCTest** — ten v Command Line Tools vůbec není.
- **Žádné `.xcassets`, žádný `.xcodeproj`.** Ikony jsou SF Symbols, build jede z `Makefile`.
- **Výchozí zkratka:** `cmd+ctrl+d`. Nikdy `cmd+b`.
- **Prompt:** instrukce anglicky, few-shot příklady česky.
- **Nikdy nezapisuj do schránky neověřený výsledek.** Zápis je poslední krok po úspěšné verifikaci.
- Po každém tasku commit. Nikdy nepushuj bez vyzvání.

---

## File Structure

### `Sources/CzechatorCore` — jádro, přenositelné na Linux

| Soubor | Odpovědnost |
|---|---|
| `Verification/DiacriticFolding.swift` | Ruční skládací tabulka české abecedy. Jediná funkce, která musí být deterministická napříč platformami. |
| `Verification/DiacriticVerifier.swift` | Kontrola invariantu `fold(out) == fold(in)`, identifikace vadných segmentů. |
| `Assembly/Segment.swift` | `Segment` (rozsah + raw + rozbalený text + druh), `SegmentKind`. |
| `Assembly/Reassembler.swift` | Vložení náhrad do původního řetězce. Sdílené pro všechny handlery. |
| `Config/SegmentationRules.swift` | Konfigurovatelná pravidla přeskakování, vestavěné výchozí hodnoty. |
| `Handlers/SegmentBuilder.swift` | Sdílená mechanika: vyloučené spany, ořez bílých znaků, filtry délky a písmen. |
| `Handlers/FormatHandler.swift` | Protokol handleru. |
| `Handlers/PlainTextHandler.swift` | Prostý text a Markdown — kandidát je řádek. |
| `Handlers/JSONScanner.swift` | Ruční skener JSONu vracející rozsahy řetězcových literálů a jejich roli (klíč/hodnota). |
| `Handlers/JSONHandler.swift` | Filtrace podle `JSONRules`, JSON unescape/escape se zachováním stylu. |
| `Handlers/MarkupScanner.swift` | Sdílený skener značkovacích jazyků: textové uzly, zásobník elementů, komentáře, PI, CDATA. |
| `Handlers/XMLHandler.swift` | XML nad `MarkupScanner`, XML entity. |
| `Handlers/HTMLHandler.swift` | HTML nad `MarkupScanner`, HTML entity, jiné výchozí `skipElements`. |
| `Detection/ClipboardInput.swift` | Vstup jádra: text, UTI, plain fallback. |
| `Detection/FormatRegistry.swift` | Výběr handleru podle `confidence`. |
| `Providers/LLMProvider.swift` | `Prompt`, protokol poskytovatele. |
| `Providers/HTTPClient.swift` | Tenký POST klient nad `URLSession`, na Linuxu přes `FoundationNetworking`. |
| `Providers/OllamaProvider.swift` | `POST /api/chat`. |
| `Providers/OpenAICompatProvider.swift` | `POST /chat/completions` + autorizace. |
| `Providers/NumberedList.swift` | Kódování a parsování číslovaného seznamu segmentů. |
| `Providers/PromptBuilder.swift` | Vestavěná systémová zpráva, sestavení promptu. |
| `Batching/SegmentBatcher.swift` | Rozdělení segmentů do dávek podle `maxBatchChars`. |
| `Pipeline.swift` | Orchestrace celého toku včetně jednoho opakování vadných segmentů. |
| `Config/Config.swift` | Datové typy konfigurace. |
| `Config/ConfigStore.swift` | Načtení a zápis YAML se zachováním neznámých klíčů. |
| `Config/SecretResolver.swift` | `SecretRef` a protokol; implementace jsou mimo jádro. |
| `IO/InputSource.swift`, `IO/OutputSink.swift` | Protokoly zdroje a cíle. |

### `Sources/czechator` — CLI

| Soubor | Odpovědnost |
|---|---|
| `main.swift` | Kořenový příkaz `czechator`. |
| `SegmentsCommand.swift` | `czechator segments` — ladicí výpis segmentů. |
| `FixCommand.swift` | `czechator fix` — celý průchod nad stdin/souborem. |
| `CLIEnvironment.swift` | Sestavení registru, providera a konfigurace z argumentů. |

### `Sources/CzechatorApp` — macOS slupka

| Soubor | Odpovědnost |
|---|---|
| `CzechatorApp.swift` | `MenuBarExtra`, `Settings`, `Window` s detailem chyby. |
| `AppModel.swift` | Stav ikony, historie, spuštění pipeline. |
| `HotKeyManager.swift` | Parsování zkratky a registrace přes `RegisterEventHotKey`. |
| `PasteboardSource.swift` | Čtení schránky včetně UTI. |
| `PasteboardSink.swift` | Zápis HTML i plain reprezentace. |
| `KeychainSecretResolver.swift` | Čtení klíčů z Keychainu. |
| `NotificationCenterBridge.swift` | Notifikace a reakce na kliknutí. |
| `SettingsView.swift` | Okno nastavení. |

---

## Task 1: Kostra balíčku, Makefile a skládání diakritiky

**Files:**
- Create: `Package.swift`
- Create: `Makefile`
- Create: `.gitattributes`
- Create: `Sources/CzechatorCore/Verification/DiacriticFolding.swift`
- Create: `Sources/czechator/main.swift`
- Test: `Tests/CzechatorCoreTests/DiacriticFoldingTests.swift`

**Interfaces:**
- Consumes: nic.
- Produces: `DiacriticFolding.fold(_ s: String) -> String`. Cíl `make test`, který musí být od této chvíle jediný způsob spouštění testů.

- [ ] **Step 1: Napiš padající test**

`Tests/CzechatorCoreTests/DiacriticFoldingTests.swift`:

```swift
import Testing
@testable import CzechatorCore

@Test func foldsAllCzechLowercaseDiacritics() {
    #expect(DiacriticFolding.fold("příliš žluťoučký kůň úpěl ďábelské ódy")
            == "prilis zlutoucky kun upel dabelske ody")
}

@Test func foldsUppercaseDiacritics() {
    #expect(DiacriticFolding.fold("ČERVENÝ ŘEDKVIČKA ŽÍŽALA ÚŽASNÝ")
            == "CERVENY REDKVICKA ZIZALA UZASNY")
}

@Test func leavesNonCzechCharactersUntouched() {
    let input = "Grüße, señor — 42% {\"a\": 1}\n\ttab"
    #expect(DiacriticFolding.fold(input) == input)
}

@Test func handlesDecomposedInput() {
    // "s" followed by COMBINING CARON must fold like the precomposed "š"
    #expect(DiacriticFolding.fold("prili\u{0073}\u{030C}") == "prilis")
}

@Test func isIdentityOnTextWithoutDiacritics() {
    #expect(DiacriticFolding.fold("Prilis zlutoucky kun") == "Prilis zlutoucky kun")
}
```

- [ ] **Step 2: Spusť test a ověř, že selže**

Run: `make test`
Expected: FAIL — balíček zatím neexistuje, `swift test` skončí chybou `no such module 'CzechatorCore'` nebo `Package.swift not found`.

- [ ] **Step 3: Vytvoř balíček, Makefile a implementaci**

`Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

// The menu bar app is macOS-only; on Linux only the core and the CLI are built.
#if os(macOS)
let appProducts: [Product] = [.executable(name: "CzechatorApp", targets: ["CzechatorApp"])]
let appTargets: [Target] = [.executableTarget(name: "CzechatorApp", dependencies: ["CzechatorCore"])]
#else
let appProducts: [Product] = []
let appTargets: [Target] = []
#endif

let package = Package(
    name: "czechator",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CzechatorCore", targets: ["CzechatorCore"]),
        .executable(name: "czechator", targets: ["czechator"]),
    ] + appProducts,
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "CzechatorCore",
            dependencies: [.product(name: "Yams", package: "Yams")]
        ),
        .executableTarget(
            name: "czechator",
            dependencies: [
                "CzechatorCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "CzechatorCoreTests", dependencies: ["CzechatorCore"]),
    ] + appTargets
)
```

`Makefile`:

```make
DEVDIR := $(shell xcode-select -p)
SWIFT_FORMAT := $(DEVDIR)/usr/bin/swift-format

# Command Line Tools ship Testing.framework outside the default search paths.
# With full Xcode these directories do not exist and no flags are added.
TEST_FRAMEWORKS := $(wildcard $(DEVDIR)/Library/Developer/Frameworks)
TEST_LIBS := $(wildcard $(DEVDIR)/Library/Developer/usr/lib)

TESTFLAGS :=
ifneq ($(TEST_FRAMEWORKS),)
TESTFLAGS += -Xswiftc -F -Xswiftc $(TEST_FRAMEWORKS) \
             -Xlinker -F -Xlinker $(TEST_FRAMEWORKS) \
             -Xlinker -rpath -Xlinker $(TEST_FRAMEWORKS)
endif
ifneq ($(TEST_LIBS),)
TESTFLAGS += -Xlinker -rpath -Xlinker $(TEST_LIBS)
endif

.PHONY: build test fmt clean

build:
	swift build

test:
	swift test $(TESTFLAGS)

fmt:
	$(SWIFT_FORMAT) format -i -r Sources Tests

clean:
	rm -rf .build build
```

`.gitattributes`:

```
* text=auto eol=lf
```

`Sources/CzechatorCore/Verification/DiacriticFolding.swift`:

```swift
/// Removes Czech diacritical marks.
///
/// Deliberately a hand-written table rather than
/// `String.folding(options: .diacriticInsensitive)`: that path goes through ICU,
/// which behaves differently in swift-corelibs-foundation on Linux. This is the
/// one function in the tool that must be byte-for-byte deterministic everywhere.
public enum DiacriticFolding {

    private static let table: [Character: Character] = [
        "á": "a", "é": "e", "í": "i", "ó": "o", "ú": "u", "ý": "y",
        "č": "c", "ď": "d", "ě": "e", "ň": "n", "ř": "r",
        "š": "s", "ť": "t", "ů": "u", "ž": "z",
        "Á": "A", "É": "E", "Í": "I", "Ó": "O", "Ú": "U", "Ý": "Y",
        "Č": "C", "Ď": "D", "Ě": "E", "Ň": "N", "Ř": "R",
        "Š": "S", "Ť": "T", "Ů": "U", "Ž": "Z",
    ]

    /// Swift compares and hashes `Character` by canonical equivalence, so a
    /// decomposed "s" + U+030C matches the precomposed "š" key.
    public static func fold(_ s: String) -> String {
        String(s.map { table[$0] ?? $0 })
    }
}
```

`Sources/czechator/main.swift` (dočasný vstupní bod, Task 17 ho smaže a nahradí `Czechator.swift`):

```swift
import CzechatorCore

// Replaced by the real ArgumentParser entry point in Task 18.
print(DiacriticFolding.fold("Prilis zlutoucky kun"))
```

- [ ] **Step 4: Spusť test a ověř, že projde**

Run: `make test`
Expected: PASS — 5 testů zeleně, výstup obsahuje `Test run with 5 tests`.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Makefile .gitattributes Sources Tests
git commit -m "feat: kostra balíčku a skládání české diakritiky"
```

---

## Task 2: Segment a Reassembler

**Files:**
- Create: `Sources/CzechatorCore/Assembly/Segment.swift`
- Create: `Sources/CzechatorCore/Assembly/Reassembler.swift`
- Test: `Tests/CzechatorCoreTests/ReassemblerTests.swift`

**Interfaces:**
- Consumes: nic.
- Produces:
  - `enum SegmentKind: String, Sendable, Codable, Equatable { case plain, jsonString, xmlText, htmlText }`
  - `struct Segment: Sendable, Equatable` s `range: Range<String.Index>`, `raw: String`, `text: String`, `kind: SegmentKind` a memberwise `init`.
  - `enum ReassemblyError: Error, Equatable { case countMismatch(expected: Int, got: Int), overlappingRanges }`
  - `Reassembler.splice(_ original: String, segments: [Segment], replacements: [String]) throws -> String`

- [ ] **Step 1: Napiš padající test**

`Tests/CzechatorCoreTests/ReassemblerTests.swift`:

```swift
import Testing
@testable import CzechatorCore

private func segment(_ text: String, _ range: Range<String.Index>, raw: String? = nil) -> Segment {
    Segment(range: range, raw: raw ?? text, text: text, kind: .plain)
}

@Test func spliceWithRawIsIdentity() throws {
    let original = "{\"a\": \"ahoj\", \"b\": \"svete\"}"
    let first = original.range(of: "ahoj")!
    let second = original.range(of: "svete")!
    let segments = [segment("ahoj", first), segment("svete", second)]

    let result = try Reassembler.splice(original, segments: segments,
                                        replacements: segments.map(\.raw))
    #expect(result == original)
}

@Test func splicesReplacementsInPlace() throws {
    let original = "{\"a\": \"ahoj\", \"b\": \"svete\"}"
    let segments = [
        segment("ahoj", original.range(of: "ahoj")!),
        segment("svete", original.range(of: "svete")!),
    ]

    let result = try Reassembler.splice(original, segments: segments,
                                        replacements: ["ahoj", "světe"])
    #expect(result == "{\"a\": \"ahoj\", \"b\": \"světe\"}")
}

@Test func acceptsSegmentsInAnyOrder() throws {
    let original = "prvni druhy"
    let segments = [
        segment("druhy", original.range(of: "druhy")!),
        segment("prvni", original.range(of: "prvni")!),
    ]

    let result = try Reassembler.splice(original, segments: segments,
                                        replacements: ["druhý", "první"])
    #expect(result == "první druhý")
}

@Test func rejectsCountMismatch() {
    let original = "ahoj"
    let segments = [segment("ahoj", original.startIndex..<original.endIndex)]

    #expect(throws: ReassemblyError.countMismatch(expected: 1, got: 2)) {
        try Reassembler.splice(original, segments: segments, replacements: ["a", "b"])
    }
}

@Test func rejectsOverlappingRanges() {
    let original = "abcdef"
    let a = original.startIndex..<original.index(original.startIndex, offsetBy: 4)
    let b = original.index(original.startIndex, offsetBy: 2)..<original.endIndex

    #expect(throws: ReassemblyError.overlappingRanges) {
        try Reassembler.splice(original,
                               segments: [segment("abcd", a), segment("cdef", b)],
                               replacements: ["X", "Y"])
    }
}

@Test func preservesEmptySegmentList() throws {
    let original = "beze zmeny"
    #expect(try Reassembler.splice(original, segments: [], replacements: []) == original)
}
```

- [ ] **Step 2: Spusť test a ověř, že selže**

Run: `make test`
Expected: FAIL — `cannot find 'Segment' in scope`, `cannot find 'Reassembler' in scope`.

- [ ] **Step 3: Napiš implementaci**

`Sources/CzechatorCore/Assembly/Segment.swift`:

```swift
public enum SegmentKind: String, Sendable, Codable, Equatable {
    case plain
    case jsonString
    case xmlText
    case htmlText
}

/// One correctable text node, located by its range in the original document.
///
/// Handlers never serialize anything — they only report ranges. Everything
/// outside those ranges is guaranteed to survive byte-for-byte.
public struct Segment: Sendable, Equatable {
    /// Range in the original document.
    public let range: Range<String.Index>
    /// Original source text at `range`, still escaped.
    public let raw: String
    /// Unescaped content handed to the model.
    public let text: String
    public let kind: SegmentKind

    public init(range: Range<String.Index>, raw: String, text: String, kind: SegmentKind) {
        self.range = range
        self.raw = raw
        self.text = text
        self.kind = kind
    }
}
```

`Sources/CzechatorCore/Assembly/Reassembler.swift`:

```swift
public enum ReassemblyError: Error, Equatable {
    case countMismatch(expected: Int, got: Int)
    case overlappingRanges
}

public enum Reassembler {

    /// Rebuilds the document by walking it forward and swapping each segment's
    /// range for its replacement. Builds a new string rather than mutating in
    /// place, because String indices are not guaranteed to stay valid across
    /// mutations of the same value.
    public static func splice(_ original: String,
                              segments: [Segment],
                              replacements: [String]) throws -> String {
        guard segments.count == replacements.count else {
            throw ReassemblyError.countMismatch(expected: segments.count, got: replacements.count)
        }

        let pairs = zip(segments, replacements)
            .sorted { $0.0.range.lowerBound < $1.0.range.lowerBound }

        var out = ""
        out.reserveCapacity(original.count)
        var cursor = original.startIndex

        for (segment, replacement) in pairs {
            guard segment.range.lowerBound >= cursor else {
                throw ReassemblyError.overlappingRanges
            }
            out += original[cursor..<segment.range.lowerBound]
            out += replacement
            cursor = segment.range.upperBound
        }
        out += original[cursor...]
        return out
    }
}
```

- [ ] **Step 4: Spusť test a ověř, že projde**

Run: `make test`
Expected: PASS — všech 11 testů (5 z Tasku 1 + 6 nových).

- [ ] **Step 5: Commit**

```bash
git add Sources/CzechatorCore/Assembly Tests/CzechatorCoreTests/ReassemblerTests.swift
git commit -m "feat: segmenty jako rozsahy a jejich skládání zpět"
```

---
## Task 3: Pravidla segmentace a sdílený SegmentBuilder

**Files:**
- Create: `Sources/CzechatorCore/Config/SegmentationRules.swift`
- Create: `Sources/CzechatorCore/Handlers/SegmentBuilder.swift`
- Test: `Tests/CzechatorCoreTests/SegmentBuilderTests.swift`

**Interfaces:**
- Consumes: `Segment`, `SegmentKind` (Task 2).
- Produces:
  - `CommonRules`, `HTMLRules`, `XMLRules`, `JSONRules`, `PlainRules`, `SegmentationRules` — vše `Sendable, Codable, Equatable`, každý se statickou `builtIn` a s dekodérem, který chybějící klíče doplní z `builtIn`.
  - `SegmentationRules.builtIn`
  - `SegmentBuilder.init(common: CommonRules, extraSkipPatterns: [String]) throws`
  - `SegmentBuilder.prepared(for text: String) -> PreparedSegmenter`
  - `PreparedSegmenter.build(candidate: Range<String.Index>, kind: SegmentKind, unescape: (Substring) -> String) -> [Segment]`
  - `PreparedSegmenter.excludedSpans: [Range<String.Index>]`

- [ ] **Step 1: Napiš padající test**

`Tests/CzechatorCoreTests/SegmentBuilderTests.swift`:

```swift
import Testing
@testable import CzechatorCore

private func build(_ text: String,
                   rules: CommonRules = .builtIn,
                   extra: [String] = []) throws -> [Segment] {
    let prepared = try SegmentBuilder(common: rules, extraSkipPatterns: extra).prepared(for: text)
    return prepared.build(candidate: text.startIndex..<text.endIndex, kind: .plain) { String($0) }
}

@Test func keepsPlainTextAsSingleSegment() throws {
    let segments = try build("Prilis zlutoucky kun")
    #expect(segments.map(\.text) == ["Prilis zlutoucky kun"])
}

@Test func splitsAroundURLs() throws {
    let segments = try build("Podivej se na https://example.com/a?b=1 a rekni mi to")
    #expect(segments.map(\.text) == ["Podivej se na", "a rekni mi to"])
}

@Test func splitsAroundEmails() throws {
    let segments = try build("Napis na petr@example.com prosim")
    #expect(segments.map(\.text) == ["Napis na", "prosim"])
}

@Test func trimsSurroundingWhitespaceOutOfSegments() throws {
    let text = "   ahoj svete   "
    let segments = try build(text)
    #expect(segments.count == 1)
    #expect(segments[0].text == "ahoj svete")
    #expect(text[segments[0].range] == "ahoj svete")
}

@Test func dropsSegmentsShorterThanMinLength() throws {
    let rules = CommonRules(minLength: 5, requireLetters: true, skipPatterns: [])
    #expect(try build("ahoj", rules: rules).isEmpty)
    #expect(try build("ahojky", rules: rules).map(\.text) == ["ahojky"])
}

@Test func dropsSegmentsWithoutLetters() throws {
    #expect(try build("12345 -- 67").isEmpty)
}

@Test func appliesMultilineExtraPatterns() throws {
    let text = "pred\n```\nkod ktery se neopravuje\n```\npo"
    let segments = try build(text, extra: [#"^```[\s\S]*?^```"#])
    #expect(segments.map(\.text) == ["pred", "po"])
}

@Test func mergesOverlappingExcludedSpans() throws {
    let prepared = try SegmentBuilder(common: .builtIn,
                                      extraSkipPatterns: [#"example\.com/\S*"#])
        .prepared(for: "x https://example.com/a y")
    #expect(prepared.excludedSpans.count == 1)
}
```

- [ ] **Step 2: Spusť test a ověř, že selže**

Run: `make test`
Expected: FAIL — `cannot find 'SegmentBuilder' in scope`, `cannot find 'CommonRules' in scope`.

- [ ] **Step 3: Napiš implementaci**

`Sources/CzechatorCore/Config/SegmentationRules.swift`:

```swift
/// Rules shared by every handler.
public struct CommonRules: Sendable, Codable, Equatable {
    public var minLength: Int
    public var requireLetters: Bool
    /// Regular expressions whose matches are excluded from every segment.
    public var skipPatterns: [String]

    public static let builtIn = CommonRules(
        minLength: 2,
        requireLetters: true,
        skipPatterns: [#"https?://\S+"#, #"\S+@\S+\.\S+"#]
    )

    public init(minLength: Int, requireLetters: Bool, skipPatterns: [String]) {
        self.minLength = minLength
        self.requireLetters = requireLetters
        self.skipPatterns = skipPatterns
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CommonRules.builtIn
        minLength = try c.decodeIfPresent(Int.self, forKey: .minLength) ?? d.minLength
        requireLetters = try c.decodeIfPresent(Bool.self, forKey: .requireLetters) ?? d.requireLetters
        skipPatterns = try c.decodeIfPresent([String].self, forKey: .skipPatterns) ?? d.skipPatterns
    }
}

public struct HTMLRules: Sendable, Codable, Equatable {
    public var skipElements: [String]
    public var skipAttributes: Bool
    public var skipComments: Bool

    public static let builtIn = HTMLRules(
        skipElements: ["script", "style", "code", "pre", "kbd", "samp", "var"],
        skipAttributes: true,
        skipComments: true
    )

    public init(skipElements: [String], skipAttributes: Bool, skipComments: Bool) {
        self.skipElements = skipElements
        self.skipAttributes = skipAttributes
        self.skipComments = skipComments
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = HTMLRules.builtIn
        skipElements = try c.decodeIfPresent([String].self, forKey: .skipElements) ?? d.skipElements
        skipAttributes = try c.decodeIfPresent(Bool.self, forKey: .skipAttributes) ?? d.skipAttributes
        skipComments = try c.decodeIfPresent(Bool.self, forKey: .skipComments) ?? d.skipComments
    }
}

public struct XMLRules: Sendable, Codable, Equatable {
    public var skipElements: [String]
    public var skipAttributes: Bool
    public var skipComments: Bool
    public var skipProcessingInstructions: Bool
    public var skipCDATA: Bool

    public static let builtIn = XMLRules(
        skipElements: [],
        skipAttributes: true,
        skipComments: true,
        skipProcessingInstructions: true,
        skipCDATA: false
    )

    public init(skipElements: [String], skipAttributes: Bool, skipComments: Bool,
                skipProcessingInstructions: Bool, skipCDATA: Bool) {
        self.skipElements = skipElements
        self.skipAttributes = skipAttributes
        self.skipComments = skipComments
        self.skipProcessingInstructions = skipProcessingInstructions
        self.skipCDATA = skipCDATA
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = XMLRules.builtIn
        skipElements = try c.decodeIfPresent([String].self, forKey: .skipElements) ?? d.skipElements
        skipAttributes = try c.decodeIfPresent(Bool.self, forKey: .skipAttributes) ?? d.skipAttributes
        skipComments = try c.decodeIfPresent(Bool.self, forKey: .skipComments) ?? d.skipComments
        skipProcessingInstructions = try c.decodeIfPresent(Bool.self, forKey: .skipProcessingInstructions)
            ?? d.skipProcessingInstructions
        skipCDATA = try c.decodeIfPresent(Bool.self, forKey: .skipCDATA) ?? d.skipCDATA
    }
}

public struct JSONRules: Sendable, Codable, Equatable {
    public var skipKeys: Bool
    public var skipValuesForKeys: [String]

    public static let builtIn = JSONRules(
        skipKeys: true,
        skipValuesForKeys: ["id", "uuid", "url", "href", "path", "type", "kind"]
    )

    public init(skipKeys: Bool, skipValuesForKeys: [String]) {
        self.skipKeys = skipKeys
        self.skipValuesForKeys = skipValuesForKeys
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = JSONRules.builtIn
        skipKeys = try c.decodeIfPresent(Bool.self, forKey: .skipKeys) ?? d.skipKeys
        skipValuesForKeys = try c.decodeIfPresent([String].self, forKey: .skipValuesForKeys)
            ?? d.skipValuesForKeys
    }
}

public struct PlainRules: Sendable, Codable, Equatable {
    public var skipPatterns: [String]

    public static let builtIn = PlainRules(skipPatterns: [
        #"`[^`]+`"#,
        #"^```[\s\S]*?^```"#,
    ])

    public init(skipPatterns: [String]) { self.skipPatterns = skipPatterns }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        skipPatterns = try c.decodeIfPresent([String].self, forKey: .skipPatterns)
            ?? PlainRules.builtIn.skipPatterns
    }
}

public struct SegmentationRules: Sendable, Codable, Equatable {
    public var common: CommonRules
    public var html: HTMLRules
    public var xml: XMLRules
    public var json: JSONRules
    public var plain: PlainRules

    public static let builtIn = SegmentationRules(
        common: .builtIn, html: .builtIn, xml: .builtIn, json: .builtIn, plain: .builtIn
    )

    public init(common: CommonRules, html: HTMLRules, xml: XMLRules,
                json: JSONRules, plain: PlainRules) {
        self.common = common
        self.html = html
        self.xml = xml
        self.json = json
        self.plain = plain
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        common = try c.decodeIfPresent(CommonRules.self, forKey: .common) ?? .builtIn
        html = try c.decodeIfPresent(HTMLRules.self, forKey: .html) ?? .builtIn
        xml = try c.decodeIfPresent(XMLRules.self, forKey: .xml) ?? .builtIn
        json = try c.decodeIfPresent(JSONRules.self, forKey: .json) ?? .builtIn
        plain = try c.decodeIfPresent(PlainRules.self, forKey: .plain) ?? .builtIn
    }
}
```

`Sources/CzechatorCore/Handlers/SegmentBuilder.swift`:

```swift
import Foundation

/// Shared segmentation mechanics: excluded spans, whitespace trimming,
/// length and letter filters. Handlers only decide *where* the candidate
/// ranges are; everything else happens here so the rules apply uniformly.
///
/// `@unchecked Sendable`: NSRegularExpression is documented as thread-safe
/// and the array is never mutated after init.
public struct SegmentBuilder: @unchecked Sendable {

    private let minLength: Int
    private let requireLetters: Bool
    private let regexes: [NSRegularExpression]

    public init(common: CommonRules, extraSkipPatterns: [String] = []) throws {
        minLength = common.minLength
        requireLetters = common.requireLetters
        regexes = try (common.skipPatterns + extraSkipPatterns).map {
            try NSRegularExpression(pattern: $0, options: [.anchorsMatchLines])
        }
    }

    /// Computes the excluded spans once for the whole document, so multi-line
    /// patterns (fenced code blocks) work even when candidates are single lines.
    public func prepared(for text: String) -> PreparedSegmenter {
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        var spans: [Range<String.Index>] = []
        for regex in regexes {
            for match in regex.matches(in: text, options: [], range: full) {
                if let range = Range(match.range, in: text), !range.isEmpty {
                    spans.append(range)
                }
            }
        }
        return PreparedSegmenter(text: text,
                                 excludedSpans: PreparedSegmenter.merge(spans),
                                 minLength: minLength,
                                 requireLetters: requireLetters)
    }
}

public struct PreparedSegmenter: Sendable {

    public let text: String
    public let excludedSpans: [Range<String.Index>]
    public let minLength: Int
    public let requireLetters: Bool

    /// Splits `candidate` around the excluded spans, trims and filters the
    /// remaining pieces, and turns each into a `Segment`.
    public func build(candidate: Range<String.Index>,
                      kind: SegmentKind,
                      unescape: (Substring) -> String) -> [Segment] {
        var pieces: [Range<String.Index>] = []
        var cursor = candidate.lowerBound

        for span in excludedSpans
        where span.upperBound > candidate.lowerBound && span.lowerBound < candidate.upperBound {
            let lower = Swift.max(span.lowerBound, candidate.lowerBound)
            if lower > cursor { pieces.append(cursor..<lower) }
            cursor = Swift.max(cursor, Swift.min(span.upperBound, candidate.upperBound))
        }
        if cursor < candidate.upperBound { pieces.append(cursor..<candidate.upperBound) }

        return pieces.compactMap { piece in
            guard let trimmed = trim(piece) else { return nil }
            let body = text[trimmed]
            guard body.count >= minLength else { return nil }
            if requireLetters, !body.contains(where: { $0.isLetter }) { return nil }
            return Segment(range: trimmed, raw: String(body), text: unescape(body), kind: kind)
        }
    }

    /// Whitespace stays outside segments so the model cannot swallow it.
    private func trim(_ range: Range<String.Index>) -> Range<String.Index>? {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, text[lower].isWhitespace { lower = text.index(after: lower) }
        while upper > lower, text[text.index(before: upper)].isWhitespace {
            upper = text.index(before: upper)
        }
        return lower < upper ? lower..<upper : nil
    }

    static func merge(_ spans: [Range<String.Index>]) -> [Range<String.Index>] {
        let sorted = spans.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for span in sorted {
            if let last = merged.last, span.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<Swift.max(last.upperBound, span.upperBound)
            } else {
                merged.append(span)
            }
        }
        return merged
    }
}
```

- [ ] **Step 4: Spusť test a ověř, že projde**

Run: `make test`
Expected: PASS — 19 testů celkem.

- [ ] **Step 5: Commit**

```bash
git add Sources/CzechatorCore/Config/SegmentationRules.swift \
        Sources/CzechatorCore/Handlers/SegmentBuilder.swift \
        Tests/CzechatorCoreTests/SegmentBuilderTests.swift
git commit -m "feat: konfigurovatelná pravidla segmentace a sdílený SegmentBuilder"
```

---

## Task 4: ClipboardInput, protokol handleru a PlainTextHandler

**Files:**
- Create: `Sources/CzechatorCore/Detection/ClipboardInput.swift`
- Create: `Sources/CzechatorCore/Handlers/FormatHandler.swift`
- Create: `Sources/CzechatorCore/Handlers/PlainTextHandler.swift`
- Test: `Tests/CzechatorCoreTests/PlainTextHandlerTests.swift`

**Interfaces:**
- Consumes: `Segment`, `SegmentKind`, `Reassembler` (Task 2); `SegmentationRules`, `SegmentBuilder` (Task 3).
- Produces:
  - `struct ClipboardInput: Sendable, Equatable { let text: String; let uti: String?; let plainText: String? }` s `init(text:uti:plainText:)`, kde `uti` i `plainText` mají výchozí `nil`.
  - `protocol FormatHandler: Sendable` s `static var id: String`, `static func confidence(for: ClipboardInput) -> Double`, `func segments(in: String) throws -> [Segment]`, `func escape(_ corrected: String, like original: Segment) -> String`.
  - `struct PlainTextHandler: FormatHandler` s `init(rules: SegmentationRules) throws`.

- [ ] **Step 1: Napiš padající test**

`Tests/CzechatorCoreTests/PlainTextHandlerTests.swift`:

```swift
import Testing
@testable import CzechatorCore

private func handler() throws -> PlainTextHandler {
    try PlainTextHandler(rules: .builtIn)
}

@Test func treatsEachLineAsItsOwnCandidate() throws {
    let text = "prvni radek\ndruhy radek\n\ntreti radek"
    let segments = try handler().segments(in: text)
    #expect(segments.map(\.text) == ["prvni radek", "druhy radek", "treti radek"])
}

@Test func leavesNewlinesOutsideSegments() throws {
    let text = "a bcd\ne fgh"
    let segments = try handler().segments(in: text)
    for segment in segments {
        #expect(!text[segment.range].contains("\n"))
    }
}

@Test func skipsFencedCodeBlocks() throws {
    let text = "text pred\n```\nlet x = 1\n```\ntext po"
    let segments = try handler().segments(in: text)
    #expect(segments.map(\.text) == ["text pred", "text po"])
}

@Test func skipsInlineCode() throws {
    let segments = try handler().segments(in: "pouzij `let x = 1` prosim")
    #expect(segments.map(\.text) == ["pouzij", "prosim"])
}

@Test func spliceWithRawReproducesOriginalExactly() throws {
    let text = "prvni radek\n\n  odsazeny radek  \nhttps://example.com\nposledni"
    let segments = try handler().segments(in: text)
    let rebuilt = try Reassembler.splice(text, segments: segments,
                                         replacements: segments.map(\.raw))
    #expect(rebuilt == text)
}

@Test func escapeIsIdentityForPlainText() throws {
    let text = "ahoj"
    let segments = try handler().segments(in: text)
    #expect(try handler().escape("ahoj", like: segments[0]) == "ahoj")
}

@Test func confidenceIsTheLowFallbackValue() {
    #expect(PlainTextHandler.confidence(for: ClipboardInput(text: "cokoliv")) == 0.1)
    #expect(PlainTextHandler.id == "plain")
}
```

- [ ] **Step 2: Spusť test a ověř, že selže**

Run: `make test`
Expected: FAIL — `cannot find 'PlainTextHandler' in scope`, `cannot find 'ClipboardInput' in scope`.

- [ ] **Step 3: Napiš implementaci**

`Sources/CzechatorCore/Detection/ClipboardInput.swift`:

```swift
/// What the core receives from an `InputSource`.
///
/// `text` is the richest representation the source could offer (HTML when
/// available), `plainText` is the plain fallback that must be rewritten
/// alongside it so the pasteboard keeps both flavours in sync.
public struct ClipboardInput: Sendable, Equatable {
    public let text: String
    public let uti: String?
    public let plainText: String?

    public init(text: String, uti: String? = nil, plainText: String? = nil) {
        self.text = text
        self.uti = uti
        self.plainText = plainText
    }
}
```

`Sources/CzechatorCore/Handlers/FormatHandler.swift`:

```swift
/// A format handler never serializes the document. It only reports the ranges
/// of correctable text nodes and knows how to escape a corrected string back
/// into the format's syntax.
public protocol FormatHandler: Sendable {
    static var id: String { get }

    /// 0.0 means "not my format". The registry picks the highest bidder.
    static func confidence(for input: ClipboardInput) -> Double

    func segments(in text: String) throws -> [Segment]

    /// Must satisfy `escape(unescape(raw), like: segment) == raw` for the
    /// formats' realistic inputs. Residual mismatches are caught by the
    /// verifier, which then refuses to write anything.
    func escape(_ corrected: String, like original: Segment) -> String
}
```

`Sources/CzechatorCore/Handlers/PlainTextHandler.swift`:

```swift
/// Plain text and Markdown. Each line is its own candidate, which keeps
/// newlines outside segments and gives the batcher a natural granularity.
public struct PlainTextHandler: FormatHandler {

    public static let id = "plain"

    /// Constant low value: this is the fallback every other handler outbids.
    public static func confidence(for input: ClipboardInput) -> Double { 0.1 }

    private let builder: SegmentBuilder

    public init(rules: SegmentationRules) throws {
        builder = try SegmentBuilder(common: rules.common,
                                     extraSkipPatterns: rules.plain.skipPatterns)
    }

    public func segments(in text: String) throws -> [Segment] {
        let prepared = builder.prepared(for: text)
        var result: [Segment] = []
        var lineStart = text.startIndex
        var index = text.startIndex

        while index < text.endIndex {
            if text[index] == "\n" {
                result += prepared.build(candidate: lineStart..<index, kind: .plain) { String($0) }
                lineStart = text.index(after: index)
            }
            index = text.index(after: index)
        }
        result += prepared.build(candidate: lineStart..<text.endIndex, kind: .plain) { String($0) }
        return result
    }

    public func escape(_ corrected: String, like original: Segment) -> String { corrected }
}
```

- [ ] **Step 4: Spusť test a ověř, že projde**

Run: `make test`
Expected: PASS — 26 testů celkem.

- [ ] **Step 5: Commit**

```bash
git add Sources/CzechatorCore/Detection Sources/CzechatorCore/Handlers \
        Tests/CzechatorCoreTests/PlainTextHandlerTests.swift
git commit -m "feat: handler prostého textu a protokol formátů"
```

---
## Task 5: JSONScanner, escapování a JSONHandler

**Files:**
- Create: `Sources/CzechatorCore/Handlers/JSONScanner.swift`
- Create: `Sources/CzechatorCore/Handlers/JSONEscaping.swift`
- Create: `Sources/CzechatorCore/Handlers/JSONHandler.swift`
- Test: `Tests/CzechatorCoreTests/JSONHandlerTests.swift`

**Interfaces:**
- Consumes: `Segment`, `Reassembler` (Task 2); `SegmentationRules`, `SegmentBuilder` (Task 3); `ClipboardInput`, `FormatHandler` (Task 4).
- Produces:
  - `struct JSONStringLiteral: Sendable, Equatable { let contentRange: Range<String.Index>; let isKey: Bool; let parentKey: String? }`
  - `enum JSONScanError: Error, Equatable { case unexpectedCharacter(offset: Int), unterminatedString(offset: Int), trailingContent(offset: Int) }`
  - `JSONScanner.scan(_ text: String) throws -> [JSONStringLiteral]`
  - `struct JSONEscapeStyle: Sendable, Equatable { var unicodeEscapes: Bool; var escapedSolidus: Bool }`, `JSONEscapeStyle.detect(in raw: String) -> JSONEscapeStyle`
  - `JSONEscaping.unescape(_ s: Substring) -> String`, `JSONEscaping.escape(_ s: String, style: JSONEscapeStyle) -> String`
  - `struct JSONHandler: FormatHandler` s `init(rules: SegmentationRules) throws`

- [ ] **Step 1: Napiš padající test**

`Tests/CzechatorCoreTests/JSONHandlerTests.swift`:

```swift
import Testing
@testable import CzechatorCore

private func handler() throws -> JSONHandler { try JSONHandler(rules: .builtIn) }

@Test func scannerReportsKeysAndValuesSeparately() throws {
    let text = #"{"nazev": "ahoj svete"}"#
    let literals = try JSONScanner.scan(text)
    #expect(literals.count == 2)
    #expect(literals[0].isKey)
    #expect(!literals[1].isKey)
    #expect(literals[1].parentKey == "nazev")
    #expect(text[literals[1].contentRange] == "ahoj svete")
}

@Test func scannerHandlesNestingAndArrays() throws {
    let text = #"{"a": {"b": ["prvni text", "druhy text"]}, "c": 12}"#
    let literals = try JSONScanner.scan(text)
    let values = literals.filter { !$0.isKey }.map { String(text[$0.contentRange]) }
    #expect(values == ["prvni text", "druhy text"])
}

@Test func scannerRejectsInvalidJSON() {
    #expect(throws: (any Error).self) { try JSONScanner.scan(#"{"a": }"#) }
    #expect(throws: (any Error).self) { try JSONScanner.scan(#"{"a": "b"} navic"#) }
}

@Test func skipsKeysAndConfiguredValueKeys() throws {
    let text = #"{"id": "nejaky text", "popis": "dalsi text"}"#
    let segments = try handler().segments(in: text)
    #expect(segments.map(\.text) == ["dalsi text"])
}

@Test func unescapesContentForTheModel() throws {
    let text = #"{"a": "prvni\nradek á konec"}"#
    let segments = try handler().segments(in: text)
    #expect(segments.count == 1)
    #expect(segments[0].text == "prvni\nradek á konec")
}

@Test func escapeRoundTripsRawContent() throws {
    let raws = [
        #"ahoj svete"#,
        #"prvni\nradek"#,
        #"uvozovka \" uvnitr"#,
        #"lomitko \/ uvnitr"#,
        #"unicode á znak"#,
        #"zpetne \\ lomitko"#,
    ]
    for raw in raws {
        let style = JSONEscapeStyle.detect(in: raw)
        let round = JSONEscaping.escape(JSONEscaping.unescape(raw[...]), style: style)
        #expect(round == raw, "round trip failed for \(raw)")
    }
}

@Test func spliceWithRawReproducesOriginalExactly() throws {
    let text = #"""
    {
      "id": "abc",
      "nazev": "prvni text",
      "vnorene": { "popis": "druhy á text", "url": "https://example.com" },
      "seznam": ["treti text", 42, true, null]
    }
    """#
    let segments = try handler().segments(in: text)
    let rebuilt = try Reassembler.splice(text, segments: segments,
                                         replacements: segments.map(\.raw))
    #expect(rebuilt == text)
}

@Test func correctingOneValueLeavesStructureUntouched() throws {
    let text = #"{"b": 1, "a": "prilis zlutoucky kun"}"#
    let h = try handler()
    let segments = try h.segments(in: text)
    let replacements = segments.map { h.escape("příliš žluťoučký kůň", like: $0) }
    let rebuilt = try Reassembler.splice(text, segments: segments, replacements: replacements)
    #expect(rebuilt == #"{"b": 1, "a": "příliš žluťoučký kůň"}"#)
}

@Test func confidenceRequiresParsableJSON() {
    #expect(JSONHandler.confidence(for: ClipboardInput(text: #"{"a": "b"}"#)) == 0.9)
    #expect(JSONHandler.confidence(for: ClipboardInput(text: "jen text")) == 0)
    #expect(JSONHandler.confidence(for: ClipboardInput(text: #"{"a": }"#)) == 0)
    #expect(JSONHandler.id == "json")
}
```

- [ ] **Step 2: Spusť test a ověř, že selže**

Run: `make test`
Expected: FAIL — `cannot find 'JSONScanner' in scope`.

- [ ] **Step 3: Napiš implementaci**

`Sources/CzechatorCore/Handlers/JSONScanner.swift`:

```swift
public struct JSONStringLiteral: Sendable, Equatable {
    /// Range of the content between the quotes, still escaped.
    public let contentRange: Range<String.Index>
    public let isKey: Bool
    /// Object key this value belongs to, if any. Array elements inherit the
    /// key of the array itself.
    public let parentKey: String?

    public init(contentRange: Range<String.Index>, isKey: Bool, parentKey: String?) {
        self.contentRange = contentRange
        self.isKey = isKey
        self.parentKey = parentKey
    }
}

public enum JSONScanError: Error, Equatable {
    case unexpectedCharacter(offset: Int)
    case unterminatedString(offset: Int)
    case trailingContent(offset: Int)
}

/// Hand-written scanner. JSONSerialization is unusable here because it loses
/// key order, indentation and formatting — the document could never be
/// reassembled byte-for-byte.
public enum JSONScanner {

    public static func scan(_ text: String) throws -> [JSONStringLiteral] {
        var parser = Parser(text: text)
        parser.skipWhitespace()
        try parser.parseValue(parentKey: nil)
        parser.skipWhitespace()
        guard parser.isAtEnd else { throw JSONScanError.trailingContent(offset: parser.offset) }
        return parser.literals
    }

    private struct Parser {
        let text: String
        var index: String.Index
        var literals: [JSONStringLiteral] = []

        init(text: String) {
            self.text = text
            self.index = text.startIndex
        }

        var isAtEnd: Bool { index >= text.endIndex }
        var current: Character? { isAtEnd ? nil : text[index] }
        var offset: Int { text.distance(from: text.startIndex, to: index) }

        mutating func advance() { index = text.index(after: index) }

        mutating func skipWhitespace() {
            while let c = current, c == " " || c == "\n" || c == "\r" || c == "\t" { advance() }
        }

        mutating func expect(_ character: Character) throws {
            guard current == character else { throw JSONScanError.unexpectedCharacter(offset: offset) }
            advance()
        }

        mutating func parseValue(parentKey: String?) throws {
            skipWhitespace()
            switch current {
            case "{": try parseObject()
            case "[": try parseArray(parentKey: parentKey)
            case "\"": _ = try parseString(isKey: false, parentKey: parentKey)
            case nil: throw JSONScanError.unexpectedCharacter(offset: offset)
            default: try parseBareLiteral()
            }
        }

        mutating func parseObject() throws {
            try expect("{")
            skipWhitespace()
            if current == "}" { advance(); return }
            while true {
                skipWhitespace()
                guard current == "\"" else { throw JSONScanError.unexpectedCharacter(offset: offset) }
                let key = try parseString(isKey: true, parentKey: nil)
                skipWhitespace()
                try expect(":")
                try parseValue(parentKey: key)
                skipWhitespace()
                if current == "," { advance(); continue }
                try expect("}")
                return
            }
        }

        mutating func parseArray(parentKey: String?) throws {
            try expect("[")
            skipWhitespace()
            if current == "]" { advance(); return }
            while true {
                try parseValue(parentKey: parentKey)
                skipWhitespace()
                if current == "," { advance(); continue }
                try expect("]")
                return
            }
        }

        @discardableResult
        mutating func parseString(isKey: Bool, parentKey: String?) throws -> String {
            try expect("\"")
            let start = index
            while true {
                guard let character = current else {
                    throw JSONScanError.unterminatedString(offset: offset)
                }
                if character == "\\" {
                    advance()
                    guard !isAtEnd else { throw JSONScanError.unterminatedString(offset: offset) }
                    advance()
                    continue
                }
                if character == "\"" { break }
                advance()
            }
            let content = start..<index
            advance()
            literals.append(JSONStringLiteral(contentRange: content, isKey: isKey, parentKey: parentKey))
            return String(text[content])
        }

        /// Numbers, true, false, null — not segmented, only skipped over.
        mutating func parseBareLiteral() throws {
            let start = index
            while let character = current, !",]} \n\r\t".contains(character) { advance() }
            guard index > start else { throw JSONScanError.unexpectedCharacter(offset: offset) }
        }
    }
}
```

`Sources/CzechatorCore/Handlers/JSONEscaping.swift`:

```swift
/// Which optional escapes the source document used. Preserved so that an
/// unchanged segment escapes back to exactly the bytes it came from.
public struct JSONEscapeStyle: Sendable, Equatable {
    public var unicodeEscapes: Bool
    public var escapedSolidus: Bool

    public init(unicodeEscapes: Bool, escapedSolidus: Bool) {
        self.unicodeEscapes = unicodeEscapes
        self.escapedSolidus = escapedSolidus
    }

    public static func detect(in raw: String) -> JSONEscapeStyle {
        JSONEscapeStyle(unicodeEscapes: raw.contains("\\u"),
                        escapedSolidus: raw.contains("\\/"))
    }
}

public enum JSONEscaping {

    public static func unescape(_ s: Substring) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var index = s.startIndex
        var pendingHighSurrogate: UInt32?

        func flushSurrogate() {
            if let high = pendingHighSurrogate {
                out.append(Character(UnicodeScalar(high) ?? UnicodeScalar(0xFFFD)!))
                pendingHighSurrogate = nil
            }
        }

        while index < s.endIndex {
            let character = s[index]
            guard character == "\\" else {
                flushSurrogate()
                out.append(character)
                index = s.index(after: index)
                continue
            }
            let next = s.index(after: index)
            guard next < s.endIndex else {
                flushSurrogate()
                out.append(character)
                break
            }
            let escape = s[next]
            if escape == "u" {
                let hexStart = s.index(after: next)
                guard let hexEnd = s.index(hexStart, offsetBy: 4, limitedBy: s.endIndex),
                      let value = UInt32(s[hexStart..<hexEnd], radix: 16) else {
                    flushSurrogate()
                    out.append(character)
                    index = next
                    continue
                }
                if (0xD800...0xDBFF).contains(value) {
                    flushSurrogate()
                    pendingHighSurrogate = value
                } else if (0xDC00...0xDFFF).contains(value), let high = pendingHighSurrogate {
                    let combined = 0x10000 + ((high - 0xD800) << 10) + (value - 0xDC00)
                    pendingHighSurrogate = nil
                    out.append(Character(UnicodeScalar(combined) ?? UnicodeScalar(0xFFFD)!))
                } else {
                    flushSurrogate()
                    out.append(Character(UnicodeScalar(value) ?? UnicodeScalar(0xFFFD)!))
                }
                index = hexEnd
                continue
            }
            flushSurrogate()
            switch escape {
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "r": out.append("\r")
            case "b": out.append("\u{08}")
            case "f": out.append("\u{0C}")
            case "\"": out.append("\"")
            case "\\": out.append("\\")
            case "/": out.append("/")
            default: out.append(escape)
            }
            index = s.index(after: next)
        }
        flushSurrogate()
        return out
    }

    public static func escape(_ s: String, style: JSONEscapeStyle) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "/": out += style.escapedSolidus ? "\\/" : "/"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else if style.unicodeEscapes, scalar.value > 0x7F {
                    for unit in String(scalar).utf16 {
                        out += String(format: "\\u%04x", unit)
                    }
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }
}
```

> `String(format:)` vyžaduje `import Foundation` — přidej ho na začátek souboru.

`Sources/CzechatorCore/Handlers/JSONHandler.swift`:

```swift
public struct JSONHandler: FormatHandler {

    public static let id = "json"

    public static func confidence(for input: ClipboardInput) -> Double {
        let trimmed = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { return 0 }
        return (try? JSONScanner.scan(input.text)) != nil ? 0.9 : 0
    }

    private let rules: JSONRules
    private let builder: SegmentBuilder

    public init(rules: SegmentationRules) throws {
        self.rules = rules.json
        self.builder = try SegmentBuilder(common: rules.common)
    }

    public func segments(in text: String) throws -> [Segment] {
        let literals = try JSONScanner.scan(text)
        let prepared = builder.prepared(for: text)
        var result: [Segment] = []

        for literal in literals {
            if literal.isKey, rules.skipKeys { continue }
            if let key = literal.parentKey, rules.skipValuesForKeys.contains(key) { continue }
            result += prepared.build(candidate: literal.contentRange, kind: .jsonString) {
                JSONEscaping.unescape($0)
            }
        }
        return result
    }

    public func escape(_ corrected: String, like original: Segment) -> String {
        JSONEscaping.escape(corrected, style: .detect(in: original.raw))
    }
}
```

> `trimmingCharacters(in:)` vyžaduje `import Foundation` — přidej ho na začátek souboru.

- [ ] **Step 4: Spusť test a ověř, že projde**

Run: `make test`
Expected: PASS — 35 testů celkem.

- [ ] **Step 5: Commit**

```bash
git add Sources/CzechatorCore/Handlers/JSONScanner.swift \
        Sources/CzechatorCore/Handlers/JSONEscaping.swift \
        Sources/CzechatorCore/Handlers/JSONHandler.swift \
        Tests/CzechatorCoreTests/JSONHandlerTests.swift
git commit -m "feat: skener a handler JSONu se zachováním stylu escapování"
```

---

## Task 6: MarkupScanner

**Files:**
- Create: `Sources/CzechatorCore/Handlers/MarkupScanner.swift`
- Test: `Tests/CzechatorCoreTests/MarkupScannerTests.swift`

**Interfaces:**
- Consumes: nic z předchozích tasků.
- Produces:
  - `struct MarkupTextNode: Sendable, Equatable { let range: Range<String.Index>; let elementPath: [String]; let isAttributeValue: Bool }`
  - `struct MarkupScanOptions: Sendable { var skipElements: Set<String>; var skipComments: Bool; var skipProcessingInstructions: Bool; var skipCDATA: Bool; var includeAttributeValues: Bool; var voidElements: Set<String> }`
  - `MarkupScanOptions.htmlVoidElements: Set<String>`
  - `MarkupScanner.scan(_ text: String, options: MarkupScanOptions) -> [MarkupTextNode]`
  - `MarkupScanner.looksLikeMarkup(_ text: String) -> Bool`

- [ ] **Step 1: Napiš padající test**

`Tests/CzechatorCoreTests/MarkupScannerTests.swift`:

```swift
import Testing
@testable import CzechatorCore

private let base = MarkupScanOptions(
    skipElements: [],
    skipComments: true,
    skipProcessingInstructions: true,
    skipCDATA: false,
    includeAttributeValues: false,
    voidElements: []
)

private func texts(_ input: String, _ options: MarkupScanOptions = base) -> [String] {
    MarkupScanner.scan(input, options: options).map { String(input[$0.range]) }
}

@Test func extractsTextNodesOnly() {
    #expect(texts("<p>ahoj svete</p>") == ["ahoj svete"])
}

@Test func neverReturnsTagsOrAttributes() {
    let input = #"<div class="velky" id="x">obsah</div>"#
    #expect(texts(input) == ["obsah"])
}

@Test func tracksElementPath() {
    let input = "<a><b>hluboko</b></a>"
    let nodes = MarkupScanner.scan(input, options: base)
    #expect(nodes.count == 1)
    #expect(nodes[0].elementPath == ["a", "b"])
}

@Test func skipsConfiguredElements() {
    var options = base
    options.skipElements = ["script", "style"]
    let input = "<p>viditelne</p><script>var x = 'skryte';</script>"
    #expect(texts(input, options) == ["viditelne"])
}

@Test func skipsCommentsAndProcessingInstructions() {
    let input = "<?xml version=\"1.0\"?><!-- poznamka --><r>obsah</r>"
    #expect(texts(input) == ["obsah"])
}

@Test func includesCDATAWhenNotSkipped() {
    let input = "<r><![CDATA[uvnitr cdata]]></r>"
    #expect(texts(input) == ["uvnitr cdata"])
}

@Test func skipsCDATAWhenConfigured() {
    var options = base
    options.skipCDATA = true
    #expect(texts("<r><![CDATA[uvnitr cdata]]></r>", options).isEmpty)
}

@Test func handlesSelfClosingAndVoidElements() {
    var options = base
    options.voidElements = MarkupScanOptions.htmlVoidElements
    let input = "<p>pred<br>po</p><img src=\"a.png\"/><p>dalsi</p>"
    let nodes = MarkupScanner.scan(input, options: options)
    #expect(nodes.map { String(input[$0.range]) } == ["pred", "po", "dalsi"])
    #expect(nodes.allSatisfy { $0.elementPath == ["p"] })
}

@Test func returnsAttributeValuesWhenRequested() {
    var options = base
    options.includeAttributeValues = true
    let input = #"<img alt="popis obrazku">"#
    let nodes = MarkupScanner.scan(input, options: options)
    #expect(nodes.map { String(input[$0.range]) } == ["popis obrazku"])
    #expect(nodes[0].isAttributeValue)
}

@Test func detectsMarkupHeuristically() {
    #expect(MarkupScanner.looksLikeMarkup("<p>ahoj</p>"))
    #expect(MarkupScanner.looksLikeMarkup("<?xml version=\"1.0\"?><r/>"))
    #expect(!MarkupScanner.looksLikeMarkup("2 < 3 a 5 > 4"))
    #expect(!MarkupScanner.looksLikeMarkup("obycejny text"))
}
```

- [ ] **Step 2: Spusť test a ověř, že selže**

Run: `make test`
Expected: FAIL — `cannot find 'MarkupScanner' in scope`.

- [ ] **Step 3: Napiš implementaci**

`Sources/CzechatorCore/Handlers/MarkupScanner.swift`:

```swift
public struct MarkupTextNode: Sendable, Equatable {
    public let range: Range<String.Index>
    /// Lowercased element names, outermost first.
    public let elementPath: [String]
    public let isAttributeValue: Bool

    public init(range: Range<String.Index>, elementPath: [String], isAttributeValue: Bool) {
        self.range = range
        self.elementPath = elementPath
        self.isAttributeValue = isAttributeValue
    }
}

public struct MarkupScanOptions: Sendable {
    public var skipElements: Set<String>
    public var skipComments: Bool
    public var skipProcessingInstructions: Bool
    public var skipCDATA: Bool
    public var includeAttributeValues: Bool
    /// Elements that never have a closing tag (HTML only).
    public var voidElements: Set<String>

    public init(skipElements: Set<String>, skipComments: Bool,
                skipProcessingInstructions: Bool, skipCDATA: Bool,
                includeAttributeValues: Bool, voidElements: Set<String>) {
        self.skipElements = skipElements
        self.skipComments = skipComments
        self.skipProcessingInstructions = skipProcessingInstructions
        self.skipCDATA = skipCDATA
        self.includeAttributeValues = includeAttributeValues
        self.voidElements = voidElements
    }

    public static let htmlVoidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr",
    ]
}

/// Shared scanner for XML and HTML. Deliberately forgiving: malformed markup
/// yields fewer text nodes rather than an error, because the verifier is the
/// real safety net.
public enum MarkupScanner {

    public static func looksLikeMarkup(_ text: String) -> Bool {
        guard let open = text.firstIndex(of: "<") else { return false }
        let after = text.index(after: open)
        guard after < text.endIndex else { return false }
        let next = text[after]
        guard next.isLetter || next == "/" || next == "?" || next == "!" else { return false }
        return text[after...].contains(">")
    }

    public static func scan(_ text: String, options: MarkupScanOptions) -> [MarkupTextNode] {
        var nodes: [MarkupTextNode] = []
        var stack: [String] = []
        var index = text.startIndex
        var textStart = text.startIndex

        func flushText(upTo end: String.Index) {
            guard textStart < end else { return }
            if stack.contains(where: { options.skipElements.contains($0) }) { return }
            nodes.append(MarkupTextNode(range: textStart..<end,
                                        elementPath: stack,
                                        isAttributeValue: false))
        }

        while index < text.endIndex {
            guard text[index] == "<" else {
                index = text.index(after: index)
                continue
            }

            if text[index...].hasPrefix("<!--") {
                flushText(upTo: index)
                index = advance(text, from: index, past: "-->")
                textStart = index
                continue
            }

            if text[index...].hasPrefix("<![CDATA[") {
                flushText(upTo: index)
                let contentStart = text.index(index, offsetBy: 9)
                let end = advance(text, from: contentStart, past: "]]>")
                if !options.skipCDATA,
                   !stack.contains(where: { options.skipElements.contains($0) }) {
                    let contentEnd = text.index(end, offsetBy: -3, limitedBy: contentStart) ?? contentStart
                    if contentStart < contentEnd {
                        nodes.append(MarkupTextNode(range: contentStart..<contentEnd,
                                                    elementPath: stack,
                                                    isAttributeValue: false))
                    }
                }
                index = end
                textStart = index
                continue
            }

            if text[index...].hasPrefix("<?") {
                flushText(upTo: index)
                index = advance(text, from: index, past: "?>")
                textStart = index
                continue
            }

            if text[index...].hasPrefix("<!") {
                flushText(upTo: index)
                index = advance(text, from: index, past: ">")
                textStart = index
                continue
            }

            guard let tagEnd = text[index...].firstIndex(of: ">") else { break }
            flushText(upTo: index)

            let inner = text[text.index(after: index)..<tagEnd]
            if inner.hasPrefix("/") {
                let name = elementName(of: inner.dropFirst())
                if let position = stack.lastIndex(of: name) {
                    stack.removeSubrange(position...)
                }
            } else {
                let name = elementName(of: inner)
                if options.includeAttributeValues,
                   !stack.contains(where: { options.skipElements.contains($0) }),
                   !options.skipElements.contains(name) {
                    nodes += attributeValues(in: text,
                                             tagInner: inner,
                                             path: stack + [name])
                }
                let selfClosing = inner.hasSuffix("/") || options.voidElements.contains(name)
                if !selfClosing { stack.append(name) }
            }

            index = text.index(after: tagEnd)
            textStart = index
        }
        flushText(upTo: text.endIndex)
        return nodes
    }

    private static func elementName(of inner: Substring) -> String {
        String(inner.prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ":" })
            .lowercased()
    }

    private static func advance(_ text: String,
                                from index: String.Index,
                                past terminator: String) -> String.Index {
        guard let found = text.range(of: terminator, range: index..<text.endIndex) else {
            return text.endIndex
        }
        return found.upperBound
    }

    /// Scans `name="value"` pairs inside an already-delimited tag body.
    private static func attributeValues(in text: String,
                                        tagInner: Substring,
                                        path: [String]) -> [MarkupTextNode] {
        var nodes: [MarkupTextNode] = []
        var index = tagInner.startIndex
        while index < tagInner.endIndex {
            guard tagInner[index] == "\"" || tagInner[index] == "'" else {
                index = tagInner.index(after: index)
                continue
            }
            let quote = tagInner[index]
            let start = tagInner.index(after: index)
            guard let end = tagInner[start...].firstIndex(of: quote) else { break }
            if start < end {
                nodes.append(MarkupTextNode(range: start..<end,
                                            elementPath: path,
                                            isAttributeValue: true))
            }
            index = tagInner.index(after: end)
        }
        return nodes
    }
}
```

> `text.range(of:range:)` vyžaduje `import Foundation` — přidej ho na začátek souboru.

- [ ] **Step 4: Spusť test a ověř, že projde**

Run: `make test`
Expected: PASS — 45 testů celkem.

- [ ] **Step 5: Commit**

```bash
git add Sources/CzechatorCore/Handlers/MarkupScanner.swift \
        Tests/CzechatorCoreTests/MarkupScannerTests.swift
git commit -m "feat: sdílený skener značkovacích jazyků"
```

---
## Task 7: Entity a XMLHandler

**Files:**
- Create: `Sources/CzechatorCore/Handlers/MarkupEntities.swift`
- Create: `Sources/CzechatorCore/Handlers/XMLHandler.swift`
- Test: `Tests/CzechatorCoreTests/XMLHandlerTests.swift`

**Interfaces:**
- Consumes: `Segment`, `Reassembler` (Task 2); `SegmentationRules`, `SegmentBuilder` (Task 3); `ClipboardInput`, `FormatHandler` (Task 4); `MarkupScanner`, `MarkupScanOptions` (Task 6).
- Produces:
  - `struct MarkupEntityStyle: Sendable, Equatable { var preferred: [Character: String] }` + `MarkupEntityStyle.detect(in raw: String, table: [String: Character]) -> MarkupEntityStyle`
  - `MarkupEntities.xmlTable: [String: Character]`, `MarkupEntities.htmlTable: [String: Character]`
  - `MarkupEntities.unescape(_ s: Substring, table: [String: Character]) -> String`
  - `MarkupEntities.escape(_ s: String, style: MarkupEntityStyle) -> String`
  - `struct XMLHandler: FormatHandler` s `init(rules: SegmentationRules) throws`

**Zásadní pravidlo escapování:** `escape` nepřidává escapování z vlastní iniciativy. Emituje entitu **jen** pro znaky, u kterých zdrojový text entitu použil (`style.preferred`). Model přidává výhradně diakritiku, takže žádný nový `&` ani `<` nevznikne, a round trip je tím pádem přesný. Dokument, který míchá `&amp;` s holým `&`, verifikaci neprojde — a to je záměr, ne chyba.

- [ ] **Step 1: Napiš padající test**

`Tests/CzechatorCoreTests/XMLHandlerTests.swift`:

```swift
import Testing
@testable import CzechatorCore

private func handler() throws -> XMLHandler { try XMLHandler(rules: .builtIn) }

@Test func unescapesNamedAndNumericEntities() {
    let input = "a &lt; b &amp; c &#160;konec"[...]
    #expect(MarkupEntities.unescape(input, table: MarkupEntities.xmlTable)
            == "a < b & c \u{00A0}konec")
}

@Test func escapeReproducesTheSourceSpelling() {
    let raw = "a &lt; b &amp; c &#160;konec"
    let style = MarkupEntityStyle.detect(in: raw, table: MarkupEntities.xmlTable)
    let round = MarkupEntities.escape(MarkupEntities.unescape(raw[...], table: MarkupEntities.xmlTable),
                                      style: style)
    #expect(round == raw)
}

@Test func escapeLeavesUnEscapedCharactersAlone() {
    let style = MarkupEntityStyle.detect(in: "bez entit", table: MarkupEntities.xmlTable)
    #expect(MarkupEntities.escape("a > b", style: style) == "a > b")
}

@Test func segmentsOnlyTextNodes() throws {
    let text = "<?xml version=\"1.0\"?><r><a id=\"x\">prvni text</a><!-- pozn --><b>druhy text</b></r>"
    #expect(try handler().segments(in: text).map(\.text) == ["prvni text", "druhy text"])
}

@Test func spliceWithRawReproducesOriginalExactly() throws {
    let text = """
    <?xml version="1.0" encoding="UTF-8"?>
    <root>
      <polozka id="1">prvni text s &amp; entitou</polozka>
      <!-- komentar -->
      <polozka id="2"><![CDATA[cdata text]]></polozka>
      <prazdna/>
    </root>
    """
    let segments = try handler().segments(in: text)
    let rebuilt = try Reassembler.splice(text, segments: segments,
                                         replacements: segments.map(\.raw))
    #expect(rebuilt == text)
}

@Test func correctingTextLeavesMarkupUntouched() throws {
    let text = "<r><a>prilis zlutoucky kun</a></r>"
    let h = try handler()
    let segments = try h.segments(in: text)
    let rebuilt = try Reassembler.splice(
        text, segments: segments,
        replacements: segments.map { h.escape("příliš žluťoučký kůň", like: $0) })
    #expect(rebuilt == "<r><a>příliš žluťoučký kůň</a></r>")
}

@Test func confidenceFavoursDeclaredXML() {
    #expect(XMLHandler.confidence(for: ClipboardInput(text: "<?xml version=\"1.0\"?><r/>")) == 0.95)
    #expect(XMLHandler.confidence(for: ClipboardInput(text: "<r><a>x</a></r>")) == 0.6)
    #expect(XMLHandler.confidence(for: ClipboardInput(text: "2 < 3")) == 0)
    #expect(XMLHandler.id == "xml")
}
```

- [ ] **Step 2: Spusť test a ověř, že selže**

Run: `make test`
Expected: FAIL — `cannot find 'MarkupEntities' in scope`.

- [ ] **Step 3: Napiš implementaci**

`Sources/CzechatorCore/Handlers/MarkupEntities.swift`:

```swift
import Foundation

/// Which entity spelling the source document used for a given character.
/// Escaping is driven purely by this map, so an untouched segment escapes back
/// to exactly the bytes it came from.
public struct MarkupEntityStyle: Sendable, Equatable {
    public var preferred: [Character: String]

    public init(preferred: [Character: String]) { self.preferred = preferred }

    /// Records, for every entity the source actually used, the exact spelling.
    /// First spelling wins, so a document mixing `&#160;` and `&nbsp;` round
    /// trips the first form and fails verification for the rest — deliberate.
    public static func detect(in raw: String, table: [String: Character]) -> MarkupEntityStyle {
        var preferred: [Character: String] = [:]
        var index = raw.startIndex
        while index < raw.endIndex {
            guard raw[index] == "&",
                  let semicolon = raw[index...].firstIndex(of: ";"),
                  raw.distance(from: index, to: semicolon) <= 10,
                  let character = MarkupEntities.resolveEntity(
                      raw[raw.index(after: index)..<semicolon], table: table)
            else {
                index = raw.index(after: index)
                continue
            }
            if preferred[character] == nil {
                preferred[character] = String(raw[index...semicolon])
            }
            index = raw.index(after: semicolon)
        }
        return MarkupEntityStyle(preferred: preferred)
    }
}

public enum MarkupEntities {

    public static let xmlTable: [String: Character] = [
        "lt": "<", "gt": ">", "amp": "&", "quot": "\"", "apos": "'",
    ]

    public static let htmlTable: [String: Character] = xmlTable.merging([
        "nbsp": "\u{00A0}", "copy": "©", "reg": "®", "trade": "™",
        "hellip": "…", "mdash": "—", "ndash": "–",
        "laquo": "«", "raquo": "»", "bdquo": "„", "ldquo": "“", "rdquo": "”",
        "eacute": "é", "aacute": "á", "iacute": "í", "oacute": "ó", "uacute": "ú",
        "yacute": "ý", "scaron": "š", "zcaron": "ž", "ccaron": "č", "rcaron": "ř",
    ]) { current, _ in current }

    /// Resolves one entity body (the part between `&` and `;`).
    static func resolveEntity(_ body: Substring, table: [String: Character]) -> Character? {
        if body.hasPrefix("#x") || body.hasPrefix("#X") {
            guard let value = UInt32(body.dropFirst(2), radix: 16),
                  let scalar = UnicodeScalar(value) else { return nil }
            return Character(scalar)
        }
        if body.hasPrefix("#") {
            guard let value = UInt32(body.dropFirst()), let scalar = UnicodeScalar(value) else {
                return nil
            }
            return Character(scalar)
        }
        return table[String(body)]
    }

    public static func unescape(_ s: Substring, table: [String: Character]) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var index = s.startIndex
        while index < s.endIndex {
            guard s[index] == "&",
                  let semicolon = s[index...].firstIndex(of: ";"),
                  s.distance(from: index, to: semicolon) <= 10,
                  let character = resolveEntity(s[s.index(after: index)..<semicolon], table: table)
            else {
                out.append(s[index])
                index = s.index(after: index)
                continue
            }
            out.append(character)
            index = s.index(after: semicolon)
        }
        return out
    }

    /// Escapes only what the source escaped. See `MarkupEntityStyle`.
    public static func escape(_ s: String, style: MarkupEntityStyle) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for character in s {
            if let spelling = style.preferred[character] {
                out += spelling
            } else {
                out.append(character)
            }
        }
        return out
    }
}
```

`Sources/CzechatorCore/Handlers/XMLHandler.swift`:

```swift
import Foundation

public struct XMLHandler: FormatHandler {

    public static let id = "xml"

    public static func confidence(for input: ClipboardInput) -> Double {
        if input.uti == "public.xml" { return 0.95 }
        let trimmed = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<?xml") { return 0.95 }
        return MarkupScanner.looksLikeMarkup(trimmed) ? 0.6 : 0
    }

    private let options: MarkupScanOptions
    private let builder: SegmentBuilder

    public init(rules: SegmentationRules) throws {
        options = MarkupScanOptions(
            skipElements: Set(rules.xml.skipElements.map { $0.lowercased() }),
            skipComments: rules.xml.skipComments,
            skipProcessingInstructions: rules.xml.skipProcessingInstructions,
            skipCDATA: rules.xml.skipCDATA,
            includeAttributeValues: !rules.xml.skipAttributes,
            voidElements: []
        )
        builder = try SegmentBuilder(common: rules.common)
    }

    public func segments(in text: String) throws -> [Segment] {
        let prepared = builder.prepared(for: text)
        return MarkupScanner.scan(text, options: options).flatMap { node in
            prepared.build(candidate: node.range, kind: .xmlText) {
                MarkupEntities.unescape($0, table: MarkupEntities.xmlTable)
            }
        }
    }

    public func escape(_ corrected: String, like original: Segment) -> String {
        MarkupEntities.escape(corrected,
                              style: .detect(in: original.raw, table: MarkupEntities.xmlTable))
    }
}
```

- [ ] **Step 4: Spusť test a ověř, že projde**

Run: `make test`
Expected: PASS — 52 testů celkem.

- [ ] **Step 5: Commit**

```bash
git add Sources/CzechatorCore/Handlers/MarkupEntities.swift \
        Sources/CzechatorCore/Handlers/XMLHandler.swift \
        Tests/CzechatorCoreTests/XMLHandlerTests.swift
git commit -m "feat: entity a handler XML"
```

---

## Task 8: HTMLHandler

**Files:**
- Create: `Sources/CzechatorCore/Handlers/HTMLHandler.swift`
- Test: `Tests/CzechatorCoreTests/HTMLHandlerTests.swift`

**Interfaces:**
- Consumes: vše z Tasku 7 plus `MarkupScanOptions.htmlVoidElements` (Task 6).
- Produces: `struct HTMLHandler: FormatHandler` s `init(rules: SegmentationRules) throws`.

- [ ] **Step 1: Napiš padající test**

`Tests/CzechatorCoreTests/HTMLHandlerTests.swift`:

```swift
import Testing
@testable import CzechatorCore

private func handler() throws -> HTMLHandler { try HTMLHandler(rules: .builtIn) }

@Test func skipsScriptStyleAndCode() throws {
    let text = "<p>viditelne</p><script>var a='x';</script><style>p{color:red}</style><code>let x</code>"
    #expect(try handler().segments(in: text).map(\.text) == ["viditelne"])
}

@Test func handlesVoidElementsWithoutBreakingTheStack() throws {
    let text = "<p>pred<br>po</p><p>dalsi</p>"
    #expect(try handler().segments(in: text).map(\.text) == ["pred", "po", "dalsi"])
}

@Test func unescapesHTMLEntitiesForTheModel() throws {
    let text = "<p>ahoj&nbsp;svete&hellip;</p>"
    #expect(try handler().segments(in: text).map(\.text) == ["ahoj\u{00A0}svete…"])
}

@Test func spliceWithRawReproducesOriginalExactly() throws {
    let text = """
    <div class="a"><p>prvni &amp; text</p><br><ul><li>polozka</li></ul>
    <script>var x = 1;</script><p>posledni&nbsp;text</p></div>
    """
    let segments = try handler().segments(in: text)
    let rebuilt = try Reassembler.splice(text, segments: segments,
                                         replacements: segments.map(\.raw))
    #expect(rebuilt == text)
}

@Test func correctingTextLeavesTagsAndAttributesUntouched() throws {
    let text = #"<p class="velky">prilis zlutoucky kun</p>"#
    let h = try handler()
    let segments = try h.segments(in: text)
    let rebuilt = try Reassembler.splice(
        text, segments: segments,
        replacements: segments.map { h.escape("příliš žluťoučký kůň", like: $0) })
    #expect(rebuilt == #"<p class="velky">příliš žluťoučký kůň</p>"#)
}

@Test func confidenceFavoursDeclaredHTML() {
    #expect(HTMLHandler.confidence(for: ClipboardInput(text: "<p>x</p>", uti: "public.html")) == 1.0)
    #expect(HTMLHandler.confidence(for: ClipboardInput(text: "<div>x</div>")) == 0.75)
    #expect(HTMLHandler.confidence(for: ClipboardInput(text: "<r><a>x</a></r>")) == 0)
    #expect(HTMLHandler.id == "html")
}
```

- [ ] **Step 2: Spusť test a ověř, že selže**

Run: `make test`
Expected: FAIL — `cannot find 'HTMLHandler' in scope`.

- [ ] **Step 3: Napiš implementaci**

`Sources/CzechatorCore/Handlers/HTMLHandler.swift`:

```swift
import Foundation

public struct HTMLHandler: FormatHandler {

    public static let id = "html"

    /// Element names that mark a document as HTML rather than generic XML.
    private static let markers = ["<html", "<div", "<span", "<body", "<p>", "<p ", "<br", "<ul", "<table"]

    public static func confidence(for input: ClipboardInput) -> Double {
        if input.uti == "public.html" { return 1.0 }
        let lowered = input.text.lowercased()
        return markers.contains(where: lowered.contains) ? 0.75 : 0
    }

    private let options: MarkupScanOptions
    private let builder: SegmentBuilder

    public init(rules: SegmentationRules) throws {
        options = MarkupScanOptions(
            skipElements: Set(rules.html.skipElements.map { $0.lowercased() }),
            skipComments: rules.html.skipComments,
            skipProcessingInstructions: true,
            skipCDATA: true,
            includeAttributeValues: !rules.html.skipAttributes,
            voidElements: MarkupScanOptions.htmlVoidElements
        )
        builder = try SegmentBuilder(common: rules.common)
    }

    public func segments(in text: String) throws -> [Segment] {
        let prepared = builder.prepared(for: text)
        return MarkupScanner.scan(text, options: options).flatMap { node in
            prepared.build(candidate: node.range, kind: .htmlText) {
                MarkupEntities.unescape($0, table: MarkupEntities.htmlTable)
            }
        }
    }

    public func escape(_ corrected: String, like original: Segment) -> String {
        MarkupEntities.escape(corrected,
                              style: .detect(in: original.raw, table: MarkupEntities.htmlTable))
    }
}
```

- [ ] **Step 4: Spusť test a ověř, že projde**

Run: `make test`
Expected: PASS — 58 testů celkem.

- [ ] **Step 5: Commit**

```bash
git add Sources/CzechatorCore/Handlers/HTMLHandler.swift \
        Tests/CzechatorCoreTests/HTMLHandlerTests.swift
git commit -m "feat: handler HTML"
```

---

## Task 9: FormatRegistry

**Files:**
- Create: `Sources/CzechatorCore/Detection/FormatRegistry.swift`
- Test: `Tests/CzechatorCoreTests/FormatRegistryTests.swift`

**Interfaces:**
- Consumes: všechny čtyři handlery (Tasky 4, 5, 7, 8), `ClipboardInput` (Task 4), `SegmentationRules` (Task 3).
- Produces:
  - `struct FormatRegistry: Sendable` s `init(rules: SegmentationRules) throws`
  - `FormatRegistry.select(_ input: ClipboardInput) -> (id: String, handler: any FormatHandler)`
  - `FormatRegistry.handler(id: String) -> (any FormatHandler)?`
  - `FormatRegistry.availableIDs: [String]`

- [ ] **Step 1: Napiš padající test**

`Tests/CzechatorCoreTests/FormatRegistryTests.swift`:

```swift
import Testing
@testable import CzechatorCore

private func registry() throws -> FormatRegistry { try FormatRegistry(rules: .builtIn) }

@Test func picksJSONForParsableJSON() throws {
    #expect(try registry().select(ClipboardInput(text: #"{"a": "b"}"#)).id == "json")
}

@Test func picksHTMLForDeclaredHTMLUTI() throws {
    let input = ClipboardInput(text: "<p>x</p>", uti: "public.html", plainText: "x")
    #expect(try registry().select(input).id == "html")
}

@Test func picksXMLForDeclaredXMLDocument() throws {
    #expect(try registry().select(ClipboardInput(text: "<?xml version=\"1.0\"?><r>x</r>")).id == "xml")
}

@Test func fallsBackToPlainText() throws {
    #expect(try registry().select(ClipboardInput(text: "obycejny text")).id == "plain")
}

@Test func exposesHandlersByIdentifier() throws {
    let r = try registry()
    #expect(r.availableIDs == ["json", "html", "xml", "plain"])
    #expect(r.handler(id: "json") != nil)
    #expect(r.handler(id: "neexistuje") == nil)
}
```

- [ ] **Step 2: Spusť test a ověř, že selže**

Run: `make test`
Expected: FAIL — `cannot find 'FormatRegistry' in scope`.

- [ ] **Step 3: Napiš implementaci**

`Sources/CzechatorCore/Detection/FormatRegistry.swift`:

```swift
/// Picks the handler with the highest confidence. Ties are broken by
/// registration order, so `plain` — which always bids a constant 0.1 — only
/// wins when nobody else claims the input.
public struct FormatRegistry: Sendable {

    private struct Entry: Sendable {
        let id: String
        let confidence: @Sendable (ClipboardInput) -> Double
        let handler: any FormatHandler
    }

    private let entries: [Entry]

    public init(rules: SegmentationRules) throws {
        entries = [
            Entry(id: JSONHandler.id, confidence: JSONHandler.confidence,
                  handler: try JSONHandler(rules: rules)),
            Entry(id: HTMLHandler.id, confidence: HTMLHandler.confidence,
                  handler: try HTMLHandler(rules: rules)),
            Entry(id: XMLHandler.id, confidence: XMLHandler.confidence,
                  handler: try XMLHandler(rules: rules)),
            Entry(id: PlainTextHandler.id, confidence: PlainTextHandler.confidence,
                  handler: try PlainTextHandler(rules: rules)),
        ]
    }

    public var availableIDs: [String] { entries.map(\.id) }

    public func handler(id: String) -> (any FormatHandler)? {
        entries.first { $0.id == id }?.handler
    }

    public func select(_ input: ClipboardInput) -> (id: String, handler: any FormatHandler) {
        var best = entries[entries.count - 1]
        var bestScore = best.confidence(input)
        for entry in entries {
            let score = entry.confidence(input)
            if score > bestScore {
                best = entry
                bestScore = score
            }
        }
        return (best.id, best.handler)
    }
}
```

- [ ] **Step 4: Spusť test a ověř, že projde**

Run: `make test`
Expected: PASS — 63 testů celkem.

- [ ] **Step 5: Commit**

```bash
git add Sources/CzechatorCore/Detection/FormatRegistry.swift \
        Tests/CzechatorCoreTests/FormatRegistryTests.swift
git commit -m "feat: výběr handleru podle confidence"
```

---

## Task 10: Verifikátor

**Files:**
- Create: `Sources/CzechatorCore/Verification/DiacriticVerifier.swift`
- Test: `Tests/CzechatorCoreTests/DiacriticVerifierTests.swift`

**Interfaces:**
- Consumes: `DiacriticFolding` (Task 1), `Segment` (Task 2).
- Produces:
  - `DiacriticVerifier.documentMatches(original: String, corrected: String) -> Bool`
  - `DiacriticVerifier.failingIndices(segments: [Segment], corrections: [String]) -> [Int]`

- [ ] **Step 1: Napiš padající test**

`Tests/CzechatorCoreTests/DiacriticVerifierTests.swift`:

```swift
import Testing
@testable import CzechatorCore

@Test func acceptsPureDiacriticRestoration() {
    #expect(DiacriticVerifier.documentMatches(original: "Prilis zlutoucky kun",
                                              corrected: "Příliš žluťoučký kůň"))
}

@Test func rejectsAddedText() {
    #expect(!DiacriticVerifier.documentMatches(original: "Prilis zlutoucky kun",
                                               corrected: "Příliš žluťoučký kůň. Hotovo!"))
}

@Test func rejectsReformatting() {
    #expect(!DiacriticVerifier.documentMatches(original: #"{"a":"x"}"#,
                                               corrected: #"{ "a": "x" }"#))
}

@Test func rejectsCaseChanges() {
    #expect(!DiacriticVerifier.documentMatches(original: "ahoj", corrected: "Ahoj"))
}

@Test func rejectsWhitespaceChanges() {
    #expect(!DiacriticVerifier.documentMatches(original: "a  b", corrected: "a b"))
}

@Test func identifiesOnlyTheOffendingSegments() {
    let text = "prvni druhy treti"
    func segment(_ s: String) -> Segment {
        Segment(range: text.range(of: s)!, raw: s, text: s, kind: .plain)
    }
    let segments = [segment("prvni"), segment("druhy"), segment("treti")]
    let corrections = ["první", "druhý navíc", "třetí"]
    #expect(DiacriticVerifier.failingIndices(segments: segments, corrections: corrections) == [1])
}

@Test func reportsEverythingWhenCountsDisagree() {
    let text = "a"
    let segments = [Segment(range: text.startIndex..<text.endIndex, raw: "a", text: "a", kind: .plain)]
    #expect(DiacriticVerifier.failingIndices(segments: segments, corrections: []) == [0])
}
```

- [ ] **Step 2: Spusť test a ověř, že selže**

Run: `make test`
Expected: FAIL — `cannot find 'DiacriticVerifier' in scope`.

- [ ] **Step 3: Napiš implementaci**

`Sources/CzechatorCore/Verification/DiacriticVerifier.swift`:

```swift
/// The tool's single hard guarantee: after folding away Czech diacritics the
/// output must be *exactly* the input. This catches structural edits, casing
/// changes, reformatting, and any commentary the model volunteers.
///
/// It deliberately does NOT catch wrong diacritics — English text that the
/// model decorated folds back to the same string. That is a prompt and model
/// quality problem, not an architectural one.
public enum DiacriticVerifier {

    public static func documentMatches(original: String, corrected: String) -> Bool {
        DiacriticFolding.fold(original) == DiacriticFolding.fold(corrected)
    }

    /// Indices of segments whose correction changed something other than
    /// diacritics. Used to retry just the offenders instead of the whole batch.
    public static func failingIndices(segments: [Segment], corrections: [String]) -> [Int] {
        guard segments.count == corrections.count else {
            return Array(segments.indices)
        }
        return segments.indices.filter {
            !documentMatches(original: segments[$0].text, corrected: corrections[$0])
        }
    }
}
```

- [ ] **Step 4: Spusť test a ověř, že projde**

Run: `make test`
Expected: PASS — 70 testů celkem.

- [ ] **Step 5: Commit**

```bash
git add Sources/CzechatorCore/Verification/DiacriticVerifier.swift \
        Tests/CzechatorCoreTests/DiacriticVerifierTests.swift
git commit -m "feat: verifikace invariantu diakritiky"
```

---
## Task 11: Číslovaný seznam a prompt

**Files:**
- Create: `Sources/CzechatorCore/Providers/NumberedList.swift`
- Create: `Sources/CzechatorCore/Providers/PromptBuilder.swift`
- Test: `Tests/CzechatorCoreTests/NumberedListTests.swift`

**Interfaces:**
- Consumes: nic.
- Produces:
  - `enum NumberedListError: Error, Equatable { case countMismatch(expected: Int, got: Int), badNumbering(atItem: Int) }`
  - `NumberedList.encode(_ items: [String]) -> String`
  - `NumberedList.decode(_ text: String, expectedCount: Int) throws -> [String]`
  - `struct Prompt: Sendable, Equatable { let system: String; let user: String }`
  - `PromptBuilder.defaultSystem: String`
  - `PromptBuilder.build(items: [String], systemOverride: String?) -> Prompt`

**Proč se escapují nové řádky:** segment může obsahovat skutečný nový řádek (rozbalené `\n` z JSONu). Kdyby šel do promptu doslova, rozbil by číslování seznamu. Kodér ho proto převede na dvojznak `\n` a instrukce v systémové zprávě modelu říká, ať ho nechá být.

- [ ] **Step 1: Napiš padající test**

`Tests/CzechatorCoreTests/NumberedListTests.swift`:

```swift
import Testing
@testable import CzechatorCore

@Test func encodesItemsWithOneBasedNumbering() {
    #expect(NumberedList.encode(["prvni", "druhy"]) == "1. prvni\n2. druhy")
}

@Test func escapesNewlinesAndBackslashes() {
    #expect(NumberedList.encode(["a\nb", "c\\d"]) == "1. a\\nb\n2. c\\\\d")
}

@Test func decodeRoundTripsEncode() throws {
    let items = ["prvni radek", "s\nnovym radkem", "zpetne \\ lomitko"]
    #expect(try NumberedList.decode(NumberedList.encode(items), expectedCount: 3) == items)
}

@Test func decodeToleratesCodeFencesAndBlankLines() throws {
    let response = "```\n\n1. prvni\n\n2. druhy\n```\n"
    #expect(try NumberedList.decode(response, expectedCount: 2) == ["prvni", "druhy"])
}

@Test func decodeRejectsWrongCount() {
    #expect(throws: NumberedListError.countMismatch(expected: 3, got: 2)) {
        try NumberedList.decode("1. a\n2. b", expectedCount: 3)
    }
}

@Test func decodeRejectsWrongNumbering() {
    #expect(throws: NumberedListError.badNumbering(atItem: 1)) {
        try NumberedList.decode("1. a\n3. b", expectedCount: 2)
    }
}

@Test func systemPromptIsStableAndEnglish() {
    let a = PromptBuilder.build(items: ["x"], systemOverride: nil).system
    let b = PromptBuilder.build(items: ["y", "z"], systemOverride: nil).system
    #expect(a == b)
    #expect(a == PromptBuilder.defaultSystem)
    #expect(a.contains("Czech diacritics"))
}

@Test func userMessageCarriesOnlyTheVariablePart() {
    let prompt = PromptBuilder.build(items: ["prvni", "druhy"], systemOverride: nil)
    #expect(prompt.user == "1. prvni\n2. druhy")
}

@Test func systemOverrideReplacesTheBuiltInPrompt() {
    #expect(PromptBuilder.build(items: ["x"], systemOverride: "vlastni").system == "vlastni")
}
```

- [ ] **Step 2: Spusť test a ověř, že selže**

Run: `make test`
Expected: FAIL — `cannot find 'NumberedList' in scope`.

- [ ] **Step 3: Napiš implementaci**

`Sources/CzechatorCore/Providers/NumberedList.swift`:

```swift
public enum NumberedListError: Error, Equatable {
    case countMismatch(expected: Int, got: Int)
    case badNumbering(atItem: Int)
}

/// Wire format between the tool and the model. Items are escaped so a segment
/// containing a real newline cannot break the list structure.
public enum NumberedList {

    public static func encode(_ items: [String]) -> String {
        items.enumerated()
            .map { "\($0.offset + 1). \(escape($0.element))" }
            .joined(separator: "\n")
    }

    public static func decode(_ text: String, expectedCount: Int) throws -> [String] {
        var items: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("```") { continue }
            guard let dot = trimmed.firstIndex(of: "."),
                  let number = Int(trimmed[trimmed.startIndex..<dot]) else { continue }
            guard number == items.count + 1 else {
                throw NumberedListError.badNumbering(atItem: items.count + 1)
            }
            var body = trimmed[trimmed.index(after: dot)...]
            if body.hasPrefix(" ") { body = body.dropFirst() }
            items.append(unescape(body))
        }
        guard items.count == expectedCount else {
            throw NumberedListError.countMismatch(expected: expectedCount, got: items.count)
        }
        return items
    }

    private static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for character in s {
            switch character {
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.append(character)
            }
        }
        return out
    }

    private static func unescape(_ s: Substring) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var index = s.startIndex
        while index < s.endIndex {
            guard s[index] == "\\", s.index(after: index) < s.endIndex else {
                out.append(s[index])
                index = s.index(after: index)
                continue
            }
            let next = s[s.index(after: index)]
            switch next {
            case "n": out.append("\n")
            case "r": out.append("\r")
            case "t": out.append("\t")
            case "\\": out.append("\\")
            default:
                out.append(s[index])
                out.append(next)
            }
            index = s.index(index, offsetBy: 2)
        }
        return out
    }
}
```

> `trimmingCharacters(in:)` vyžaduje `import Foundation` — přidej ho na začátek souboru.

`Sources/CzechatorCore/Providers/PromptBuilder.swift`:

```swift
public struct Prompt: Sendable, Equatable {
    public let system: String
    public let user: String

    public init(system: String, user: String) {
        self.system = system
        self.user = user
    }
}

public enum PromptBuilder {

    /// Instructions in English, examples in Czech. Small instruct models follow
    /// English rules noticeably better, while the few-shot examples must be
    /// Czech because they are what actually demonstrates the task.
    ///
    /// MUST stay byte-identical between calls — Ollama caches the prefill for a
    /// stable prefix. Anything variable belongs in the user message.
    public static let defaultSystem = """
        You restore Czech diacritics.

        Rules:
        - Output ONLY the numbered list, with the same count and numbering as the input.
        - Change nothing except adding Czech diacritical marks.
        - Never translate, reword, reformat, or fix spelling, grammar or punctuation.
        - Preserve casing, whitespace, and all non-letter characters exactly.
        - The sequences \\n, \\r, \\t and \\\\ are literal two-character escapes. Keep them as-is.
        - Leave text that is not Czech unchanged.

        Example
        input:
        1. Prilis zlutoucky kun upel dabelske ody.
        2. Vcera jsem koupil novy pocitac.
        output:
        1. Příliš žluťoučký kůň úpěl ďábelské ódy.
        2. Včera jsem koupil nový počítač.
        """

    public static func build(items: [String], systemOverride: String?) -> Prompt {
        Prompt(system: systemOverride ?? defaultSystem, user: NumberedList.encode(items))
    }
}
```

- [ ] **Step 4: Spusť test a ověř, že projde**

Run: `make test`
Expected: PASS — 79 testů celkem.

- [ ] **Step 5: Commit**

```bash
git add Sources/CzechatorCore/Providers/NumberedList.swift \
        Sources/CzechatorCore/Providers/PromptBuilder.swift \
        Tests/CzechatorCoreTests/NumberedListTests.swift
git commit -m "feat: protokol číslovaného seznamu a sestavení promptu"
```

---

## Task 12: HTTP klient a poskytovatel Ollama

**Files:**
- Create: `Sources/CzechatorCore/Providers/HTTPClient.swift`
- Create: `Sources/CzechatorCore/Providers/LLMProvider.swift`
- Create: `Sources/CzechatorCore/Providers/OllamaProvider.swift`
- Test: `Tests/CzechatorCoreTests/OllamaProviderTests.swift`

**Interfaces:**
- Consumes: `Prompt` (Task 11).
- Produces:
  - `enum HTTPError: Error, Equatable { case status(code: Int, body: String), transport(String) }`
  - `protocol HTTPClient: Sendable { func post(url: URL, headers: [String: String], body: Data, timeout: TimeInterval) async throws -> Data }`
  - `struct URLSessionHTTPClient: HTTPClient` s `init()`
  - `protocol LLMProvider: Sendable { func complete(_ prompt: Prompt) async throws -> String }`
  - `enum ProviderError: Error, Equatable { case malformedResponse(String), empty }`
  - `struct OllamaProvider: LLMProvider` s `init(endpoint: URL, model: String, temperature: Double, timeout: TimeInterval, client: any HTTPClient)`

- [ ] **Step 1: Napiš padající test**

`Tests/CzechatorCoreTests/OllamaProviderTests.swift`:

```swift
import Foundation
import Testing
@testable import CzechatorCore

/// Records the last request and replays a canned response.
final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    var response: Data
    var error: (any Error)?
    private(set) var lastURL: URL?
    private(set) var lastBody: Data?
    private(set) var lastHeaders: [String: String] = [:]

    init(response: Data) { self.response = response }

    func post(url: URL, headers: [String: String], body: Data,
              timeout: TimeInterval) async throws -> Data {
        lastURL = url
        lastBody = body
        lastHeaders = headers
        if let error { throw error }
        return response
    }
}

private func ollama(_ client: FakeHTTPClient) -> OllamaProvider {
    OllamaProvider(endpoint: URL(string: "http://localhost:11434")!,
                   model: "qwen3:4b-instruct",
                   temperature: 0,
                   timeout: 30,
                   client: client)
}

@Test func extractsMessageContent() async throws {
    let client = FakeHTTPClient(
        response: Data(#"{"message":{"role":"assistant","content":"1. Příliš"}}"#.utf8))
    let result = try await ollama(client).complete(Prompt(system: "s", user: "u"))
    #expect(result == "1. Příliš")
}

@Test func postsToChatEndpointWithStreamingDisabled() async throws {
    let client = FakeHTTPClient(response: Data(#"{"message":{"content":"x"}}"#.utf8))
    _ = try await ollama(client).complete(Prompt(system: "s", user: "u"))

    #expect(client.lastURL?.absoluteString == "http://localhost:11434/api/chat")
    let body = try JSONSerialization.jsonObject(with: client.lastBody!) as! [String: Any]
    #expect(body["model"] as? String == "qwen3:4b-instruct")
    #expect(body["stream"] as? Bool == false)
    let messages = body["messages"] as! [[String: String]]
    #expect(messages.map { $0["role"]! } == ["system", "user"])
    #expect(messages[0]["content"] == "s")
    #expect(messages[1]["content"] == "u")
    let options = body["options"] as! [String: Any]
    #expect(options["temperature"] as? Double == 0)
}

@Test func reportsMalformedResponses() async {
    let client = FakeHTTPClient(response: Data(#"{"neco":"jineho"}"#.utf8))
    await #expect(throws: (any Error).self) {
        try await ollama(client).complete(Prompt(system: "s", user: "u"))
    }
}

@Test func propagatesTransportErrors() async {
    let client = FakeHTTPClient(response: Data())
    client.error = HTTPError.transport("spojení odmítnuto")
    await #expect(throws: HTTPError.transport("spojení odmítnuto")) {
        try await ollama(client).complete(Prompt(system: "s", user: "u"))
    }
}
```

- [ ] **Step 2: Spusť test a ověř, že selže**

Run: `make test`
Expected: FAIL — `cannot find 'HTTPClient' in scope`.

- [ ] **Step 3: Napiš implementaci**

`Sources/CzechatorCore/Providers/HTTPClient.swift`:

```swift
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum HTTPError: Error, Equatable {
    case status(code: Int, body: String)
    case transport(String)
}

public protocol HTTPClient: Sendable {
    func post(url: URL,
              headers: [String: String],
              body: Data,
              timeout: TimeInterval) async throws -> Data
}

public struct URLSessionHTTPClient: HTTPClient {

    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func post(url: URL,
                     headers: [String: String],
                     body: Data,
                     timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw HTTPError.transport(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPError.status(code: http.statusCode,
                                   body: String(decoding: data, as: UTF8.self))
        }
        return data
    }
}
```

`Sources/CzechatorCore/Providers/LLMProvider.swift`:

```swift
public enum ProviderError: Error, Equatable {
    case malformedResponse(String)
    case empty
}

public protocol LLMProvider: Sendable {
    func complete(_ prompt: Prompt) async throws -> String
}
```

`Sources/CzechatorCore/Providers/OllamaProvider.swift`:

```swift
import Foundation

public struct OllamaProvider: LLMProvider {

    private let endpoint: URL
    private let model: String
    private let temperature: Double
    private let timeout: TimeInterval
    private let client: any HTTPClient

    public init(endpoint: URL, model: String, temperature: Double,
                timeout: TimeInterval, client: any HTTPClient) {
        self.endpoint = endpoint
        self.model = model
        self.temperature = temperature
        self.timeout = timeout
        self.client = client
    }

    private struct Response: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }

    public func complete(_ prompt: Prompt) async throws -> String {
        let payload: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "system", "content": prompt.system],
                ["role": "user", "content": prompt.user],
            ],
            "options": ["temperature": temperature],
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await client.post(url: endpoint.appendingPathComponent("api/chat"),
                                         headers: [:],
                                         body: body,
                                         timeout: timeout)
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw ProviderError.malformedResponse(String(decoding: data.prefix(200), as: UTF8.self))
        }
        guard !decoded.message.content.isEmpty else { throw ProviderError.empty }
        return decoded.message.content
    }
}
```

- [ ] **Step 4: Spusť test a ověř, že projde**

Run: `make test`
Expected: PASS — 83 testů celkem.

- [ ] **Step 5: Commit**

```bash
git add Sources/CzechatorCore/Providers Tests/CzechatorCoreTests/OllamaProviderTests.swift
git commit -m "feat: HTTP klient a poskytovatel Ollama"
```

---

## Task 13: Tajemství a poskytovatel kompatibilní s OpenAI

**Files:**
- Create: `Sources/CzechatorCore/Config/SecretResolver.swift`
- Create: `Sources/CzechatorCore/Providers/OpenAICompatProvider.swift`
- Test: `Tests/CzechatorCoreTests/OpenAICompatProviderTests.swift`

**Interfaces:**
- Consumes: `HTTPClient`, `LLMProvider`, `ProviderError` (Task 12); `Prompt` (Task 11). `FakeHTTPClient` z Tasku 12 se použije znovu.
- Produces:
  - `enum SecretRef: Sendable, Equatable, Codable { case keychain(account: String), environment(name: String), literal(String) }` — YAML tvar `{ source: keychain, account: "..." }`, `{ source: env, name: "..." }`, `{ source: literal, value: "..." }`
  - `enum SecretError: Error, Equatable { case notFound(String), unsupported(String) }`
  - `protocol SecretResolver: Sendable { func resolve(_ ref: SecretRef) throws -> String }`
  - `struct EnvironmentSecretResolver: SecretResolver` — umí `.environment` a `.literal`, na `.keychain` vyhodí `.unsupported`
  - `struct StaticSecretResolver: SecretResolver` s `init(_ values: [String: String])` pro testy
  - `struct OpenAICompatProvider: LLMProvider` s `init(endpoint: URL, model: String, temperature: Double, timeout: TimeInterval, apiKey: String?, client: any HTTPClient)`

- [ ] **Step 1: Napiš padající test**

`Tests/CzechatorCoreTests/OpenAICompatProviderTests.swift`:

```swift
import Foundation
import Testing
@testable import CzechatorCore

private func openAI(_ client: FakeHTTPClient, apiKey: String? = "tajny-klic") -> OpenAICompatProvider {
    OpenAICompatProvider(endpoint: URL(string: "https://api.openai.com/v1")!,
                         model: "gpt-4o-mini",
                         temperature: 0,
                         timeout: 30,
                         apiKey: apiKey,
                         client: client)
}

@Test func extractsFirstChoiceContent() async throws {
    let client = FakeHTTPClient(
        response: Data(#"{"choices":[{"message":{"content":"1. Příliš"}}]}"#.utf8))
    #expect(try await openAI(client).complete(Prompt(system: "s", user: "u")) == "1. Příliš")
}

@Test func sendsAuthorizationHeaderAndCorrectPath() async throws {
    let client = FakeHTTPClient(response: Data(#"{"choices":[{"message":{"content":"x"}}]}"#.utf8))
    _ = try await openAI(client).complete(Prompt(system: "s", user: "u"))

    #expect(client.lastURL?.absoluteString == "https://api.openai.com/v1/chat/completions")
    #expect(client.lastHeaders["Authorization"] == "Bearer tajny-klic")
}

@Test func omitsAuthorizationWhenNoKeyIsConfigured() async throws {
    let client = FakeHTTPClient(response: Data(#"{"choices":[{"message":{"content":"x"}}]}"#.utf8))
    _ = try await openAI(client, apiKey: nil).complete(Prompt(system: "s", user: "u"))
    #expect(client.lastHeaders["Authorization"] == nil)
}

@Test func environmentResolverReadsLiteralsAndVariables() throws {
    let resolver = EnvironmentSecretResolver()
    #expect(try resolver.resolve(.literal("primo")) == "primo")
    #expect(throws: SecretError.notFound("CZECHATOR_TEST_NEEXISTUJE")) {
        try resolver.resolve(.environment(name: "CZECHATOR_TEST_NEEXISTUJE"))
    }
    #expect(throws: SecretError.unsupported("keychain")) {
        try resolver.resolve(.keychain(account: "x"))
    }
}

@Test func secretRefRoundTripsThroughJSON() throws {
    let refs: [SecretRef] = [.keychain(account: "czechator-openai"),
                             .environment(name: "OPENAI_API_KEY"),
                             .literal("abc")]
    for ref in refs {
        let data = try JSONEncoder().encode(ref)
        #expect(try JSONDecoder().decode(SecretRef.self, from: data) == ref)
    }
}
```

- [ ] **Step 2: Spusť test a ověř, že selže**

Run: `make test`
Expected: FAIL — `cannot find 'OpenAICompatProvider' in scope`.

- [ ] **Step 3: Napiš implementaci**

`Sources/CzechatorCore/Config/SecretResolver.swift`:

```swift
import Foundation

/// A reference to a secret, never the secret itself. Config files hold these;
/// the actual value is fetched lazily, right before building the auth header,
/// so nothing that gets logged or stored in history can contain a key.
public enum SecretRef: Sendable, Equatable, Codable {
    case keychain(account: String)
    case environment(name: String)
    case literal(String)

    private enum CodingKeys: String, CodingKey {
        case source, account, name, value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .source) {
        case "keychain":
            self = .keychain(account: try container.decode(String.self, forKey: .account))
        case "env", "environment":
            self = .environment(name: try container.decode(String.self, forKey: .name))
        case "literal":
            self = .literal(try container.decode(String.self, forKey: .value))
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .source, in: container,
                debugDescription: "neznámý zdroj tajemství: \(other)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .keychain(let account):
            try container.encode("keychain", forKey: .source)
            try container.encode(account, forKey: .account)
        case .environment(let name):
            try container.encode("env", forKey: .source)
            try container.encode(name, forKey: .name)
        case .literal(let value):
            try container.encode("literal", forKey: .source)
            try container.encode(value, forKey: .value)
        }
    }
}

public enum SecretError: Error, Equatable {
    case notFound(String)
    case unsupported(String)
}

/// Implementations live outside the core: Keychain on macOS, environment
/// variables everywhere else. This is what keeps `Security.framework` out of
/// `CzechatorCore`.
public protocol SecretResolver: Sendable {
    func resolve(_ ref: SecretRef) throws -> String
}

public struct EnvironmentSecretResolver: SecretResolver {

    public init() {}

    public func resolve(_ ref: SecretRef) throws -> String {
        switch ref {
        case .literal(let value):
            return value
        case .environment(let name):
            guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
                throw SecretError.notFound(name)
            }
            return value
        case .keychain:
            throw SecretError.unsupported("keychain")
        }
    }
}

public struct StaticSecretResolver: SecretResolver {

    private let values: [String: String]

    public init(_ values: [String: String]) { self.values = values }

    public func resolve(_ ref: SecretRef) throws -> String {
        switch ref {
        case .literal(let value): return value
        case .environment(let name):
            guard let value = values[name] else { throw SecretError.notFound(name) }
            return value
        case .keychain(let account):
            guard let value = values[account] else { throw SecretError.notFound(account) }
            return value
        }
    }
}
```

`Sources/CzechatorCore/Providers/OpenAICompatProvider.swift`:

```swift
import Foundation

public struct OpenAICompatProvider: LLMProvider {

    private let endpoint: URL
    private let model: String
    private let temperature: Double
    private let timeout: TimeInterval
    private let apiKey: String?
    private let client: any HTTPClient

    public init(endpoint: URL, model: String, temperature: Double,
                timeout: TimeInterval, apiKey: String?, client: any HTTPClient) {
        self.endpoint = endpoint
        self.model = model
        self.temperature = temperature
        self.timeout = timeout
        self.apiKey = apiKey
        self.client = client
    }

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let choices: [Choice]
    }

    public func complete(_ prompt: Prompt) async throws -> String {
        let payload: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "messages": [
                ["role": "system", "content": prompt.system],
                ["role": "user", "content": prompt.user],
            ],
        ]
        var headers: [String: String] = [:]
        if let apiKey { headers["Authorization"] = "Bearer \(apiKey)" }

        let data = try await client.post(
            url: endpoint.appendingPathComponent("chat/completions"),
            headers: headers,
            body: try JSONSerialization.data(withJSONObject: payload),
            timeout: timeout)

        guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
              let first = decoded.choices.first else {
            throw ProviderError.malformedResponse(String(decoding: data.prefix(200), as: UTF8.self))
        }
        guard !first.message.content.isEmpty else { throw ProviderError.empty }
        return first.message.content
    }
}
```

- [ ] **Step 4: Spusť test a ověř, že projde**

Run: `make test`
Expected: PASS — 88 testů celkem.

- [ ] **Step 5: Commit**

```bash
git add Sources/CzechatorCore/Config/SecretResolver.swift \
        Sources/CzechatorCore/Providers/OpenAICompatProvider.swift \
        Tests/CzechatorCoreTests/OpenAICompatProviderTests.swift
git commit -m "feat: odkazy na tajemství a poskytovatel kompatibilní s OpenAI"
```

---

## Task 14: SegmentBatcher

**Files:**
- Create: `Sources/CzechatorCore/Batching/SegmentBatcher.swift`
- Test: `Tests/CzechatorCoreTests/SegmentBatcherTests.swift`

**Interfaces:**
- Consumes: `Segment` (Task 2).
- Produces: `SegmentBatcher.batches(_ segments: [Segment], maxChars: Int) -> [[Int]]` — vrací **indexy** do vstupního pole, aby si volající uměl výsledky namapovat zpět.

- [ ] **Step 1: Napiš padající test**

`Tests/CzechatorCoreTests/SegmentBatcherTests.swift`:

```swift
import Testing
@testable import CzechatorCore

private func segments(_ lengths: [Int]) -> [Segment] {
    let text = String(repeating: "a", count: lengths.reduce(0, +))
    var result: [Segment] = []
    var start = text.startIndex
    for length in lengths {
        let end = text.index(start, offsetBy: length)
        let body = String(text[start..<end])
        result.append(Segment(range: start..<end, raw: body, text: body, kind: .plain))
        start = end
    }
    return result
}

@Test func fitsEverythingIntoOneBatchWhenItIsSmallEnough() {
    #expect(SegmentBatcher.batches(segments([10, 10, 10]), maxChars: 100) == [[0, 1, 2]])
}

@Test func startsANewBatchWhenTheLimitWouldBeExceeded() {
    #expect(SegmentBatcher.batches(segments([40, 40, 40]), maxChars: 100) == [[0, 1], [2]])
}

@Test func neverProducesAnEmptyBatchForAnOversizedSegment() {
    #expect(SegmentBatcher.batches(segments([500]), maxChars: 100) == [[0]])
}

@Test func returnsNothingForNoSegments() {
    #expect(SegmentBatcher.batches([], maxChars: 100).isEmpty)
}
```

- [ ] **Step 2: Spusť test a ověř, že selže**

Run: `make test`
Expected: FAIL — `cannot find 'SegmentBatcher' in scope`.

- [ ] **Step 3: Napiš implementaci**

`Sources/CzechatorCore/Batching/SegmentBatcher.swift`:

```swift
public enum SegmentBatcher {

    /// Greedy packing by character count. Returns indices into `segments` so the
    /// caller can map results back without rebuilding the segment list.
    ///
    /// A single segment larger than `maxChars` still gets its own batch — the
    /// alternative would be splitting it, which would break reassembly.
    public static func batches(_ segments: [Segment], maxChars: Int) -> [[Int]] {
        var result: [[Int]] = []
        var current: [Int] = []
        var currentSize = 0

        for (index, segment) in segments.enumerated() {
            let size = segment.text.count
            if !current.isEmpty, currentSize + size > maxChars {
                result.append(current)
                current = []
                currentSize = 0
            }
            current.append(index)
            currentSize += size
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
```

- [ ] **Step 4: Spusť test a ověř, že projde**

Run: `make test`
Expected: PASS — 92 testů celkem.

- [ ] **Step 5: Commit**

```bash
git add Sources/CzechatorCore/Batching Tests/CzechatorCoreTests/SegmentBatcherTests.swift
git commit -m "feat: dávkování segmentů"
```

---
## Task 15: Pipeline

**Files:**
- Create: `Sources/CzechatorCore/Pipeline.swift`
- Create: `Sources/CzechatorCore/Config/Limits.swift`
- Test: `Tests/CzechatorCoreTests/PipelineTests.swift`

**Interfaces:**
- Consumes: `FormatRegistry` (Task 9), `DiacriticVerifier` (Task 10), `PromptBuilder`, `NumberedList` (Task 11), `LLMProvider` (Task 12), `SegmentBatcher` (Task 14), `Reassembler` (Task 2), `DiacriticFolding` (Task 1).
- Produces:
  - `struct Limits: Sendable, Codable, Equatable { var maxInputBytes: Int; var maxBatchChars: Int }` + `Limits.builtIn`
  - `struct PipelineResult: Sendable, Equatable` s `formatID`, `originalText`, `correctedText`, `correctedPlainText: String?`, `segmentCount: Int`, `changedSegmentCount: Int`
  - `enum PipelineError: Error, Equatable { case noText, inputTooLarge(bytes: Int, limit: Int), providerFailed(String), verificationFailed(failedSegments: Int) }`
  - `struct Pipeline: Sendable` s `init(registry: FormatRegistry, provider: any LLMProvider, limits: Limits, promptOverride: String?)` a `func run(_ input: ClipboardInput) async throws -> PipelineResult`

**Tři věci, které se v tomto tasku snadno přehlédnou:**

1. **Nezměněný segment se vkládá jako `segment.raw`**, nikoli přes `escape`. Tím se úplně obejde riziko, že round trip escapování změní jediný bajt.
2. **Cache oprav klíčovaná složeným textem** (`fold(segment.text)`). HTML i plain reprezentace téže schránky obsahují stejná slova, takže druhý průchod je téměř celý z cache a nestojí další volání modelu.
3. **Verifikace běží dvakrát** — jednou po segmentech (aby šlo zopakovat jen viníky) a jednou nad celým složeným dokumentem (aby se chytila chyba ve skládání).

- [ ] **Step 1: Napiš padající test**

`Tests/CzechatorCoreTests/PipelineTests.swift`:

```swift
import Foundation
import Testing
@testable import CzechatorCore

/// Returns whatever the closure produces for each numbered-list request.
final class FakeProvider: LLMProvider, @unchecked Sendable {
    let transform: @Sendable ([String]) -> [String]
    private(set) var callCount = 0

    init(transform: @escaping @Sendable ([String]) -> [String]) { self.transform = transform }

    func complete(_ prompt: Prompt) async throws -> String {
        callCount += 1
        let items = try NumberedList.decode(prompt.user, expectedCount: countOfItems(in: prompt.user))
        return NumberedList.encode(transform(items))
    }

    private func countOfItems(in user: String) -> Int {
        user.split(separator: "\n").filter { $0.first?.isNumber == true }.count
    }
}

private let restore: @Sendable ([String]) -> [String] = { items in
    items.map {
        $0.replacingOccurrences(of: "Prilis", with: "Příliš")
            .replacingOccurrences(of: "zlutoucky", with: "žluťoučký")
            .replacingOccurrences(of: "kun", with: "kůň")
            .replacingOccurrences(of: "svete", with: "světe")
    }
}

private func pipeline(_ provider: any LLMProvider,
                      limits: Limits = .builtIn) throws -> Pipeline {
    Pipeline(registry: try FormatRegistry(rules: .builtIn),
             provider: provider,
             limits: limits,
             promptOverride: nil)
}

@Test func correctsPlainText() async throws {
    let result = try await pipeline(FakeProvider(transform: restore))
        .run(ClipboardInput(text: "Prilis zlutoucky kun"))
    #expect(result.correctedText == "Příliš žluťoučký kůň")
    #expect(result.formatID == "plain")
    #expect(result.changedSegmentCount == 1)
}

@Test func correctsJSONValuesWithoutTouchingStructure() async throws {
    let text = #"{"id": "x", "popis": "Prilis zlutoucky kun"}"#
    let result = try await pipeline(FakeProvider(transform: restore)).run(ClipboardInput(text: text))
    #expect(result.correctedText == #"{"id": "x", "popis": "Příliš žluťoučký kůň"}"#)
    #expect(result.formatID == "json")
}

@Test func refusesOutputWhenTheModelAddsText() async {
    let chatty = FakeProvider { $0.map { $0 + " (hotovo)" } }
    await #expect(throws: PipelineError.verificationFailed(failedSegments: 1)) {
        try await pipeline(chatty).run(ClipboardInput(text: "Prilis zlutoucky kun"))
    }
}

@Test func reportsProviderFailureWhenTheListNeverParses() async {
    final class Garbage: LLMProvider, @unchecked Sendable {
        func complete(_ prompt: Prompt) async throws -> String { "nesmysl bez cislovani" }
    }
    await #expect(throws: (any Error).self) {
        try await pipeline(Garbage()).run(ClipboardInput(text: "Prilis zlutoucky kun"))
    }
}

@Test func reusesCorrectionsBetweenHTMLAndPlainRepresentations() async throws {
    let provider = FakeProvider(transform: restore)
    let input = ClipboardInput(text: "<p>Prilis zlutoucky kun</p>",
                               uti: "public.html",
                               plainText: "Prilis zlutoucky kun")
    let result = try await pipeline(provider).run(input)

    #expect(result.correctedText == "<p>Příliš žluťoučký kůň</p>")
    #expect(result.correctedPlainText == "Příliš žluťoučký kůň")
    // The plain pass is served entirely from the cache.
    #expect(provider.callCount == 1)
}

@Test func rejectsEmptyInput() async {
    await #expect(throws: PipelineError.noText) {
        try await pipeline(FakeProvider(transform: restore)).run(ClipboardInput(text: "   \n  "))
    }
}

@Test func rejectsOversizedInput() async {
    let big = String(repeating: "a bcd ", count: 100)
    await #expect(throws: PipelineError.inputTooLarge(bytes: big.utf8.count, limit: 100)) {
        try await pipeline(FakeProvider(transform: restore),
                           limits: Limits(maxInputBytes: 100, maxBatchChars: 1500))
            .run(ClipboardInput(text: big))
    }
}

@Test func returnsInputUnchangedWhenThereIsNothingToSegment() async throws {
    let provider = FakeProvider(transform: restore)
    let result = try await pipeline(provider).run(ClipboardInput(text: "12345 -- 67"))
    #expect(result.correctedText == "12345 -- 67")
    #expect(result.segmentCount == 0)
    #expect(provider.callCount == 0)
}
```

- [ ] **Step 2: Spusť test a ověř, že selže**

Run: `make test`
Expected: FAIL — `cannot find 'Pipeline' in scope`.

- [ ] **Step 3: Napiš implementaci**

`Sources/CzechatorCore/Config/Limits.swift`:

```swift
public struct Limits: Sendable, Codable, Equatable {
    public var maxInputBytes: Int
    public var maxBatchChars: Int

    public static let builtIn = Limits(maxInputBytes: 51_200, maxBatchChars: 1_500)

    public init(maxInputBytes: Int, maxBatchChars: Int) {
        self.maxInputBytes = maxInputBytes
        self.maxBatchChars = maxBatchChars
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Limits.builtIn
        maxInputBytes = try container.decodeIfPresent(Int.self, forKey: .maxInputBytes)
            ?? defaults.maxInputBytes
        maxBatchChars = try container.decodeIfPresent(Int.self, forKey: .maxBatchChars)
            ?? defaults.maxBatchChars
    }
}
```

`Sources/CzechatorCore/Pipeline.swift`:

```swift
import Foundation

public struct PipelineResult: Sendable, Equatable {
    public let formatID: String
    public let originalText: String
    public let correctedText: String
    public let correctedPlainText: String?
    public let segmentCount: Int
    public let changedSegmentCount: Int

    public init(formatID: String, originalText: String, correctedText: String,
                correctedPlainText: String?, segmentCount: Int, changedSegmentCount: Int) {
        self.formatID = formatID
        self.originalText = originalText
        self.correctedText = correctedText
        self.correctedPlainText = correctedPlainText
        self.segmentCount = segmentCount
        self.changedSegmentCount = changedSegmentCount
    }
}

public enum PipelineError: Error, Equatable {
    case noText
    case inputTooLarge(bytes: Int, limit: Int)
    case providerFailed(String)
    case verificationFailed(failedSegments: Int)
}

public struct Pipeline: Sendable {

    private let registry: FormatRegistry
    private let provider: any LLMProvider
    private let limits: Limits
    private let promptOverride: String?

    public init(registry: FormatRegistry, provider: any LLMProvider,
                limits: Limits, promptOverride: String?) {
        self.registry = registry
        self.provider = provider
        self.limits = limits
        self.promptOverride = promptOverride
    }

    public func run(_ input: ClipboardInput) async throws -> PipelineResult {
        guard !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PipelineError.noText
        }
        let bytes = input.text.utf8.count + (input.plainText?.utf8.count ?? 0)
        guard bytes <= limits.maxInputBytes else {
            throw PipelineError.inputTooLarge(bytes: bytes, limit: limits.maxInputBytes)
        }

        var cache: [String: String] = [:]
        let selected = registry.select(input)
        let main = try await correct(input.text, handler: selected.handler, cache: &cache)

        var correctedPlain: String?
        if let plain = input.plainText,
           plain != input.text,
           !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let plainHandler = registry.handler(id: PlainTextHandler.id) {
            correctedPlain = try await correct(plain, handler: plainHandler, cache: &cache)
        }

        return PipelineResult(formatID: selected.id,
                              originalText: input.text,
                              correctedText: main.text,
                              correctedPlainText: correctedPlain?.text,
                              segmentCount: main.segmentCount,
                              changedSegmentCount: main.changedCount)
    }

    private struct Corrected {
        let text: String
        let segmentCount: Int
        let changedCount: Int
    }

    private func correct(_ text: String,
                         handler: any FormatHandler,
                         cache: inout [String: String]) async throws -> Corrected {
        let segments = try handler.segments(in: text)
        guard !segments.isEmpty else {
            return Corrected(text: text, segmentCount: 0, changedCount: 0)
        }

        var corrections = [String](repeating: "", count: segments.count)
        var pending: [Int] = []
        for (index, segment) in segments.enumerated() {
            if let hit = cache[DiacriticFolding.fold(segment.text)] {
                corrections[index] = hit
            } else {
                pending.append(index)
            }
        }
        if !pending.isEmpty {
            try await fill(&corrections, indices: pending, segments: segments, cache: &cache)
        }

        // Retry only the segments that broke the invariant, exactly once.
        let failing = DiacriticVerifier.failingIndices(segments: segments, corrections: corrections)
        if !failing.isEmpty {
            try await fill(&corrections, indices: failing, segments: segments, cache: &cache)
            let stillFailing = DiacriticVerifier.failingIndices(segments: segments,
                                                               corrections: corrections)
            guard stillFailing.isEmpty else {
                throw PipelineError.verificationFailed(failedSegments: stillFailing.count)
            }
        }

        // Unchanged segments go back as their original bytes, so escaping can
        // never introduce a difference where the model made none.
        let replacements = zip(segments, corrections).map { segment, corrected in
            corrected == segment.text ? segment.raw : handler.escape(corrected, like: segment)
        }
        let output = try Reassembler.splice(text, segments: segments, replacements: replacements)
        guard DiacriticVerifier.documentMatches(original: text, corrected: output) else {
            throw PipelineError.verificationFailed(failedSegments: 0)
        }

        let changed = zip(segments, corrections).count { $0.text != $1 }
        return Corrected(text: output, segmentCount: segments.count, changedCount: changed)
    }

    private func fill(_ corrections: inout [String],
                      indices: [Int],
                      segments: [Segment],
                      cache: inout [String: String]) async throws {
        let subset = indices.map { segments[$0] }
        for batch in SegmentBatcher.batches(subset, maxChars: limits.maxBatchChars) {
            let items = batch.map { subset[$0].text }
            let prompt = PromptBuilder.build(items: items, systemOverride: promptOverride)

            let answer: String
            do {
                answer = try await provider.complete(prompt)
            } catch {
                throw PipelineError.providerFailed(String(describing: error))
            }

            var decoded: [String]
            do {
                decoded = try NumberedList.decode(answer, expectedCount: items.count)
            } catch {
                // A malformed list gets exactly one more attempt.
                let second: String
                do {
                    second = try await provider.complete(prompt)
                } catch {
                    throw PipelineError.providerFailed(String(describing: error))
                }
                do {
                    decoded = try NumberedList.decode(second, expectedCount: items.count)
                } catch {
                    throw PipelineError.providerFailed("odpověď modelu neodpovídá číslovanému seznamu")
                }
            }

            for (offset, positionInSubset) in batch.enumerated() {
                let target = indices[positionInSubset]
                corrections[target] = decoded[offset]
                cache[DiacriticFolding.fold(segments[target].text)] = decoded[offset]
            }
        }
    }
}

private extension Sequence {
    func count(where predicate: (Element) -> Bool) -> Int {
        reduce(0) { predicate($1) ? $0 + 1 : $0 }
    }
}
```

> `zip(...).count { ... }` používá to soukromé rozšíření nad `Sequence` — nech ho na konci souboru.

- [ ] **Step 4: Spusť test a ověř, že projde**

Run: `make test`
Expected: PASS — 100 testů celkem.

- [ ] **Step 5: Commit**

```bash
git add Sources/CzechatorCore/Pipeline.swift Sources/CzechatorCore/Config/Limits.swift \
        Tests/CzechatorCoreTests/PipelineTests.swift
git commit -m "feat: orchestrace pipeline s verifikací a cache oprav"
```

---

## Task 16: Konfigurace a její ukládání

**Files:**
- Create: `Sources/CzechatorCore/Config/Config.swift`
- Create: `Sources/CzechatorCore/Config/ConfigStore.swift`
- Test: `Tests/CzechatorCoreTests/ConfigStoreTests.swift`

**Interfaces:**
- Consumes: `SegmentationRules` (Task 3), `SecretRef` (Task 13), `Limits` (Task 15).
- Produces:
  - `enum ProfileKind: String, Sendable, Codable { case ollama, openaiCompat = "openai-compat" }`
  - `struct Profile: Sendable, Codable, Equatable { var kind: ProfileKind; var endpoint: URL; var model: String; var temperature: Double; var timeoutSeconds: Double; var apiKey: SecretRef? }`
  - `struct HotkeyBinding: Sendable, Codable, Equatable { var shortcut: String; var source: String; var sink: String }`
  - `struct FeatureFlags: Sendable, Codable, Equatable { var preview: Bool; var history: Bool; var historySize: Int }` + `.builtIn`
  - `struct PromptConfig: Sendable, Codable, Equatable { var override: String? }`
  - `struct Config: Sendable, Codable, Equatable` s `activeProfile`, `profiles: [String: Profile]`, `hotkeys: [HotkeyBinding]`, `limits`, `segmentation`, `features`, `prompt` + `Config.builtIn`
  - `struct ConfigStore: Sendable` s `ConfigStore.defaultURL()`, `init(url: URL)`, `func load() throws -> Config`, `func save(_ config: Config) throws`

- [ ] **Step 1: Napiš padající test**

`Tests/CzechatorCoreTests/ConfigStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import CzechatorCore

private func temporaryStore() -> (ConfigStore, URL) {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("czechator-test-\(UUID().uuidString)")
    let url = directory.appendingPathComponent("config.yaml")
    return (ConfigStore(url: url), url)
}

@Test func writesFullDefaultsOnFirstLoad() throws {
    let (store, url) = temporaryStore()
    let config = try store.load()

    #expect(config == .builtIn)
    #expect(FileManager.default.fileExists(atPath: url.path))

    let written = try String(contentsOf: url, encoding: .utf8)
    // The segmentation block must be materialized in full so it can be edited
    // without reading the source.
    #expect(written.contains("segmentation"))
    #expect(written.contains("skipValuesForKeys"))
    #expect(written.contains("cmd+ctrl+d"))
}

@Test func fillsMissingKeysFromDefaults() throws {
    let (store, url) = temporaryStore()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try """
    activeProfile: local
    profiles:
      local:
        kind: ollama
        endpoint: http://localhost:11434
        model: gemma3:4b
        temperature: 0
        timeoutSeconds: 30
    """.write(to: url, atomically: true, encoding: .utf8)

    let config = try store.load()
    #expect(config.profiles["local"]?.model == "gemma3:4b")
    #expect(config.limits == .builtIn)
    #expect(config.segmentation == .builtIn)
    #expect(config.features == .builtIn)
}

@Test func savePreservesUnknownKeys() throws {
    let (store, url) = temporaryStore()
    _ = try store.load()

    var text = try String(contentsOf: url, encoding: .utf8)
    text += "\nmojePoznamka: neco vlastniho\n"
    try text.write(to: url, atomically: true, encoding: .utf8)

    var config = try store.load()
    config.activeProfile = "openai"
    try store.save(config)

    let saved = try String(contentsOf: url, encoding: .utf8)
    #expect(saved.contains("mojePoznamka: neco vlastniho"))
    #expect(saved.contains("activeProfile: openai"))
}

@Test func defaultsPointAtTheExpectedLocation() {
    #expect(ConfigStore.defaultURL().path.hasSuffix(".config/czechator/config.yaml"))
}

@Test func defaultProfileIsLocalOllamaWithTemperatureZero() {
    let profile = Config.builtIn.profiles["local"]
    #expect(Config.builtIn.activeProfile == "local")
    #expect(profile?.kind == .ollama)
    #expect(profile?.temperature == 0)
    #expect(Config.builtIn.hotkeys.first?.shortcut == "cmd+ctrl+d")
    #expect(Config.builtIn.hotkeys.first?.source == "clipboard")
    #expect(Config.builtIn.hotkeys.first?.sink == "clipboard")
}
```

- [ ] **Step 2: Spusť test a ověř, že selže**

Run: `make test`
Expected: FAIL — `cannot find 'ConfigStore' in scope`.

- [ ] **Step 3: Napiš implementaci**

`Sources/CzechatorCore/Config/Config.swift`:

```swift
import Foundation

public enum ProfileKind: String, Sendable, Codable {
    case ollama
    case openaiCompat = "openai-compat"
}

public struct Profile: Sendable, Codable, Equatable {
    public var kind: ProfileKind
    public var endpoint: URL
    public var model: String
    public var temperature: Double
    public var timeoutSeconds: Double
    /// Never the key itself — only a reference resolved lazily. See SecretRef.
    public var apiKey: SecretRef?

    public init(kind: ProfileKind, endpoint: URL, model: String,
                temperature: Double, timeoutSeconds: Double, apiKey: SecretRef? = nil) {
        self.kind = kind
        self.endpoint = endpoint
        self.model = model
        self.temperature = temperature
        self.timeoutSeconds = timeoutSeconds
        self.apiKey = apiKey
    }
}

public struct HotkeyBinding: Sendable, Codable, Equatable {
    public var shortcut: String
    public var source: String
    public var sink: String

    public init(shortcut: String, source: String, sink: String) {
        self.shortcut = shortcut
        self.source = source
        self.sink = sink
    }
}

public struct FeatureFlags: Sendable, Codable, Equatable {
    public var preview: Bool
    public var history: Bool
    public var historySize: Int

    public static let builtIn = FeatureFlags(preview: false, history: true, historySize: 20)

    public init(preview: Bool, history: Bool, historySize: Int) {
        self.preview = preview
        self.history = history
        self.historySize = historySize
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = FeatureFlags.builtIn
        preview = try container.decodeIfPresent(Bool.self, forKey: .preview) ?? defaults.preview
        history = try container.decodeIfPresent(Bool.self, forKey: .history) ?? defaults.history
        historySize = try container.decodeIfPresent(Int.self, forKey: .historySize)
            ?? defaults.historySize
    }
}

public struct PromptConfig: Sendable, Codable, Equatable {
    public var override: String?

    public static let builtIn = PromptConfig(override: nil)

    public init(override: String?) { self.override = override }
}

public struct Config: Sendable, Codable, Equatable {
    public var activeProfile: String
    public var profiles: [String: Profile]
    public var hotkeys: [HotkeyBinding]
    public var limits: Limits
    public var segmentation: SegmentationRules
    public var features: FeatureFlags
    public var prompt: PromptConfig

    public static let builtIn = Config(
        activeProfile: "local",
        profiles: [
            "local": Profile(kind: .ollama,
                             endpoint: URL(string: "http://localhost:11434")!,
                             model: "qwen3:4b-instruct",
                             temperature: 0,
                             timeoutSeconds: 30),
            "openai": Profile(kind: .openaiCompat,
                              endpoint: URL(string: "https://api.openai.com/v1")!,
                              model: "gpt-4o-mini",
                              temperature: 0,
                              timeoutSeconds: 30,
                              apiKey: .keychain(account: "czechator-openai")),
        ],
        hotkeys: [HotkeyBinding(shortcut: "cmd+ctrl+d", source: "clipboard", sink: "clipboard")],
        limits: .builtIn,
        segmentation: .builtIn,
        features: .builtIn,
        prompt: .builtIn
    )

    public init(activeProfile: String, profiles: [String: Profile], hotkeys: [HotkeyBinding],
                limits: Limits, segmentation: SegmentationRules,
                features: FeatureFlags, prompt: PromptConfig) {
        self.activeProfile = activeProfile
        self.profiles = profiles
        self.hotkeys = hotkeys
        self.limits = limits
        self.segmentation = segmentation
        self.features = features
        self.prompt = prompt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Config.builtIn
        activeProfile = try container.decodeIfPresent(String.self, forKey: .activeProfile)
            ?? defaults.activeProfile
        profiles = try container.decodeIfPresent([String: Profile].self, forKey: .profiles)
            ?? defaults.profiles
        hotkeys = try container.decodeIfPresent([HotkeyBinding].self, forKey: .hotkeys)
            ?? defaults.hotkeys
        limits = try container.decodeIfPresent(Limits.self, forKey: .limits) ?? defaults.limits
        segmentation = try container.decodeIfPresent(SegmentationRules.self, forKey: .segmentation)
            ?? defaults.segmentation
        features = try container.decodeIfPresent(FeatureFlags.self, forKey: .features)
            ?? defaults.features
        prompt = try container.decodeIfPresent(PromptConfig.self, forKey: .prompt) ?? defaults.prompt
    }

    /// The profile the tool will actually use, falling back to the first one
    /// defined if `activeProfile` names something that does not exist.
    public var active: Profile? {
        profiles[activeProfile] ?? profiles.sorted { $0.key < $1.key }.first?.value
    }
}
```

`Sources/CzechatorCore/Config/ConfigStore.swift`:

```swift
import Foundation
import Yams

public struct ConfigStore: Sendable {

    private let url: URL

    public init(url: URL) { self.url = url }

    public static func defaultURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".config")
            .appendingPathComponent("czechator")
            .appendingPathComponent("config.yaml")
    }

    /// Materializes the full defaults on first run so every rule is visible and
    /// editable without reading the source.
    public func load() throws -> Config {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            try write(node: try encodeNode(Config.builtIn))
            return .builtIn
        }
        return try YAMLDecoder().decode(Config.self, from: text)
    }

    /// Writes the config back while keeping any keys the tool does not know
    /// about — hand-written notes survive the settings window.
    public func save(_ config: Config) throws {
        let encoded = try encodeNode(config)
        if let existing = try? String(contentsOf: url, encoding: .utf8),
           let base = try Yams.compose(yaml: existing) {
            try write(node: Self.merge(into: base, from: encoded))
        } else {
            try write(node: encoded)
        }
    }

    private func encodeNode(_ config: Config) throws -> Node {
        let text = try YAMLEncoder().encode(config)
        guard let node = try Yams.compose(yaml: text) else {
            throw SecretError.notFound("config serialization")
        }
        return node
    }

    private func write(node: Node) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let text = try Yams.serialize(node: node)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Recursive mapping merge: known keys are overwritten, unknown ones kept.
    /// Sequences and scalars are replaced wholesale.
    static func merge(into base: Node, from new: Node) -> Node {
        guard case .mapping(let baseMapping) = base,
              case .mapping(let newMapping) = new else {
            return new
        }
        var result = baseMapping
        for (key, value) in newMapping {
            if let existing = result[key] {
                result[key] = merge(into: existing, from: value)
            } else {
                result[key] = value
            }
        }
        return .mapping(result)
    }
}
```

- [ ] **Step 4: Spusť test a ověř, že projde**

Run: `make test`
Expected: PASS — 105 testů celkem.

- [ ] **Step 5: Commit**

```bash
git add Sources/CzechatorCore/Config/Config.swift \
        Sources/CzechatorCore/Config/ConfigStore.swift \
        Tests/CzechatorCoreTests/ConfigStoreTests.swift
git commit -m "feat: konfigurace v YAML se zachováním neznámých klíčů"
```

---
## Task 17: CLI — ladicí příkaz `segments`

**Files:**
- Delete: `Sources/czechator/main.swift` (zástupný soubor z Tasku 1)
- Create: `Sources/czechator/Czechator.swift`
- Create: `Sources/czechator/CLIEnvironment.swift`
- Create: `Sources/czechator/SegmentsCommand.swift`
- Create: `Sources/CzechatorCore/Handlers/SegmentationDebug.swift`
- Test: `Tests/CzechatorCoreTests/SegmentationDebugTests.swift`

**Interfaces:**
- Consumes: `Config`, `ConfigStore` (Task 16), `FormatRegistry` (Task 9), `SegmentationRules` (Task 3), poskytovatelé (Tasky 12–13).
- Produces:
  - `struct ExcludedSpan: Sendable, Equatable { let pattern: String; let text: String; let offset: Int }`
  - `SegmentationDebug.excludedSpans(in text: String, rules: SegmentationRules, formatID: String) throws -> [ExcludedSpan]`
  - `SegmentationDebug.activeRuleSummary(rules: SegmentationRules, formatID: String) -> [String]`
  - CLI kořen `Czechator` (`AsyncParsableCommand`), podpříkaz `segments`, `CLIEnvironment.load(configPath:profile:)`

**Pozor na `@main`:** soubor se vstupním bodem **nesmí** být pojmenovaný `main.swift` — s top-level kódem se atribut `@main` nepřeloží. Proto se zástupný `main.swift` z Tasku 1 maže a vzniká `Czechator.swift`.

**Rozsah `--show-skipped`:** vypisuje spany vyloučené regulárními výrazy (včetně toho, který vzor je vyloučil) a přehled pravidel, která jsou pro daný formát aktivní. Neuvádí uzel po uzlu, proč konkrétní element nebo klíč nedal segment — na to stačí porovnat výpis segmentů s přehledem pravidel.

- [ ] **Step 1: Napiš padající test**

`Tests/CzechatorCoreTests/SegmentationDebugTests.swift`:

```swift
import Testing
@testable import CzechatorCore

@Test func reportsWhichPatternExcludedWhichSpan() throws {
    let text = "napis na petr@example.com nebo https://example.com/x"
    let spans = try SegmentationDebug.excludedSpans(in: text, rules: .builtIn, formatID: "plain")

    #expect(spans.map(\.text) == ["petr@example.com", "https://example.com/x"])
    #expect(spans[0].pattern == #"\S+@\S+\.\S+"#)
    #expect(spans[1].pattern == #"https?://\S+"#)
    #expect(spans[0].offset == 10)
}

@Test func includesFormatSpecificPatternsForPlainText() throws {
    let spans = try SegmentationDebug.excludedSpans(in: "pouzij `kod` tady",
                                                    rules: .builtIn, formatID: "plain")
    #expect(spans.map(\.text) == ["`kod`"])
}

@Test func doesNotApplyPlainPatternsToJSON() throws {
    let spans = try SegmentationDebug.excludedSpans(in: #"{"a": "pouzij `kod` tady"}"#,
                                                    rules: .builtIn, formatID: "json")
    #expect(spans.isEmpty)
}

@Test func summarisesTheRulesInEffect() {
    let json = SegmentationDebug.activeRuleSummary(rules: .builtIn, formatID: "json")
    #expect(json.contains { $0.contains("skipKeys") })
    #expect(json.contains { $0.contains("skipValuesForKeys") })

    let html = SegmentationDebug.activeRuleSummary(rules: .builtIn, formatID: "html")
    #expect(html.contains { $0.contains("script") })
}
```

- [ ] **Step 2: Spusť test a ověř, že selže**

Run: `make test`
Expected: FAIL — `cannot find 'SegmentationDebug' in scope`.

- [ ] **Step 3: Napiš implementaci**

`Sources/CzechatorCore/Handlers/SegmentationDebug.swift`:

```swift
import Foundation

public struct ExcludedSpan: Sendable, Equatable {
    public let pattern: String
    public let text: String
    public let offset: Int

    public init(pattern: String, text: String, offset: Int) {
        self.pattern = pattern
        self.text = text
        self.offset = offset
    }
}

/// Support for `czechator segments`. Tuning the skip rules is an empirical
/// loop, so it has to be possible to see what a rule actually removed without
/// rebuilding anything.
public enum SegmentationDebug {

    public static func patterns(rules: SegmentationRules, formatID: String) -> [String] {
        rules.common.skipPatterns + (formatID == PlainTextHandler.id ? rules.plain.skipPatterns : [])
    }

    public static func excludedSpans(in text: String,
                                     rules: SegmentationRules,
                                     formatID: String) throws -> [ExcludedSpan] {
        var spans: [ExcludedSpan] = []
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        for pattern in patterns(rules: rules, formatID: formatID) {
            let regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
            for match in regex.matches(in: text, options: [], range: full) {
                guard let range = Range(match.range, in: text), !range.isEmpty else { continue }
                spans.append(ExcludedSpan(
                    pattern: pattern,
                    text: String(text[range]),
                    offset: text.distance(from: text.startIndex, to: range.lowerBound)))
            }
        }
        return spans.sorted { $0.offset < $1.offset }
    }

    public static func activeRuleSummary(rules: SegmentationRules, formatID: String) -> [String] {
        var lines = [
            "common.minLength = \(rules.common.minLength)",
            "common.requireLetters = \(rules.common.requireLetters)",
            "common.skipPatterns = \(rules.common.skipPatterns)",
        ]
        switch formatID {
        case JSONHandler.id:
            lines.append("json.skipKeys = \(rules.json.skipKeys)")
            lines.append("json.skipValuesForKeys = \(rules.json.skipValuesForKeys)")
        case HTMLHandler.id:
            lines.append("html.skipElements = \(rules.html.skipElements)")
            lines.append("html.skipAttributes = \(rules.html.skipAttributes)")
            lines.append("html.skipComments = \(rules.html.skipComments)")
        case XMLHandler.id:
            lines.append("xml.skipElements = \(rules.xml.skipElements)")
            lines.append("xml.skipAttributes = \(rules.xml.skipAttributes)")
            lines.append("xml.skipComments = \(rules.xml.skipComments)")
            lines.append("xml.skipProcessingInstructions = \(rules.xml.skipProcessingInstructions)")
            lines.append("xml.skipCDATA = \(rules.xml.skipCDATA)")
        default:
            lines.append("plain.skipPatterns = \(rules.plain.skipPatterns)")
        }
        return lines
    }
}
```

`Sources/czechator/Czechator.swift`:

```swift
import ArgumentParser

@main
struct Czechator: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "czechator",
        abstract: "Doplní do textu českou diakritiku, aniž by sáhla na strukturu.",
        subcommands: [FixCommand.self, SegmentsCommand.self],
        defaultSubcommand: FixCommand.self
    )
}
```

> `FixCommand` vznikne až v Tasku 18. Do té doby uveď v `subcommands` jen `SegmentsCommand.self` a vynech `defaultSubcommand`; v Tasku 18 se řádky doplní.

`Sources/czechator/CLIEnvironment.swift`:

```swift
import ArgumentParser
import CzechatorCore
import Foundation

struct CLIEnvironment {
    let config: Config
    let registry: FormatRegistry

    static func load(configPath: String?, profileName: String?) throws -> CLIEnvironment {
        let url = configPath.map { URL(fileURLWithPath: $0) } ?? ConfigStore.defaultURL()
        var config = try ConfigStore(url: url).load()
        if let profileName { config.activeProfile = profileName }
        return CLIEnvironment(config: config,
                              registry: try FormatRegistry(rules: config.segmentation))
    }

    /// The CLI resolves secrets from the environment — Keychain lives in the app.
    func makeProvider() throws -> any LLMProvider {
        guard let profile = config.active else {
            throw ValidationError("konfigurace neobsahuje žádný profil")
        }
        let client = URLSessionHTTPClient()
        let key = try profile.apiKey.map { try EnvironmentSecretResolver().resolve($0) }

        switch profile.kind {
        case .ollama:
            return OllamaProvider(endpoint: profile.endpoint,
                                  model: profile.model,
                                  temperature: profile.temperature,
                                  timeout: profile.timeoutSeconds,
                                  client: client)
        case .openaiCompat:
            return OpenAICompatProvider(endpoint: profile.endpoint,
                                        model: profile.model,
                                        temperature: profile.temperature,
                                        timeout: profile.timeoutSeconds,
                                        apiKey: key,
                                        client: client)
        }
    }

    static func readInput(path: String) throws -> String {
        if path == "-" {
            var data = Data()
            while let line = readLine(strippingNewline: false) { data.append(Data(line.utf8)) }
            return String(decoding: data, as: UTF8.self)
        }
        return try String(contentsOfFile: path, encoding: .utf8)
    }
}
```

`Sources/czechator/SegmentsCommand.swift`:

```swift
import ArgumentParser
import CzechatorCore

struct SegmentsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "segments",
        abstract: "Vypíše segmenty, které by šly modelu. Model se nevolá."
    )

    @Argument(help: "Cesta k souboru, nebo - pro standardní vstup.")
    var path: String = "-"

    @Option(name: .long, help: "Vynutí formát: json, xml, html, plain.")
    var format: String?

    @Option(name: .long, help: "Cesta ke konfiguraci.")
    var config: String?

    @Flag(name: .long, help: "Vypíše i vyloučené spany a aktivní pravidla.")
    var showSkipped = false

    func run() throws {
        let environment = try CLIEnvironment.load(configPath: config, profileName: nil)
        let text = try CLIEnvironment.readInput(path: path)
        let input = ClipboardInput(text: text)

        let formatID: String
        let handler: any FormatHandler
        if let format {
            guard let forced = environment.registry.handler(id: format) else {
                throw ValidationError("neznámý formát: \(format)")
            }
            formatID = format
            handler = forced
        } else {
            let selected = environment.registry.select(input)
            formatID = selected.id
            handler = selected.handler
        }

        print("formát: \(formatID)")
        let segments = try handler.segments(in: text)
        print("segmentů: \(segments.count)")
        for (index, segment) in segments.enumerated() {
            let offset = text.distance(from: text.startIndex, to: segment.range.lowerBound)
            let length = text.distance(from: segment.range.lowerBound, to: segment.range.upperBound)
            print("\(index + 1). [\(offset)+\(length)] \(segment.kind.rawValue): \(segment.text)")
        }

        guard showSkipped else { return }

        print("\nvyloučené spany:")
        let spans = try SegmentationDebug.excludedSpans(in: text,
                                                        rules: environment.config.segmentation,
                                                        formatID: formatID)
        if spans.isEmpty { print("  (žádné)") }
        for span in spans {
            print("  [\(span.offset)] \(span.text)   ← \(span.pattern)")
        }

        print("\naktivní pravidla:")
        for line in SegmentationDebug.activeRuleSummary(rules: environment.config.segmentation,
                                                        formatID: formatID) {
            print("  \(line)")
        }
    }
}
```

- [ ] **Step 4: Spusť testy a ručně ověř příkaz**

Run: `make test`
Expected: PASS — 109 testů celkem.

Run:
```bash
printf '{"id":"x","popis":"Prilis zlutoucky kun na https://example.com"}' \
  | swift run czechator segments - --show-skipped
```
Expected: `formát: json`, jeden segment `Prilis zlutoucky kun na`, ve vyloučených spanech URL s uvedeným vzorem `https?://\S+`, a v aktivních pravidlech `json.skipValuesForKeys`.

- [ ] **Step 5: Commit**

```bash
git rm Sources/czechator/main.swift
git add Sources/czechator Sources/CzechatorCore/Handlers/SegmentationDebug.swift \
        Tests/CzechatorCoreTests/SegmentationDebugTests.swift
git commit -m "feat: CLI a ladicí příkaz segments"
```

---

## Task 18: CLI — příkaz `fix`

**Files:**
- Create: `Sources/czechator/FixCommand.swift`
- Modify: `Sources/czechator/Czechator.swift` (doplnit `FixCommand` do `subcommands` a jako `defaultSubcommand`)

**Interfaces:**
- Consumes: `CLIEnvironment` (Task 17), `Pipeline`, `PipelineError` (Task 15).
- Produces: podpříkaz `fix`.

- [ ] **Step 1: Napiš implementaci**

Tento task nemá jednotkový test — veškerá logika už je pokrytá v `PipelineTests`. `FixCommand` je tenká slupka nad `Pipeline` a ověřuje se ručně proti živé Ollamě.

`Sources/czechator/FixCommand.swift`:

```swift
import ArgumentParser
import CzechatorCore
import Foundation

struct FixCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fix",
        abstract: "Doplní českou diakritiku a výsledek vypíše na standardní výstup."
    )

    @Argument(help: "Cesta k souboru, nebo - pro standardní vstup.")
    var path: String = "-"

    @Option(name: .long, help: "Název profilu z konfigurace.")
    var profile: String?

    @Option(name: .long, help: "Cesta ke konfiguraci.")
    var config: String?

    func run() async throws {
        let environment = try CLIEnvironment.load(configPath: config, profileName: profile)
        let text = try CLIEnvironment.readInput(path: path)

        let pipeline = Pipeline(registry: environment.registry,
                                provider: try environment.makeProvider(),
                                limits: environment.config.limits,
                                promptOverride: environment.config.prompt.override)
        do {
            let result = try await pipeline.run(ClipboardInput(text: text))
            print(result.correctedText, terminator: "")
        } catch let error as PipelineError {
            throw CleanExit.message(describe(error))
        }
    }

    /// Errors go to the user in Czech; the exit code stays non-zero so the
    /// command composes in shell pipelines.
    private func describe(_ error: PipelineError) -> String {
        switch error {
        case .noText:
            return "Na vstupu není žádný text."
        case .inputTooLarge(let bytes, let limit):
            return "Vstup má \(bytes) B, limit je \(limit) B."
        case .providerFailed(let detail):
            return "Model neodpověděl použitelně: \(detail)"
        case .verificationFailed(let count):
            return "Výsledek neprošel kontrolou (\(count) vadných segmentů). Vstup zůstal beze změny."
        }
    }
}
```

> `CleanExit.message` končí s kódem 0. Pro nenulový kód použij `throw ExitCode.failure` po vypsání hlášky na `FileHandle.standardError` — zvol tuto variantu, aby `czechator fix` v rouře selhal viditelně.

V `Sources/czechator/Czechator.swift` uveď:

```swift
        subcommands: [FixCommand.self, SegmentsCommand.self],
        defaultSubcommand: FixCommand.self
```

- [ ] **Step 2: Ověř, že se vše přeloží**

Run: `make build`
Expected: `Build complete!` bez varování o nedosažitelném kódu.

- [ ] **Step 3: Spusť testy**

Run: `make test`
Expected: PASS — 109 testů, beze změny oproti Tasku 17.

- [ ] **Step 4: Ručně ověř proti živé Ollamě**

Předpoklad: běží `ollama serve` a je stažený `qwen3:4b-instruct`.

Run:
```bash
echo 'Prilis zlutoucky kun upel dabelske ody.' | swift run czechator fix -
```
Expected: `Příliš žluťoučký kůň úpěl ďábelské ódy.`

Run:
```bash
printf '{"popis":"Vcera jsem koupil novy pocitac.","id":"abc"}' | swift run czechator fix -
```
Expected: `{"popis":"Včera jsem koupil nový počítač.","id":"abc"}` — uvozovky, pořadí klíčů i absence mezer beze změny.

- [ ] **Step 5: Commit**

```bash
git add Sources/czechator
git commit -m "feat: CLI příkaz fix"
```

---

## Task 19: Registrace globální zkratky

**Files:**
- Create: `Sources/CzechatorApp/HotKeyManager.swift`
- Create: `Sources/CzechatorCore/IO/ShortcutSpec.swift`
- Test: `Tests/CzechatorCoreTests/ShortcutSpecTests.swift`

**Interfaces:**
- Consumes: nic.
- Produces:
  - `struct ShortcutSpec: Sendable, Equatable { let modifiers: Set<ShortcutModifier>; let key: String }`
  - `enum ShortcutModifier: String, Sendable, CaseIterable { case cmd, ctrl, alt, shift }`
  - `enum ShortcutParseError: Error, Equatable { case empty, unknownToken(String), noKey, multipleKeys }`
  - `ShortcutSpec.parse(_ text: String) throws -> ShortcutSpec`
  - `ShortcutSpec.isCommonSystemShortcut: Bool`
  - `final class HotKeyManager` (macOS) s `init()`, `func register(_ spec: ShortcutSpec, handler: @escaping @Sendable () -> Void) throws`, `func unregisterAll()`, `enum HotKeyError: Error { case unsupportedKey(String), registrationFailed(OSStatus) }`

**Proč je parsování v jádru:** `ShortcutSpec` je čistě textová záležitost a testuje se headless. Do `CzechatorApp` patří jen převod na Carbon kód a samotná registrace.

- [ ] **Step 1: Napiš padající test**

`Tests/CzechatorCoreTests/ShortcutSpecTests.swift`:

```swift
import Testing
@testable import CzechatorCore

@Test func parsesTheDefaultShortcut() throws {
    let spec = try ShortcutSpec.parse("cmd+ctrl+d")
    #expect(spec.modifiers == [.cmd, .ctrl])
    #expect(spec.key == "d")
}

@Test func isCaseAndWhitespaceInsensitive() throws {
    #expect(try ShortcutSpec.parse("  CMD + Ctrl + D ") == (try ShortcutSpec.parse("cmd+ctrl+d")))
}

@Test func acceptsAllModifierNames() throws {
    let spec = try ShortcutSpec.parse("cmd+ctrl+alt+shift+k")
    #expect(spec.modifiers == [.cmd, .ctrl, .alt, .shift])
    #expect(spec.key == "k")
}

@Test func rejectsMalformedInput() {
    #expect(throws: ShortcutParseError.empty) { try ShortcutSpec.parse("   ") }
    #expect(throws: ShortcutParseError.noKey) { try ShortcutSpec.parse("cmd+ctrl") }
    #expect(throws: ShortcutParseError.multipleKeys) { try ShortcutSpec.parse("cmd+d+k") }
    #expect(throws: ShortcutParseError.unknownToken("hyper")) {
        try ShortcutSpec.parse("hyper+d")
    }
}

@Test func flagsShortcutsThatCollideWithCommonSystemOnes() throws {
    #expect(try ShortcutSpec.parse("cmd+b").isCommonSystemShortcut)
    #expect(try ShortcutSpec.parse("cmd+c").isCommonSystemShortcut)
    #expect(!(try ShortcutSpec.parse("cmd+ctrl+d").isCommonSystemShortcut))
}
```

- [ ] **Step 2: Spusť test a ověř, že selže**

Run: `make test`
Expected: FAIL — `cannot find 'ShortcutSpec' in scope`.

- [ ] **Step 3: Napiš implementaci**

`Sources/CzechatorCore/IO/ShortcutSpec.swift`:

```swift
public enum ShortcutModifier: String, Sendable, CaseIterable {
    case cmd, ctrl, alt, shift
}

public enum ShortcutParseError: Error, Equatable {
    case empty
    case unknownToken(String)
    case noKey
    case multipleKeys
}

public struct ShortcutSpec: Sendable, Equatable {
    public let modifiers: Set<ShortcutModifier>
    public let key: String

    public init(modifiers: Set<ShortcutModifier>, key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    public static func parse(_ text: String) throws -> ShortcutSpec {
        let tokens = text.lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { throw ShortcutParseError.empty }

        var modifiers: Set<ShortcutModifier> = []
        var keys: [String] = []
        for token in tokens {
            switch token {
            case "cmd", "command", "⌘": modifiers.insert(.cmd)
            case "ctrl", "control", "⌃": modifiers.insert(.ctrl)
            case "alt", "option", "opt", "⌥": modifiers.insert(.alt)
            case "shift", "⇧": modifiers.insert(.shift)
            default:
                guard token.count == 1 || token.first == "f" else {
                    throw ShortcutParseError.unknownToken(token)
                }
                keys.append(token)
            }
        }
        guard !keys.isEmpty else { throw ShortcutParseError.noKey }
        guard keys.count == 1 else { throw ShortcutParseError.multipleKeys }
        return ShortcutSpec(modifiers: modifiers, key: keys[0])
    }

    /// Cmd plus a single letter is almost always already taken by every app —
    /// Cmd+B is bold everywhere. The settings window warns about these.
    public var isCommonSystemShortcut: Bool {
        modifiers == [.cmd] && key.count == 1 && key.first?.isLetter == true
    }
}
```

> `trimmingCharacters(in:)` vyžaduje `import Foundation` — přidej ho na začátek souboru.

`Sources/CzechatorApp/HotKeyManager.swift`:

```swift
import AppKit
import Carbon.HIToolbox
import CzechatorCore

/// Registers a system-wide hotkey through Carbon's `RegisterEventHotKey`.
///
/// Deliberately not `CGEventTap`: Carbon registration needs no Accessibility
/// permission, so the app works on first launch without any TCC dialog.
final class HotKeyManager {

    enum HotKeyError: Error {
        case unsupportedKey(String)
        case registrationFailed(OSStatus)
    }

    private var reference: EventHotKeyRef?
    private var handlerReference: EventHandlerRef?
    private var action: (@Sendable () -> Void)?

    private static let letterCodes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
        "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
        "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
        "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
        "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    ]

    func register(_ spec: ShortcutSpec, handler: @escaping @Sendable () -> Void) throws {
        unregisterAll()
        guard let code = Self.letterCodes[spec.key] else {
            throw HotKeyError.unsupportedKey(spec.key)
        }
        action = handler

        var carbonModifiers: UInt32 = 0
        if spec.modifiers.contains(.cmd) { carbonModifiers |= UInt32(cmdKey) }
        if spec.modifiers.contains(.ctrl) { carbonModifiers |= UInt32(controlKey) }
        if spec.modifiers.contains(.alt) { carbonModifiers |= UInt32(optionKey) }
        if spec.modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.action?()
            return noErr
        }
        let status = InstallEventHandler(GetApplicationEventTarget(),
                                         callback,
                                         1,
                                         &eventType,
                                         Unmanaged.passUnretained(self).toOpaque(),
                                         &handlerReference)
        guard status == noErr else { throw HotKeyError.registrationFailed(status) }

        let identifier = EventHotKeyID(signature: OSType(0x435A_4348), id: 1)  // "CZCH"
        let registration = RegisterEventHotKey(UInt32(code),
                                               carbonModifiers,
                                               identifier,
                                               GetApplicationEventTarget(),
                                               0,
                                               &reference)
        guard registration == noErr else { throw HotKeyError.registrationFailed(registration) }
    }

    func unregisterAll() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        if let handlerReference { RemoveEventHandler(handlerReference) }
        handlerReference = nil
        action = nil
    }

    deinit { unregisterAll() }
}
```

- [ ] **Step 4: Spusť testy a ověř překlad aplikace**

Run: `make test`
Expected: PASS — 114 testů celkem.

Run: `make build`
Expected: `Build complete!` — cíl `CzechatorApp` se přeloží.

- [ ] **Step 5: Commit**

```bash
git add Sources/CzechatorCore/IO/ShortcutSpec.swift \
        Sources/CzechatorApp/HotKeyManager.swift \
        Tests/CzechatorCoreTests/ShortcutSpecTests.swift
git commit -m "feat: parsování a registrace globální zkratky"
```

---
## Task 20: Čtení a zápis schránky

**Files:**
- Create: `Sources/CzechatorCore/IO/InputSource.swift`
- Create: `Sources/CzechatorCore/IO/OutputSink.swift`
- Create: `Sources/CzechatorCore/IO/ClipboardTypes.swift`
- Create: `Sources/CzechatorApp/PasteboardSource.swift`
- Create: `Sources/CzechatorApp/PasteboardSink.swift`
- Test: `Tests/CzechatorCoreTests/ClipboardTypesTests.swift`

**Interfaces:**
- Consumes: `ClipboardInput` (Task 4), `PipelineResult` (Task 15).
- Produces:
  - `protocol InputSource: Sendable { func read() throws -> ClipboardInput }`
  - `protocol OutputSink: Sendable { func write(_ result: PipelineResult) throws }`
  - `enum ClipboardError: Error, Equatable { case empty, noTextRepresentation(availableTypes: [String]), unsupportedFormat(String) }`
  - `enum ClipboardTypeChoice: Sendable, Equatable { case html, plain, unsupported(String), none }`
  - `ClipboardTypes.choose(_ types: [String]) -> ClipboardTypeChoice`
  - `struct PasteboardSource: InputSource`, `struct PasteboardSink: OutputSink` (obojí macOS)

**Proč se rozhodovací pravidlo drží v jádru:** `NSPasteboard` se v testech rozumně nesimuluje, ale samotné pravidlo „co si ze seznamu UTI vybrat" je čistá funkce nad polem řetězců. V jádru je testovatelné, ve slupce zbývá jen pár řádků lepidla.

**Klíčová past při zápisu:** `clearContents()` maže **všechny** reprezentace. Pokud se zapíše jen plain text, vložení do Wordu přijde o formátování. U HTML se proto zapisuje HTML **i** plain varianta.

- [ ] **Step 1: Napiš padající test**

`Tests/CzechatorCoreTests/ClipboardTypesTests.swift`:

```swift
import Testing
@testable import CzechatorCore

@Test func prefersHTMLWhenAvailable() {
    #expect(ClipboardTypes.choose(["public.html", "public.utf8-plain-text"]) == .html)
}

@Test func fallsBackToPlainText() {
    #expect(ClipboardTypes.choose(["public.utf8-plain-text"]) == .plain)
    #expect(ClipboardTypes.choose(["public.utf8-plain-text", "public.file-url"]) == .plain)
}

@Test func reportsRTFOnlyClipboardsAsUnsupported() {
    #expect(ClipboardTypes.choose(["public.rtf"]) == .unsupported("RTF"))
}

@Test func prefersHTMLEvenWhenRTFIsPresent() {
    #expect(ClipboardTypes.choose(["public.rtf", "public.html", "public.utf8-plain-text"]) == .html)
}

@Test func reportsImagesAndFilesAsHavingNoText() {
    #expect(ClipboardTypes.choose(["public.png"]) == .none)
    #expect(ClipboardTypes.choose([]) == .none)
}
```

- [ ] **Step 2: Spusť test a ověř, že selže**

Run: `make test`
Expected: FAIL — `cannot find 'ClipboardTypes' in scope`.

- [ ] **Step 3: Napiš implementaci**

`Sources/CzechatorCore/IO/ClipboardTypes.swift`:

```swift
public enum ClipboardTypeChoice: Sendable, Equatable {
    case html
    case plain
    case unsupported(String)
    case none
}

/// NSPasteboard holds one item in several representations at once, each under
/// its own UTI. This picks the richest one the tool can actually rewrite.
public enum ClipboardTypes {

    public static func choose(_ types: [String]) -> ClipboardTypeChoice {
        if types.contains("public.html") { return .html }
        if types.contains("public.utf8-plain-text") || types.contains("public.plain-text") {
            return .plain
        }
        if types.contains("public.rtf") { return .unsupported("RTF") }
        return .none
    }
}
```

`Sources/CzechatorCore/IO/InputSource.swift`:

```swift
public enum ClipboardError: Error, Equatable {
    case empty
    case noTextRepresentation(availableTypes: [String])
    case unsupportedFormat(String)
}

/// Where the text to correct comes from. MVP ships only a clipboard source;
/// v1.1 adds a selection source that fakes Cmd+C into the frontmost app.
public protocol InputSource: Sendable {
    func read() throws -> ClipboardInput
}
```

`Sources/CzechatorCore/IO/OutputSink.swift`:

```swift
/// Where the corrected text goes. MVP writes back to the clipboard; v1.1 adds
/// paste-in-place.
public protocol OutputSink: Sendable {
    func write(_ result: PipelineResult) throws
}
```

`Sources/CzechatorApp/PasteboardSource.swift`:

```swift
import AppKit
import CzechatorCore

struct PasteboardSource: InputSource {

    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    func read() throws -> ClipboardInput {
        let types = pasteboard.types?.map(\.rawValue) ?? []
        switch ClipboardTypes.choose(types) {
        case .html:
            guard let html = pasteboard.string(forType: .html) else {
                throw ClipboardError.noTextRepresentation(availableTypes: types)
            }
            return ClipboardInput(text: html,
                                  uti: "public.html",
                                  plainText: pasteboard.string(forType: .string))
        case .plain:
            guard let plain = pasteboard.string(forType: .string) else {
                throw ClipboardError.noTextRepresentation(availableTypes: types)
            }
            return ClipboardInput(text: plain, uti: "public.utf8-plain-text", plainText: nil)
        case .unsupported(let name):
            throw ClipboardError.unsupportedFormat(name)
        case .none:
            throw ClipboardError.noTextRepresentation(availableTypes: types)
        }
    }
}
```

`Sources/CzechatorApp/PasteboardSink.swift`:

```swift
import AppKit
import CzechatorCore

struct PasteboardSink: OutputSink {

    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    func write(_ result: PipelineResult) throws {
        pasteboard.clearContents()
        if result.formatID == HTMLHandler.id {
            pasteboard.setString(result.correctedText, forType: .html)
            if let plain = result.correctedPlainText {
                pasteboard.setString(plain, forType: .string)
            }
        } else {
            pasteboard.setString(result.correctedText, forType: .string)
        }
    }
}
```

- [ ] **Step 4: Spusť testy a ověř překlad**

Run: `make test`
Expected: PASS — 119 testů celkem.

Run: `make build`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Sources/CzechatorCore/IO Sources/CzechatorApp/PasteboardSource.swift \
        Sources/CzechatorApp/PasteboardSink.swift \
        Tests/CzechatorCoreTests/ClipboardTypesTests.swift
git commit -m "feat: čtení a zápis schránky se zachováním bohatých reprezentací"
```

---

## Task 21: Aplikace v menu baru, historie a chybové stavy

**Files:**
- Create: `Sources/CzechatorApp/AppModel.swift`
- Create: `Sources/CzechatorApp/CzechatorApp.swift`
- Create: `Sources/CzechatorApp/NotificationCenterBridge.swift`
- Create: `Sources/CzechatorCore/ErrorMessages.swift`
- Test: `Tests/CzechatorCoreTests/ErrorMessagesTests.swift`

**Interfaces:**
- Consumes: `Pipeline`, `PipelineError` (Task 15), `ConfigStore`, `Config` (Task 16), `HotKeyManager`, `ShortcutSpec` (Task 19), `PasteboardSource`, `PasteboardSink`, `ClipboardError` (Task 20).
- Produces:
  - `ErrorMessages.describe(_ error: any Error) -> String` — jediné místo, kde vznikají české hlášky.
  - `@MainActor final class AppModel: ObservableObject` s `@Published var state: RunState`, `@Published var history: [HistoryEntry]`, `func start()`, `func run()`, `func acknowledgeError()`, `func restore(_ entry: HistoryEntry)`
  - `enum RunState: Equatable { case idle, working, failed(String) }`
  - `struct HistoryEntry: Identifiable, Equatable` s `id: UUID`, `preview: String`, `originalText: String`, `succeeded: Bool`, `detail: String?`

**Pravidlo chybového stavu:** chyba nikdy nepřežije jedno kliknutí. Odznak zmizí při otevření menu, při kliknutí na notifikaci i po dalším úspěšném průchodu. Detail zůstává v historii.

**Pravidlo schránky:** `PasteboardSink.write` se volá **jen** po úspěšném návratu z `Pipeline.run`. Při jakékoli chybě se schránka nemění.

- [ ] **Step 1: Napiš padající test**

`Tests/CzechatorCoreTests/ErrorMessagesTests.swift`:

```swift
import Testing
@testable import CzechatorCore

@Test func describesEveryPipelineError() {
    #expect(ErrorMessages.describe(PipelineError.noText) == "Ve schránce není text.")
    #expect(ErrorMessages.describe(PipelineError.inputTooLarge(bytes: 60_000, limit: 51_200))
            == "Vstup má 60000 B, limit je 51200 B.")
    #expect(ErrorMessages.describe(PipelineError.providerFailed("timeout"))
            .hasPrefix("Model neodpověděl"))
    #expect(ErrorMessages.describe(PipelineError.verificationFailed(failedSegments: 3))
            == "Výsledek neprošel kontrolou (3 vadné segmenty). Schránka zůstala beze změny.")
}

@Test func describesClipboardErrors() {
    #expect(ErrorMessages.describe(ClipboardError.unsupportedFormat("RTF"))
            == "Formát RTF zatím neumím.")
    #expect(ErrorMessages.describe(ClipboardError.noTextRepresentation(availableTypes: ["public.png"]))
            == "Ve schránce není text.")
}

@Test func describesSecretErrors() {
    #expect(ErrorMessages.describe(SecretError.notFound("czechator-openai"))
            == "Nepodařilo se načíst klíč: czechator-openai.")
}

@Test func fallsBackToTheUnderlyingDescription() {
    struct Weird: Error {}
    #expect(!ErrorMessages.describe(Weird()).isEmpty)
}
```

- [ ] **Step 2: Spusť test a ověř, že selže**

Run: `make test`
Expected: FAIL — `cannot find 'ErrorMessages' in scope`.

- [ ] **Step 3: Napiš implementaci**

`Sources/CzechatorCore/ErrorMessages.swift`:

```swift
/// Every user-facing string in one place. The core speaks Czech to the user
/// and English to the compiler.
public enum ErrorMessages {

    public static func describe(_ error: any Error) -> String {
        switch error {
        case let error as PipelineError:
            return describe(error)
        case let error as ClipboardError:
            return describe(error)
        case let error as SecretError:
            return describe(error)
        default:
            return String(describing: error)
        }
    }

    private static func describe(_ error: PipelineError) -> String {
        switch error {
        case .noText:
            return "Ve schránce není text."
        case .inputTooLarge(let bytes, let limit):
            return "Vstup má \(bytes) B, limit je \(limit) B."
        case .providerFailed(let detail):
            return "Model neodpověděl použitelně: \(detail)"
        case .verificationFailed(let count):
            return "Výsledek neprošel kontrolou (\(count) \(segmentWord(count))). "
                 + "Schránka zůstala beze změny."
        }
    }

    private static func describe(_ error: ClipboardError) -> String {
        switch error {
        case .empty, .noTextRepresentation:
            return "Ve schránce není text."
        case .unsupportedFormat(let name):
            return "Formát \(name) zatím neumím."
        }
    }

    private static func describe(_ error: SecretError) -> String {
        switch error {
        case .notFound(let name):
            return "Nepodařilo se načíst klíč: \(name)."
        case .unsupported(let kind):
            return "Zdroj tajemství \(kind) není v tomto prostředí dostupný."
        }
    }

    private static func segmentWord(_ count: Int) -> String {
        switch count {
        case 1: return "vadný segment"
        case 2...4: return "vadné segmenty"
        default: return "vadných segmentů"
        }
    }
}
```

`Sources/CzechatorApp/NotificationCenterBridge.swift`:

```swift
import AppKit
import UserNotifications

/// Thin wrapper so the model does not deal with the notification framework
/// directly. Clicking a notification routes back through `onActivate`.
final class NotificationCenterBridge: NSObject, UNUserNotificationCenterDelegate {

    var onActivate: (() -> Void)?
    private var authorized = false

    func requestAuthorization() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert]) { [weak self] granted, _ in
                self?.authorized = granted
            }
    }

    func post(title: String, body: String) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        await MainActor.run { self.onActivate?() }
    }
}
```

`Sources/CzechatorApp/AppModel.swift`:

```swift
import AppKit
import CzechatorCore
import SwiftUI

enum RunState: Equatable {
    case idle
    case working
    case failed(String)
}

struct HistoryEntry: Identifiable, Equatable {
    let id = UUID()
    let preview: String
    let originalText: String
    let succeeded: Bool
    let detail: String?
}

@MainActor
final class AppModel: ObservableObject {

    @Published private(set) var state: RunState = .idle
    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var startupProblem: String?

    private var config: Config = .builtIn
    private let store = ConfigStore(url: ConfigStore.defaultURL())
    private let hotKeys = HotKeyManager()
    private let notifications = NotificationCenterBridge()
    private let source = PasteboardSource()
    private let sink = PasteboardSink()

    var iconName: String {
        switch state {
        case .idle: return "textformat.abc.dottedunderline"
        case .working: return "hourglass"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    var lastErrorDetail: String? {
        if case .failed(let message) = state { return message }
        return history.first(where: { !$0.succeeded })?.detail
    }

    func start() {
        notifications.onActivate = { [weak self] in self?.acknowledgeError() }
        notifications.requestAuthorization()
        reload()
    }

    /// Re-reads the config and re-registers the hotkey. Called at launch and
    /// after the settings window saves.
    func reload() {
        do {
            config = try store.load()
            guard let binding = config.hotkeys.first else {
                startupProblem = "Konfigurace neobsahuje žádnou zkratku."
                return
            }
            let spec = try ShortcutSpec.parse(binding.shortcut)
            if spec.isCommonSystemShortcut {
                startupProblem = "Zkratka \(binding.shortcut) je běžná systémová zkratka "
                               + "a v ostatních aplikacích přestane fungovat."
            } else {
                startupProblem = nil
            }
            try hotKeys.register(spec) { [weak self] in
                Task { @MainActor in self?.run() }
            }
        } catch {
            startupProblem = ErrorMessages.describe(error)
        }
    }

    func acknowledgeError() {
        if case .failed = state { state = .idle }
    }

    func restore(_ entry: HistoryEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.originalText, forType: .string)
    }

    func run() {
        guard state != .working else { return }
        state = .working

        Task { @MainActor in
            do {
                let input = try source.read()
                guard let profile = config.active else {
                    throw SecretError.notFound("profil \(config.activeProfile)")
                }
                let pipeline = Pipeline(
                    registry: try FormatRegistry(rules: config.segmentation),
                    provider: try makeProvider(profile),
                    limits: config.limits,
                    promptOverride: config.prompt.override)

                let result = try await pipeline.run(input)
                try sink.write(result)          // only ever reached on success
                state = .idle
                record(HistoryEntry(preview: preview(of: result.correctedText),
                                    originalText: result.originalText,
                                    succeeded: true,
                                    detail: nil))
            } catch {
                let message = ErrorMessages.describe(error)
                state = .failed(message)
                record(HistoryEntry(preview: "chyba",
                                    originalText: "",
                                    succeeded: false,
                                    detail: message))
                notifications.post(title: "Czechator", body: message)
            }
        }
    }

    private func makeProvider(_ profile: Profile) throws -> any LLMProvider {
        let client = URLSessionHTTPClient()
        let key = try profile.apiKey.map { try KeychainSecretResolver().resolve($0) }
        switch profile.kind {
        case .ollama:
            return OllamaProvider(endpoint: profile.endpoint, model: profile.model,
                                  temperature: profile.temperature,
                                  timeout: profile.timeoutSeconds, client: client)
        case .openaiCompat:
            return OpenAICompatProvider(endpoint: profile.endpoint, model: profile.model,
                                        temperature: profile.temperature,
                                        timeout: profile.timeoutSeconds,
                                        apiKey: key, client: client)
        }
    }

    private func record(_ entry: HistoryEntry) {
        guard config.features.history else { return }
        history.insert(entry, at: 0)
        if history.count > config.features.historySize {
            history.removeLast(history.count - config.features.historySize)
        }
    }

    private func preview(of text: String) -> String {
        let single = text.replacingOccurrences(of: "\n", with: " ")
        return single.count <= 40 ? single : String(single.prefix(40)) + "…"
    }
}
```

`Sources/CzechatorApp/CzechatorApp.swift`:

```swift
import AppKit
import SwiftUI

@main
struct CzechatorApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra("Czechator", systemImage: model.iconName) {
            MenuContent(model: model)
        }
        Settings {
            SettingsView(model: model)
        }
    }
}

/// Bootstraps the model once the app is actually running — the hotkey needs a
/// live event target and the notification prompt needs a foreground session.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.start() }
    }
}

struct MenuContent: View {

    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            Button("Doplnit diakritiku") { model.run() }

            if let problem = model.startupProblem {
                Divider()
                Text(problem).font(.caption)
            }

            if let detail = model.lastErrorDetail {
                Divider()
                Text("Poslední chyba: \(detail)").font(.caption)
            }

            if !model.history.isEmpty {
                Divider()
                Text("Historie")
                ForEach(model.history) { entry in
                    Button(entry.preview) { model.restore(entry) }
                        .disabled(!entry.succeeded)
                }
            }

            Divider()
            SettingsLink { Text("Nastavení…") }
            Button("Ukončit") { NSApplication.shared.terminate(nil) }
        }
        // Opening the menu counts as acknowledging the error: the badge clears
        // but the detail stays readable in the history below.
        .onAppear { model.acknowledgeError() }
    }
}
```

V `AppModel` (výše v tomto tasku) změň deklaraci na sdílenou instanci, aby ji
`AppDelegate` i `App` viděly jako tentýž objekt:

```swift
@MainActor
final class AppModel: ObservableObject {

    @MainActor static let shared = AppModel()

    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        notifications.onActivate = { [weak self] in self?.acknowledgeError() }
        notifications.requestAuthorization()
        reload()
    }
```

Zbytek `AppModel` zůstává, jak je uvedený výše; nahrazuje se pouze hlavička
třídy a tělo `start()`.

- [ ] **Step 4: Spusť testy a ověř běh aplikace**

Run: `make test`
Expected: PASS — 123 testů celkem.

Run: `swift run CzechatorApp`
Expected: v menu baru se objeví ikona. Klik na ni zobrazí položku „Doplnit diakritiku", „Nastavení…" a „Ukončit".

Ruční ověření (běží `ollama serve`, model stažený):
1. Zkopíruj `Prilis zlutoucky kun` do schránky.
2. Stiskni `Cmd+Ctrl+D`.
3. Vlož — očekávaný výsledek `Příliš žluťoučký kůň`.
4. Zkopíruj obrázek, stiskni zkratku — očekávaná notifikace „Ve schránce není text." a schránka beze změny.

- [ ] **Step 5: Commit**

```bash
git add Sources/CzechatorApp Sources/CzechatorCore/ErrorMessages.swift \
        Tests/CzechatorCoreTests/ErrorMessagesTests.swift
git commit -m "feat: aplikace v menu baru, historie a chybové stavy"
```

---

## Task 22: Nastavení a Keychain

**Files:**
- Create: `Sources/CzechatorApp/KeychainSecretResolver.swift`
- Create: `Sources/CzechatorApp/SettingsView.swift`

**Interfaces:**
- Consumes: `SecretRef`, `SecretResolver`, `SecretError` (Task 13), `Config`, `ConfigStore` (Task 16), `ShortcutSpec` (Task 19), `AppModel` (Task 21).
- Produces: `struct KeychainSecretResolver: SecretResolver`, `struct SettingsView: View`. `AppModel` dostane `func save(_ config: Config)`, které zapíše konfiguraci a zavolá `reload()`.

Bez jednotkových testů — Keychain i SwiftUI se v tomto prostředí headless netestují. Ověřuje se ručně.

- [ ] **Step 1: Napiš implementaci**

`Sources/CzechatorApp/KeychainSecretResolver.swift`:

```swift
import CzechatorCore
import Foundation
import Security

/// The only place in the app that touches Security.framework. The core knows
/// nothing about it, which is what keeps the core buildable on Linux.
struct KeychainSecretResolver: SecretResolver {

    private let service = "cz.czechator.app"

    func resolve(_ ref: SecretRef) throws -> String {
        switch ref {
        case .literal(let value):
            return value
        case .environment(let name):
            return try EnvironmentSecretResolver().resolve(.environment(name: name))
        case .keychain(let account):
            return try read(account: account)
        }
    }

    private func read(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            throw SecretError.notFound(account)
        }
        return value
    }

    func store(_ value: String, account: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var insert = base
        insert[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecretError.notFound(account) }
    }
}
```

`Sources/CzechatorApp/SettingsView.swift`:

```swift
import CzechatorCore
import SwiftUI

struct SettingsView: View {

    @ObservedObject var model: AppModel

    @State private var activeProfile: String = ""
    @State private var shortcut: String = ""
    @State private var apiKey: String = ""
    @State private var warning: String?

    var body: some View {
        Form {
            Section("Profil") {
                Picker("Aktivní profil", selection: $activeProfile) {
                    ForEach(model.profileNames, id: \.self) { Text($0) }
                }
                if let endpoint = model.endpointDescription(for: activeProfile) {
                    Text(endpoint).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Zkratka") {
                TextField("Zkratka", text: $shortcut)
                if let warning {
                    Text(warning).font(.caption).foregroundStyle(.orange)
                }
            }

            Section("Klíč pro cloudový profil") {
                SecureField("API klíč", text: $apiKey)
                Text("Uloží se do Keychainu, nikoli do konfiguračního souboru.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Uložit") { save() }
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { load() }
        .onChange(of: shortcut) { _, new in validate(new) }
    }

    private func load() {
        activeProfile = model.activeProfileName
        shortcut = model.shortcutText
        validate(shortcut)
    }

    private func validate(_ text: String) {
        do {
            let spec = try ShortcutSpec.parse(text)
            warning = spec.isCommonSystemShortcut
                ? "Tohle je běžná systémová zkratka — v ostatních aplikacích přestane fungovat."
                : nil
        } catch {
            warning = "Zkratku se nepodařilo přečíst."
        }
    }

    private func save() {
        if !apiKey.isEmpty, let account = model.keychainAccount(for: activeProfile) {
            try? KeychainSecretResolver().store(apiKey, account: account)
            apiKey = ""
        }
        model.applySettings(activeProfile: activeProfile, shortcut: shortcut)
    }
}
```

Do `AppModel` (Task 21) doplň:

```swift
    var profileNames: [String] { config.profiles.keys.sorted() }
    var activeProfileName: String { config.activeProfile }
    var shortcutText: String { config.hotkeys.first?.shortcut ?? "cmd+ctrl+d" }

    func endpointDescription(for profile: String) -> String? {
        config.profiles[profile].map { "\($0.kind.rawValue) · \($0.endpoint) · \($0.model)" }
    }

    func keychainAccount(for profile: String) -> String? {
        if case .keychain(let account) = config.profiles[profile]?.apiKey { return account }
        return nil
    }

    /// Writes through ConfigStore, which preserves keys the app does not know
    /// about, then re-registers the hotkey.
    func applySettings(activeProfile: String, shortcut: String) {
        var updated = config
        updated.activeProfile = activeProfile
        if updated.hotkeys.isEmpty {
            updated.hotkeys = [HotkeyBinding(shortcut: shortcut, source: "clipboard", sink: "clipboard")]
        } else {
            updated.hotkeys[0].shortcut = shortcut
        }
        do {
            try store.save(updated)
            reload()
        } catch {
            startupProblem = ErrorMessages.describe(error)
        }
    }
```

- [ ] **Step 2: Spusť testy a ověř překlad**

Run: `make test`
Expected: PASS — 123 testů, beze změny.

Run: `make build`
Expected: `Build complete!`

- [ ] **Step 3: Ručně ověř nastavení**

1. `swift run CzechatorApp`, otevři „Nastavení…".
2. Změň zkratku na `cmd+b` — pod polem se objeví oranžové varování.
3. Vrať `cmd+ctrl+d`, ulož.
4. Otevři `~/.config/czechator/config.yaml` a ověř, že se změnil jen `activeProfile` a `shortcut` a že ručně přidaný komentářový klíč zůstal.

- [ ] **Step 4: Commit**

```bash
git add Sources/CzechatorApp/KeychainSecretResolver.swift \
        Sources/CzechatorApp/SettingsView.swift Sources/CzechatorApp/AppModel.swift
git commit -m "feat: okno nastavení a klíče v Keychainu"
```

---

## Task 23: Sestavení .app bundlu bez Xcode

**Files:**
- Create: `Resources/Info.plist`
- Create: `Resources/icon.png` (1024×1024, vygeneruj nebo dodej ručně)
- Modify: `Makefile` (cíle `app`, `install`, `icon`)

**Interfaces:**
- Consumes: cíl `CzechatorApp` (Tasky 19–22).
- Produces: `make app` → `build/Czechator.app`, `make install` → zkopíruje do `/Applications`.

**Proč ručně:** v prostředí není plné Xcode, takže `.xcassets` ani `xcodebuild` nejsou k dispozici. `iconutil` a `codesign` v Command Line Tools jsou, takže bundle jde složit shellem.

**`LSUIElement`** musí být `true`, jinak se aplikace objeví v Docku a v přepínači aplikací, což u nástroje v menu baru nechceme.

- [ ] **Step 1: Napiš Info.plist**

`Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Czechator</string>
    <key>CFBundleDisplayName</key>       <string>Czechator</string>
    <key>CFBundleIdentifier</key>        <string>cz.czechator.app</string>
    <key>CFBundleExecutable</key>        <string>CzechatorApp</string>
    <key>CFBundleIconFile</key>          <string>Czechator</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key>           <string>1</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>LSUIElement</key>               <true/>
    <key>NSHumanReadableCopyright</key>  <string>Czechator</string>
</dict>
</plist>
```

- [ ] **Step 2: Doplň Makefile**

Připoj do `Makefile`:

```make
APP := build/Czechator.app
BIN := $(APP)/Contents/MacOS/CzechatorApp

.PHONY: app install icon

icon: Resources/icon.png
	rm -rf build/Czechator.iconset
	mkdir -p build/Czechator.iconset
	for size in 16 32 64 128 256 512; do \
	  sips -z $$size $$size Resources/icon.png \
	    --out build/Czechator.iconset/icon_$${size}x$${size}.png >/dev/null; \
	  sips -z $$((size*2)) $$((size*2)) Resources/icon.png \
	    --out build/Czechator.iconset/icon_$${size}x$${size}@2x.png >/dev/null; \
	done
	iconutil --convert icns build/Czechator.iconset --output build/Czechator.icns

app: icon
	swift build -c release --product CzechatorApp
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/CzechatorApp $(BIN)
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp build/Czechator.icns $(APP)/Contents/Resources/Czechator.icns
	codesign --force --sign - --timestamp=none $(APP)
	@echo "hotovo: $(APP)"

install: app
	rm -rf /Applications/Czechator.app
	cp -R $(APP) /Applications/Czechator.app
	@echo "nainstalováno do /Applications/Czechator.app"
```

- [ ] **Step 3: Sestav bundle**

Run: `make app`
Expected: vznikne `build/Czechator.app`, `codesign` skončí bez chyby.

Run: `codesign --verify --verbose build/Czechator.app`
Expected: `valid on disk`, `satisfies its Designated Requirement`.

- [ ] **Step 4: Ověř běh z bundlu**

Run: `open build/Czechator.app`
Expected:
- ikona v menu baru,
- **žádná** ikona v Docku (díky `LSUIElement`),
- systém se zeptá na povolení notifikací,
- `Cmd+Ctrl+D` nad zkopírovaným textem `Prilis zlutoucky kun` vloží `Příliš žluťoučký kůň`.

Pokud notifikace nedorazí, ověř v Nastavení systému → Oznámení, že je Czechator povolený. Bez notifikací zůstává chybový odznak na ikoně funkční, takže to není blokující.

- [ ] **Step 5: Commit**

```bash
git add Makefile Resources
git commit -m "feat: sestavení .app bundlu bez Xcode"
```

---

## Ruční ověření kvality modelu

Neběží v CI a není součástí žádného tasku — je to nástroj pro rozhodnutí, který model použít.

Založ `Fixtures/quality/` s ~50 dvojicemi `vstup.txt` / `ocekavany.txt` reprezentujícími skutečné použití: e-maily, commit messages, poznámky, JSON s českými hodnotami. Pak porovnej modely:

```bash
for model in qwen3:4b-instruct gemma3:4b; do
  echo "== $model"
  for f in Fixtures/quality/*.vstup.txt; do
    out=$(swift run czechator fix "$f" 2>/dev/null)
    exp=$(cat "${f%.vstup.txt}.ocekavany.txt")
    [ "$out" = "$exp" ] && echo "ok  $(basename $f)" || echo "CHYBA $(basename $f)"
  done
done
```

Model se přepíná úpravou `profiles.local.model` v konfiguraci. Rozhodnutí padne podle úspěšnosti a odezvy, ne podle velikosti modelu.

---

## Sebekontrola plánu

Prošel jsem plán proti specifikaci:

**Pokrytí specifikace.** Každá sekce má svůj task. §6 detekce → Tasky 4, 9, 20. §7 segmentace → Tasky 2, 3, 5, 6, 7, 8, 17. §8 verifikace → Tasky 1, 10, 15. §9 poskytovatelé a prompt → Tasky 11, 12, 13, 14. §10 konfigurace → Tasky 13, 16, 22. §11 chyby → Tasky 21, 22. §12 testy → průběžně, plus samostatná sekce kvality modelu výše. §13 sestavení → Tasky 1, 23.

**Odchylky od specifikace, na které je potřeba upozornit:**

1. **`--show-skipped` je užší, než §7 sliboval.** Vypisuje spany vyloučené regulárními výrazy s uvedením vzoru a přehled aktivních pravidel, ale ne uzel po uzlu, proč konkrétní element nebo klíč nedal segment. Plná atribuce by znamenala rozšířit protokol `FormatHandler` o ladicí rozhraní, což se pro MVP nevyplácí.

2. **Verifikace běží dvakrát** — po segmentech a nad celým dokumentem. Specifikace zmiňuje jen tu druhou; ta první je nutná, aby šlo zopakovat jen vadné segmenty, jak §8 vyžaduje.

3. **Cache oprav mezi HTML a plain průchodem** není ve specifikaci vůbec. Bez ní by zpracování schránky s oběma reprezentacemi stálo dvojnásobek volání modelu. Přidáno v Tasku 15.

4. **`escape` nikdy neescapuje z vlastní iniciativy** (Task 7). To je silnější pravidlo, než §7 popisovala, a je nutné pro přesný round trip.

**Konzistence typů.** `Segment` má oproti specifikaci navíc pole `raw` — bez něj by `escape(_:like:)` neměl podle čeho poznat styl escapování a nešlo by vracet nezměněné segmenty beze změny bajtů. Všechny tasky používají tuto rozšířenou podobu.

**Známá slabá místa, která si při implementaci zaslouží pozornost:**

- `MarkupScanner` je záměrně tolerantní k rozbité značce. U silně poškozeného HTML může vrátit méně uzlů — verifikace to podchytí, ale výsledkem bude odmítnutí, ne oprava.
- `AppModel` v Tasku 21 obsahuje komentář o bootstrapu přes `.task`; ten je potřeba dotáhnout, ne opsat doslova.
- Notifikace z ad-hoc podepsaného bundlu nemusí systém pustit. Chybový odznak na ikoně je proto primární kanál, notifikace doplňkový.

---

## Execution Handoff

**Plán je hotový a uložený v `docs/superpowers/plans/2026-08-19-czechator.md`. Dvě možnosti provedení:**

**1. Subagent-Driven (doporučeno)** — na každý task pošlu čerstvého subagenta, mezi tasky výsledek zkontroluji, rychlá iterace.

**2. Inline Execution** — tasky provedu v této session přes executing-plans, dávkově s kontrolními body.

**Kterou cestu?**

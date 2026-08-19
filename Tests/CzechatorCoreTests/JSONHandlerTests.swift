import Foundation
import Testing

@testable import CzechatorCore

private func jsonHandler() throws -> JSONHandler { try JSONHandler(rules: .builtIn) }

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
    #expect(try jsonHandler().segments(in: text).map(\.text) == ["dalsi text"])
}

@Test func unescapesContentForTheModel() throws {
    let text = #"{"a": "prvni\nradek á konec"}"#
    let segments = try jsonHandler().segments(in: text)
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

@Test func escapeStyleIsNotFooledByEscapedBackslashes() throws {
    // "a\\/b" — the escaped backslash must not be read as an escaped solidus,
    // and "C:\\uzivatel" must not be read as using \u escapes.
    let raws = [#"a\\/b"#, #"C:\\uzivatel\\slozka aábc"#, #"konec radku \\n neni novy radek"#]
    for raw in raws {
        let style = JSONEscapeStyle.detect(in: raw)
        let round = JSONEscaping.escape(JSONEscaping.unescape(raw[...]), style: style)
        #expect(round == raw, "round trip failed for \(raw)")
    }
    #expect(JSONEscapeStyle.detect(in: #"a\\/b"#).escapedSolidus == false)
    #expect(JSONEscapeStyle.detect(in: #"C:\\uzivatel"#).spellings.isEmpty)
    #expect(JSONEscapeStyle.detect(in: #"opravdu \/ escapovane"#).escapedSolidus == true)
    #expect(JSONEscapeStyle.detect(in: #"opravdu \u00e1 escapovane"#).spellings.count == 1)
}

@Test func scannerRejectsTextThatOnlyLooksLikeJSON() {
    #expect(throws: (any Error).self) { try JSONScanner.scan(#"{"a": undefinedGarbage}"#) }
    #expect(throws: (any Error).self) { try JSONScanner.scan(#"{"a": "\q"}"#) }
    #expect(throws: (any Error).self) { try JSONScanner.scan(#"{"a": 1.2.3.4}"#) }
    #expect(throws: (any Error).self) { try JSONScanner.scan(#"{"a": 0x10}"#) }
    #expect(throws: (any Error).self) { try JSONScanner.scan(#"{"a": "\u12"}"#) }
    #expect(JSONHandler.confidence(for: ClipboardInput(text: #"{"a": undefinedGarbage}"#)) == 0)
}

@Test func scannerAcceptsEveryValidJSONNumberShape() throws {
    let valid = ["0", "-0", "12", "-3.5", "1e10", "2E+3", "7.25e-4"]
    for number in valid {
        #expect(throws: Never.self) { try JSONScanner.scan("{\"a\": \(number)}") }
    }
}

@Test func jsonSpliceWithRawReproducesOriginalExactly() throws {
    let text = #"""
        {
          "id": "abc",
          "nazev": "prvni text",
          "vnorene": { "popis": "druhy á text", "url": "https://example.com" },
          "seznam": ["treti text", 42, true, null]
        }
        """#
    let segments = try jsonHandler().segments(in: text)
    let rebuilt = try Reassembler.splice(
        text, segments: segments, replacements: segments.map(\.raw))
    #expect(rebuilt == text)
}

@Test func correctingOneValueLeavesStructureUntouched() throws {
    let text = #"{"b": 1, "a": "prilis zlutoucky kun"}"#
    let handler = try jsonHandler()
    let segments = try handler.segments(in: text)
    let replacements = segments.map { handler.escape("příliš žluťoučký kůň", like: $0) }
    let rebuilt = try Reassembler.splice(text, segments: segments, replacements: replacements)
    #expect(rebuilt == #"{"b": 1, "a": "příliš žluťoučký kůň"}"#)
}

@Test func jsonConfidenceRequiresParsableJSON() {
    #expect(JSONHandler.confidence(for: ClipboardInput(text: #"{"a": "b"}"#)) == 0.9)
    #expect(JSONHandler.confidence(for: ClipboardInput(text: "jen text")) == 0)
    #expect(JSONHandler.confidence(for: ClipboardInput(text: #"{"a": }"#)) == 0)
    #expect(JSONHandler.id == "json")
}

@Test func keepsEscapedCharactersEscapedAndNewOnesPlain() {
    // Python's json.dumps escapes non-ASCII by default, so this is most
    // machine-written JSON. A per-flag style made every such document refuse
    // correction; a per-position one lets the escape survive untouched.
    let raw = #"krasn\u00e9 misto"#
    let style = JSONEscapeStyle.detect(in: raw)
    #expect(style.spellings == [5: #"\u00e9"#])

    let unescaped = JSONEscaping.unescape(raw[...])
    #expect(unescaped == "krasné misto")
    #expect(JSONEscaping.escape(unescaped, style: style) == raw)
    // The corrected text keeps the escape and writes new accents plainly.
    #expect(JSONEscaping.escape("krásné místo", style: style) == #"krásn\u00e9 místo"#)
}

@Test func escapedBackslashIsNotMistakenForAnEscape() {
    for raw in [#"a\\/b"#, #"C:\\uzivatel"#, #"opravdu \/ escapovane"#] {
        let style = JSONEscapeStyle.detect(in: raw)
        #expect(JSONEscaping.escape(JSONEscaping.unescape(raw[...]), style: style) == raw)
    }
    #expect(JSONEscapeStyle.detect(in: #"a\\/b"#).escapedSolidus == false)
    #expect(JSONEscapeStyle.detect(in: #"C:\\uzivatel"#).spellings.isEmpty)
}

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

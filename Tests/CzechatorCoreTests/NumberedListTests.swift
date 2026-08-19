import Foundation
import Testing

@testable import CzechatorCore

@Test func encodesItemsWithOneBasedNumbering() {
    #expect(NumberedList.encode(["prvni", "druhy"]) == "1. prvni\n2. druhy")
}

@Test func escapesNewlinesAndBackslashes() {
    #expect(NumberedList.encode(["a\nb", "c\\d"]) == "1. a\\nb\n2. c\\\\d")
}

@Test func decodeRoundTripsEncode() throws {
    let items = ["prvni radek", "s\nnovym radkem", "zpetne \\ lomitko", "tabulator\tuvnitr"]
    #expect(try NumberedList.decode(NumberedList.encode(items), expectedCount: 4) == items)
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
    #expect(throws: NumberedListError.badNumbering(atItem: 2)) {
        try NumberedList.decode("1. a\n3. b", expectedCount: 2)
    }
}

@Test func decodePreservesLeadingAndTrailingSpacesInsideItems() throws {
    // The model must not be able to smuggle whitespace changes past the codec;
    // only the single space after the dot is the separator.
    #expect(try NumberedList.decode("1.  dve mezery", expectedCount: 1) == [" dve mezery"])
}

@Test func systemPromptIsStableAndEnglish() {
    let first = PromptBuilder.build(items: ["x"], systemOverride: nil).system
    let second = PromptBuilder.build(items: ["y", "z"], systemOverride: nil).system
    #expect(first == second)
    #expect(first == PromptBuilder.defaultSystem)
    #expect(first.contains("Czech diacritics"))
}

@Test func userMessageCarriesOnlyTheVariablePart() {
    let prompt = PromptBuilder.build(items: ["prvni", "druhy"], systemOverride: nil)
    #expect(prompt.user == "1. prvni\n2. druhy")
}

@Test func systemOverrideReplacesTheBuiltInPrompt() {
    #expect(PromptBuilder.build(items: ["x"], systemOverride: "vlastni").system == "vlastni")
}

@Test func decodeRejectsAnItemWrappedAcrossLines() {
    // The item count would still add up, so a silent skip would truncate text.
    #expect(throws: NumberedListError.unexpectedContinuation(afterItem: 2)) {
        try NumberedList.decode(
            "1. prvni\n2. druhy radek\npokracovani druheho", expectedCount: 2)
    }
}

@Test func decodeStillToleratesAPreambleBeforeTheFirstItem() throws {
    #expect(
        try NumberedList.decode("Zde je opraveny seznam:\n1. prvni\n2. druhy", expectedCount: 2)
            == ["prvni", "druhy"])
}

@Test func escapesCRLFAsTwoEscapes() {
    // CRLF is one grapheme; matching only "\n"/"\r" let a real line break into
    // the wire format and broke the numbered list.
    #expect(NumberedList.encode(["a\r\nb"]) == "1. a\\r\\nb")
    #expect(try! NumberedList.decode("1. a\\r\\nb", expectedCount: 1) == ["a\r\nb"])
}

@Test func maskingHidesWhitespaceTheModelWouldMangle() {
    let text = "Skoleni v\u{00A0}utery, cena 1\u{00A0}500 Kc"
    let mask = FragileWhitespace.mask(text)
    // Nothing exotic reaches the model.
    #expect(!mask.masked.unicodeScalars.contains { $0.value == 0x00A0 })
    #expect(mask.positions.count == 2)
    // A correction of the same length gets its characters back.
    #expect(mask.restore(into: mask.masked) == text)
    #expect(
        FragileWhitespace.mask("Skoleni v\u{00A0}utery")
            .restore(into: "Školení v úterý") == "Školení v\u{00A0}úterý")
}

@Test func maskingGivesUpWhenTheModelChangedTheLength() {
    let mask = FragileWhitespace.mask("a\u{00A0}b")
    // Indices would be meaningless; the verifier rejects it instead.
    #expect(mask.restore(into: "a b navic") == "a b navic")
}

@Test func crlfRoundTripsThroughAPlainTextDocument() throws {
    let text = "Prvni radek textu.\r\nDruhy radek textu."
    let segments = try PlainTextHandler(rules: .builtIn).segments(in: text)
    #expect(segments.map(\.text) == ["Prvni radek textu.", "Druhy radek textu."])
    let rebuilt = try Reassembler.splice(
        text, segments: segments, replacements: segments.map(\.raw))
    #expect(rebuilt == text)
}

@Test func windowsJSONIsStillDetectedAsJSON() throws {
    let text = "{\r\n  \"nazev\": \"Prilis zlutoucky kun\"\r\n}"
    #expect(JSONHandler.confidence(for: ClipboardInput(text: text)) == 0.9)
    #expect(try JSONHandler(rules: .builtIn).segments(in: text).map(\.text)
        == ["Prilis zlutoucky kun"])
}

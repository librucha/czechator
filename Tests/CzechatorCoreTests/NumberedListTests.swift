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

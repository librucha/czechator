import Testing

@testable import CzechatorCore

@Test func protectedIndicesAreEmptyForPlainText() throws {
    let handler = try PlainTextHandler(rules: .builtIn)
    let text = "ahoj svete"
    let segment = Segment(
        range: text.startIndex..<text.endIndex, raw: text, text: text, kind: .plain)
    #expect(handler.protectedIndices(in: segment).isEmpty)
}

@Test func protectedIndicesFindAnHTMLEntity() throws {
    // "a &amp; b" unescapes to "a & b"; the ampersand sits at index 2 and must
    // still be at a known index after any correction, or it gets re-escaped in
    // the wrong place.
    let handler = try HTMLHandler(rules: .builtIn)
    let raw = "a &amp; b"
    let segment = Segment(
        range: raw.startIndex..<raw.endIndex, raw: raw, text: "a & b", kind: .htmlText)
    #expect(handler.protectedIndices(in: segment) == [2])
}

@Test func protectedIndicesAreEmptyForMarkupWithoutEntities() throws {
    let handler = try HTMLHandler(rules: .builtIn)
    let raw = "ahoj svete"
    let segment = Segment(
        range: raw.startIndex..<raw.endIndex, raw: raw, text: raw, kind: .htmlText)
    #expect(handler.protectedIndices(in: segment).isEmpty)
}

@Test func protectedIndicesFindAJSONEscape() throws {
    // "a\\nb" unescapes to "a\nb"; the newline is at index 1.
    let handler = try JSONHandler(rules: .builtIn)
    let raw = #"a\nb"#
    let segment = Segment(
        range: raw.startIndex..<raw.endIndex, raw: raw, text: "a\nb", kind: .jsonString)
    #expect(handler.protectedIndices(in: segment) == [1])
}

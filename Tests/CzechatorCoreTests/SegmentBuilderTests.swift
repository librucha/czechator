import Foundation
import Testing

@testable import CzechatorCore

private func build(
    _ text: String,
    rules: CommonRules = .builtIn,
    extra: [String] = []
) throws -> [Segment] {
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
    let prepared = try SegmentBuilder(
        common: .builtIn,
        extraSkipPatterns: [#"example\.com/\S*"#]
    )
    .prepared(for: "x https://example.com/a y")
    #expect(prepared.excludedSpans.count == 1)
}

@Test func candidateScopeStopsAGreedyPatternAtTheNodeBoundary() throws {
    // A URL pattern ending in \S+ used to run past the closing quote and eat
    // the first word of the next JSON value.
    let text = #"{"a":"koukni na https://x.com","b":"dalsi text k oprave"}"#
    let segments = try JSONHandler(rules: .builtIn).segments(in: text)
    #expect(segments.map(\.text) == ["koukni na", "dalsi text k oprave"])
}

@Test func candidateScopeStopsAGreedyPatternAtTagBoundary() throws {
    let text = "<p>koukni na https://x.com</p><p>dalsi text</p>"
    let segments = try HTMLHandler(rules: .builtIn).segments(in: text)
    #expect(segments.map(\.text) == ["koukni na", "dalsi text"])
}

@Test func documentScopeStillHandlesMultiLinePatterns() throws {
    let text = "pred\n```\nkod\n```\npo"
    let segments = try PlainTextHandler(rules: .builtIn).segments(in: text)
    #expect(segments.map(\.text) == ["pred", "po"])
}

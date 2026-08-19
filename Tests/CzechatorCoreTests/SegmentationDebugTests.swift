import Foundation
import Testing

@testable import CzechatorCore

@Test func reportsWhichPatternExcludedWhichSpan() throws {
    let text = "napis na petr@example.com nebo https://example.com/x"
    let spans = try SegmentationDebug.excludedSpans(in: text, rules: .builtIn, formatID: "plain")

    #expect(spans.map(\.text) == ["petr@example.com", "https://example.com/x"])
    #expect(spans[0].pattern == #"\S+@\S+\.\S+"#)
    #expect(spans[1].pattern == #"https?://\S+"#)
    #expect(spans[0].offset == 9)
}

@Test func includesFormatSpecificPatternsForPlainText() throws {
    let spans = try SegmentationDebug.excludedSpans(
        in: "pouzij `kod` tady", rules: .builtIn, formatID: "plain")
    #expect(spans.map(\.text) == ["`kod`"])
}

@Test func doesNotApplyPlainPatternsToJSON() throws {
    let spans = try SegmentationDebug.excludedSpans(
        in: #"{"a": "pouzij `kod` tady"}"#, rules: .builtIn, formatID: "json")
    #expect(spans.isEmpty)
}

@Test func summarisesTheRulesInEffect() {
    let json = SegmentationDebug.activeRuleSummary(rules: .builtIn, formatID: "json")
    #expect(json.contains { $0.contains("skipKeys") })
    #expect(json.contains { $0.contains("skipValuesForKeys") })

    let html = SegmentationDebug.activeRuleSummary(rules: .builtIn, formatID: "html")
    #expect(html.contains { $0.contains("script") })
}

@Test func reportedSpansRespectTheNodeBoundaryForStructuredFormats() throws {
    let text = #"{"a":"koukni na https://x.com","b":"dalsi text"}"#
    let spans = try SegmentationDebug.excludedSpans(in: text, rules: .builtIn, formatID: "json")
    // Not "https://x.com\",\"b\":\"dalsi" — the pattern stops at the value's end.
    #expect(spans.map(\.text) == ["https://x.com"])
}

@Test func doesNotReportSpansInsideValuesTheRulesDropWholesale() throws {
    // The handler never scans this value at all, so blaming the URL pattern
    // would give the wrong reason for the missing segment.
    let text = #"{"id":"https://example.com/track","note":"dalsi text"}"#
    let spans = try SegmentationDebug.excludedSpans(in: text, rules: .builtIn, formatID: "json")
    #expect(spans.isEmpty)
}

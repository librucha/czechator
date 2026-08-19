import Foundation
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
    let rebuilt = try Reassembler.splice(
        text, segments: segments, replacements: segments.map(\.raw))
    #expect(rebuilt == text)
}

@Test func escapeIsIdentityForPlainText() throws {
    let text = "ahoj"
    let handler = try handler()
    let segments = try handler.segments(in: text)
    #expect(handler.escape("ahoj", like: segments[0]) == "ahoj")
}

@Test func confidenceIsTheLowFallbackValue() {
    #expect(PlainTextHandler.confidence(for: ClipboardInput(text: "cokoliv")) == 0.1)
    #expect(PlainTextHandler.id == "plain")
}

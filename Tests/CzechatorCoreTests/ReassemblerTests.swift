import Foundation
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

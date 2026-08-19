import Foundation
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

@Test func keepsAnOversizedSegmentInItsOwnBatch() {
    #expect(SegmentBatcher.batches(segments([10, 500, 10]), maxChars: 100) == [[0], [1], [2]])
}

@Test func returnsNothingForNoSegments() {
    #expect(SegmentBatcher.batches([], maxChars: 100).isEmpty)
}

@Test func coversEverySegmentExactlyOnce() {
    let all = SegmentBatcher.batches(segments([30, 30, 30, 30, 30]), maxChars: 70).flatMap { $0 }
    #expect(all == [0, 1, 2, 3, 4])
}

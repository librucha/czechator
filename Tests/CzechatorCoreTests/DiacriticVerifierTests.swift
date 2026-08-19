import Foundation
import Testing

@testable import CzechatorCore

@Test func acceptsPureDiacriticRestoration() {
    #expect(
        DiacriticVerifier.documentMatches(
            original: "Prilis zlutoucky kun", corrected: "Příliš žluťoučký kůň"))
}

@Test func rejectsAddedText() {
    #expect(
        !DiacriticVerifier.documentMatches(
            original: "Prilis zlutoucky kun", corrected: "Příliš žluťoučký kůň. Hotovo!"))
}

@Test func rejectsReformatting() {
    #expect(
        !DiacriticVerifier.documentMatches(
            original: #"{"a":"x"}"#, corrected: #"{ "a": "x" }"#))
}

@Test func rejectsCaseChanges() {
    #expect(!DiacriticVerifier.documentMatches(original: "ahoj", corrected: "Ahoj"))
}

@Test func rejectsWhitespaceChanges() {
    #expect(!DiacriticVerifier.documentMatches(original: "a  b", corrected: "a b"))
}

@Test func identifiesOnlyTheOffendingSegments() {
    let text = "prvni druhy treti"
    func segment(_ s: String) -> Segment {
        Segment(range: text.range(of: s)!, raw: s, text: s, kind: .plain)
    }
    let segments = [segment("prvni"), segment("druhy"), segment("treti")]
    let corrections = ["první", "druhý navíc", "třetí"]
    #expect(DiacriticVerifier.failingIndices(segments: segments, corrections: corrections) == [1])
}

@Test func reportsEverythingWhenCountsDisagree() {
    let text = "a"
    let segments = [
        Segment(range: text.startIndex..<text.endIndex, raw: "a", text: "a", kind: .plain)
    ]
    #expect(DiacriticVerifier.failingIndices(segments: segments, corrections: []) == [0])
}

@Test func acceptsSegmentsThatNeedNoChange() {
    let text = "abc"
    let segments = [
        Segment(range: text.startIndex..<text.endIndex, raw: "abc", text: "abc", kind: .plain)
    ]
    #expect(DiacriticVerifier.failingIndices(segments: segments, corrections: ["abc"]).isEmpty)
}

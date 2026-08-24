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

private func segment(_ text: String) -> Segment {
    let document = text
    return Segment(
        range: document.startIndex..<document.endIndex, raw: text, text: text, kind: .plain)
}

@Test func verifierStrictModeStillRefusesATypoFix() {
    // The existing guarantee must be exactly as tight as it was.
    let failing = DiacriticVerifier.failingIndices(
        segments: [segment("kndeliky")], corrections: ["knedlíky"],
        policy: .preserve, mode: .strict, budget: .builtIn)
    #expect(failing == [0])
}

@Test func verifierStrictModeIgnoresAGenerousBudget() {
    // A mode called Přísný that honoured a 90 % budget would not be strict.
    // Strict forces the budget to zero rather than merely defaulting it.
    let failing = DiacriticVerifier.failingIndices(
        segments: [segment("kndeliky")], corrections: ["knedlíky"],
        policy: .preserve, mode: .strict, budget: EditBudget(percent: 90, minimum: 5))
    #expect(failing == [0])
}

@Test func verifierTolerantModeAcceptsATypoFix() {
    let failing = DiacriticVerifier.failingIndices(
        segments: [segment("kndeliky")], corrections: ["knedlíky"],
        policy: .preserve, mode: .minorFixes, budget: .builtIn)
    #expect(failing.isEmpty)
}

@Test func verifierTolerantModeStillRefusesARewrittenWord() {
    let failing = DiacriticVerifier.failingIndices(
        segments: [segment("schuzka se kona v utery")],
        corrections: ["schůzka se koná ve středu"],
        policy: .preserve, mode: .proofread, budget: .builtIn)
    #expect(failing == [0])
}

@Test func verifierFallsBackToStrictOnAnOversizedSegment() {
    // Above the limit the alignment is not run at all, so a tolerant mode
    // behaves exactly like a strict one rather than accepting blindly.
    let long = String(repeating: "a", count: 2_001)
    let failing = DiacriticVerifier.failingIndices(
        segments: [segment(long)], corrections: [long + "b"],
        policy: .preserve, mode: .proofread, budget: .builtIn)
    #expect(failing == [0])
}

@Test func verifierGapsMatchAcceptsAnHonestSplice() {
    let document = "a <b>ahoj</b> c"
    let range = document.range(of: "ahoj")!
    let segments = [Segment(range: range, raw: "ahoj", text: "ahoj", kind: .htmlText)]
    let output = "a <b>ahój</b> c"
    #expect(
        DiacriticVerifier.gapsMatch(
            original: document, output: output, segments: segments, replacements: ["ahój"]))
}

@Test func verifierGapsMatchRefusesAChangeOutsideASegment() {
    let document = "a <b>ahoj</b> c"
    let range = document.range(of: "ahoj")!
    let segments = [Segment(range: range, raw: "ahoj", text: "ahoj", kind: .htmlText)]
    // The tag itself changed — exactly what nothing is allowed to do.
    let output = "a <i>ahój</i> c"
    #expect(
        !DiacriticVerifier.gapsMatch(
            original: document, output: output, segments: segments, replacements: ["ahój"]))
}

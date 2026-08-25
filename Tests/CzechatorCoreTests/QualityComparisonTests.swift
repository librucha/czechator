import Testing

@testable import CzechatorCore

@Test func qualityComparisonRefusesWrongDiacritics() {
    // The one way to ruin this tool: fold the accents away before comparing.
    // The reference already carries the right ones, so folding would score a
    // wrong accent as correct — and wrong accents are what the model gets wrong.
    #expect(
        !QualityComparison.matches(
            got: "byt", want: "být", mode: .strict, policy: .preserve))
    #expect(
        !QualityComparison.matches(
            got: "bít", want: "byt", mode: .proofread, policy: .preserve))
}

@Test func qualityComparisonPreserveDemandsExactEquality() {
    #expect(
        QualityComparison.matches(
            got: "Příliš žluťoučký kůň", want: "Příliš žluťoučký kůň",
            mode: .strict, policy: .preserve))
    #expect(
        !QualityComparison.matches(
            got: "příliš žluťoučký kůň", want: "Příliš žluťoučký kůň",
            mode: .strict, policy: .preserve))
}

@Test func qualityComparisonModelPolicyIgnoresCase() {
    #expect(
        QualityComparison.matches(
            got: "Proč se to stalo v Praze", want: "proč se to stalo v praze",
            mode: .strict, policy: .model))
}

@Test func qualityComparisonSegmentStartAllowsOnlyTheFirstLetterOfEachLine() {
    #expect(
        QualityComparison.matches(
            got: "Dobrý den\nposílám podklady", want: "dobrý den\nposílám podklady",
            mode: .strict, policy: .segmentStart))
    // A case change anywhere else is still a miss.
    #expect(
        !QualityComparison.matches(
            got: "dobrý Den\nposílám podklady", want: "dobrý den\nposílám podklady",
            mode: .strict, policy: .segmentStart))
}

@Test func qualityComparisonSegmentStartComparesCRLFAsCRLF() {
    // In Swift a CRLF pair is a SINGLE Character equal to neither "\n" nor
    // "\r", so anything that splits on "\n" does not split a CRLF document at
    // all — and `segmentStart` would then relax only the first letter of the
    // whole document instead of each line. The second line is what pins it.
    #expect(
        QualityComparison.matches(
            got: "Dobrý den\r\nPosílám", want: "dobrý den\r\nposílám",
            mode: .strict, policy: .segmentStart))
    // Still exact everywhere but the line starts.
    #expect(
        !QualityComparison.matches(
            got: "Dobrý den\r\nposíláM", want: "dobrý den\r\nposílám",
            mode: .strict, policy: .segmentStart))
    // A terminator difference is a miss, not a case difference.
    #expect(
        !QualityComparison.matches(
            got: "Dobrý den\nposílám", want: "dobrý den\r\nposílám",
            mode: .strict, policy: .segmentStart))
}

@Test func qualityComparisonTolerantModesIgnoreCaseWhateverThePolicy() {
    // letterCase does nothing outside strict, so the comparison must not
    // pretend it does — a tolerant run is allowed to change case.
    for policy in LetterCasePolicy.allCases {
        #expect(
            QualityComparison.matches(
                got: "Posílám vám podklady", want: "posílám vám podklady",
                mode: .minorFixes, policy: policy))
    }
}

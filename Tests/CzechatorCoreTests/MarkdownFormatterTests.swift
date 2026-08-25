import Testing

@testable import CzechatorCore

private func sampleReport() -> QualityReport {
    QualityReport(
        version: "1.0.0",
        measuredOn: "2026-08-25",
        letterCase: .preserve,
        invocation: "czechator quality --profile local --corrections all",
        verificationForced: false,
        sets: [
            QualitySetResult(
                setName: "clean",
                sampleCount: 23,
                cells: [
                    QualityCell(
                        profileName: "local", model: "qwen3:4b-instruct",
                        corrections: .strict, budget: nil,
                        exact: 15, accepted: 22, refused: 1, total: 23,
                        misses: [], passed: []),
                    QualityCell(
                        profileName: "claude", model: "claude-sonnet-5",
                        corrections: .proofread,
                        budget: EditBudget(percent: 35, minimum: 2),
                        exact: 21, accepted: 23, refused: 0, total: 23,
                        misses: [], passed: []),
                ])
        ])
}

@Test func markdownRendersOneTablePerSet() {
    let out = MarkdownFormatter.render(sampleReport())
    #expect(out.contains("### clean — 23 vzorků"))
    #expect(
        out.contains("| profil | model | režim | rozpočet | přesně | přes verifikaci | odmítnuto |")
    )
}

@Test func markdownShowsCountsAndPercentages() {
    let out = MarkdownFormatter.render(sampleReport())
    #expect(
        out.contains(
            "| local | qwen3:4b-instruct | Přísný | — | 15/23 (65 %) | 22/23 (96 %) | 1/23 |"))
    #expect(
        out.contains(
            "| claude | claude-sonnet-5 | Korektura | 35 %/2 | 21/23 (91 %) | 23/23 (100 %) | 0/23 |"
        ))
}

@Test func markdownCarriesItsOwnProvenance() {
    // A published number without the command that produced it is an assertion
    // with no evidence — and a stale table reads as current.
    let out = MarkdownFormatter.render(sampleReport())
    #expect(out.contains("czechator 1.0.0"))
    #expect(out.contains("2026-08-25"))
    #expect(out.contains("letterCase: preserve"))
    #expect(out.contains("`czechator quality --profile local --corrections all`"))
}

@Test func markdownSaysWhenVerificationWasForced() {
    var report = sampleReport()
    report = QualityReport(
        version: report.version, measuredOn: report.measuredOn,
        letterCase: report.letterCase, invocation: report.invocation,
        verificationForced: true, sets: report.sets)
    #expect(MarkdownFormatter.render(report).contains("ověřování vynuceno"))
    #expect(!MarkdownFormatter.render(sampleReport()).contains("ověřování vynuceno"))
}

@Test func markdownCarriesNoEndpoint() {
    // QualityCell has no endpoint field at all, which is the real guard — this
    // test is what stops someone adding one for convenience and leaking an
    // internal gateway address into a public repository.
    #expect(!MarkdownFormatter.render(sampleReport()).contains("http"))
}

@Test func markdownHasNoLevelOneHeading() {
    // It has to paste into README as well as stand alone as a file.
    #expect(!MarkdownFormatter.render(sampleReport()).contains("\n# "))
}

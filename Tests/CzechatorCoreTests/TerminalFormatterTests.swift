import Testing

@testable import CzechatorCore

private func report(exact: Int, accepted: Int, total: Int) -> QualityReport {
    QualityReport(
        version: "1.0.0", measuredOn: "2026-08-25", letterCase: .preserve,
        invocation: "czechator quality", verificationForced: false,
        sets: [
            QualitySetResult(
                setName: "clean", sampleCount: total,
                cells: [
                    QualityCell(
                        profileName: "local", model: "qwen3:4b-instruct",
                        corrections: .strict, budget: nil,
                        exact: exact, accepted: accepted, refused: total - accepted,
                        total: total, misses: [], passed: [])
                ])
        ])
}

@Test func terminalOmitsEscapesWhenColourIsOff() {
    let out = TerminalFormatter.render(report(exact: 15, accepted: 22, total: 23), color: false)
    #expect(!out.contains("\u{001B}["))
    #expect(out.contains("qwen3:4b-instruct"))
    #expect(out.contains("15/23"))
}

@Test func terminalEmitsEscapesWhenColourIsOn() {
    let out = TerminalFormatter.render(report(exact: 15, accepted: 22, total: 23), color: true)
    #expect(out.contains("\u{001B}["))
}

@Test func terminalPaintsABadRunRedAndAGoodOneGreen() {
    // The whole point of the heat scale: a run refusing half the documents has
    // to look alarming at a glance.
    let bad = TerminalFormatter.render(report(exact: 2, accepted: 4, total: 23), color: true)
    let good = TerminalFormatter.render(report(exact: 23, accepted: 23, total: 23), color: true)
    #expect(bad.contains("\u{001B}[31m"))
    #expect(good.contains("\u{001B}[92m"))
}

@Test func terminalBarIsProportionalToTheRatio() {
    #expect(TerminalFormatter.bar(0.0) == String(repeating: "░", count: 12))
    #expect(TerminalFormatter.bar(1.0) == String(repeating: "█", count: 12))
    #expect(
        TerminalFormatter.bar(0.5) == String(repeating: "█", count: 6)
            + String(repeating: "░", count: 6))
}

@Test func terminalShowsTheProvenanceLineToo() {
    let out = TerminalFormatter.render(report(exact: 1, accepted: 1, total: 1), color: false)
    #expect(out.contains("letterCase: preserve"))
}

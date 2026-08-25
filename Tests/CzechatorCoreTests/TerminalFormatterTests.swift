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

@Test func terminalBarSurvivesAnOutOfRangeRatio() {
    // String(repeating:count:) traps on a negative count, so an upstream bug
    // that lets a ratio leave 0...1 must draw a wrong bar, not kill the run.
    #expect(TerminalFormatter.bar(-0.5) == String(repeating: "░", count: 12))
    #expect(TerminalFormatter.bar(1.5) == String(repeating: "█", count: 12))
}

@Test func terminalHeatPromotesAValueSittingExactlyOnAThreshold() {
    // The scan is `ratio < threshold`, so a value landing exactly on a boundary
    // gets the NEXT band up, not that one. Ported verbatim from the Python
    // harness this replaces (Tools/quality.py:64-66) — pinned here so nobody
    // flips the convention by accident.
    #expect(TerminalFormatter.heat(0.50, "x", color: true).hasPrefix("\u{001B}[38;5;208m"))
    #expect(TerminalFormatter.heat(0.95, "x", color: true).hasPrefix("\u{001B}[92m"))
    // And just below each boundary the lower band still wins.
    #expect(TerminalFormatter.heat(0.49, "x", color: true).hasPrefix("\u{001B}[31m"))
    #expect(TerminalFormatter.heat(0.94, "x", color: true).hasPrefix("\u{001B}[32m"))
}

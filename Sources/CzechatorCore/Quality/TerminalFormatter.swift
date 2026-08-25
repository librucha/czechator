import Foundation

/// Renders a report for a terminal, with the heat scale ported from the Python
/// harness this replaces.
///
/// Unlike the Markdown formatter this may show the endpoint: the output is not
/// meant to be committed anywhere.
public enum TerminalFormatter {

    /// Worst to best. A run that refuses half the documents should look
    /// alarming at a glance; one that only misses a few accents should not.
    static let heatScale: [(threshold: Double, code: String)] = [
        (0.50, "\u{001B}[31m"),  // red
        (0.70, "\u{001B}[38;5;208m"),  // orange
        (0.85, "\u{001B}[33m"),  // yellow
        (0.95, "\u{001B}[32m"),  // green
        (1.01, "\u{001B}[92m"),  // bright green
    ]
    static let reset = "\u{001B}[0m"

    static func bar(_ ratio: Double, width: Int = 12) -> String {
        let filled = Int((ratio * Double(width)).rounded())
        return String(repeating: "█", count: filled)
            + String(repeating: "░", count: width - filled)
    }

    static func heat(_ ratio: Double, _ text: String, color: Bool) -> String {
        guard color else { return text }
        for step in heatScale where ratio < step.threshold {
            return step.code + text + reset
        }
        return text
    }

    public static func render(
        _ report: QualityReport, color: Bool, verbose: Bool = false
    ) -> String {
        var lines: [String] = []
        for set in report.sets {
            lines.append("")
            lines.append("== \(set.setName)  (\(set.sampleCount) vzorků)")
            for cell in set.cells {
                let head = "\(cell.profileName) · \(cell.model) · \(cell.corrections.label)"
                lines.append(head)
                lines.append("  přesně          " + cellText(cell.exact, cell.total, color))
                lines.append("  přes verifikaci " + cellText(cell.accepted, cell.total, color))
                lines.append("  odmítnuto       \(cell.refused)/\(cell.total)")
                if verbose {
                    for name in cell.passed { lines.append("    ok   \(name)") }
                }
                for miss in cell.misses {
                    lines.append("    \(miss.refused ? "STOP" : "~   ") \(miss.sample)")
                    if !miss.refused {
                        lines.append("         chtěl:  \(miss.want.debugDescription)")
                        lines.append("         dostal: \(miss.got.debugDescription)")
                    }
                }
            }
        }
        lines.append("")
        var tail =
            "czechator \(report.version) · \(report.measuredOn) "
            + "· letterCase: \(report.letterCase.rawValue)"
        if report.verificationForced { tail += " · ověřování vynuceno" }
        lines.append(tail)
        return lines.joined(separator: "\n") + "\n"
    }

    private static func cellText(_ value: Int, _ total: Int, _ color: Bool) -> String {
        let ratio = total > 0 ? Double(value) / Double(total) : 0
        let label = String(format: "%3d/%-3d %5.1f%%", value, total, ratio * 100)
        return heat(ratio, "\(label) \(bar(ratio))", color: color)
    }
}

/// Renders a report as Markdown meant to be committed and read on GitHub.
///
/// Deliberately emits no level-one heading: the output has to paste into an
/// existing README as well as stand alone as a file.
///
/// Deliberately carries no endpoint. A measurement run against an internal
/// gateway would otherwise leak its address into a public repository.
public enum MarkdownFormatter {

    public static func render(_ report: QualityReport) -> String {
        var lines: [String] = []
        for set in report.sets {
            lines.append("### \(set.setName) — \(set.sampleCount) vzorků")
            lines.append("")
            lines.append(
                "| profil | model | režim | rozpočet | přesně | přes verifikaci | odmítnuto |")
            lines.append("|---|---|---|---|---|---|---|")
            for cell in set.cells {
                lines.append(row(cell))
            }
            lines.append("")
        }
        lines.append("<sub>\(provenance(report))</sub>")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func row(_ cell: QualityCell) -> String {
        let budget = cell.budget.map { "\($0.percent) %/\($0.minimum)" } ?? "—"
        return "| \(cell.profileName) | \(cell.model) | \(cell.corrections.label) | \(budget) "
            + "| \(fraction(cell.exact, cell.total)) "
            + "| \(fraction(cell.accepted, cell.total)) "
            + "| \(cell.refused)/\(cell.total) |"
    }

    /// "15/23 (65 %)" — the count first, because the ratio hides how few
    /// samples a percentage was computed from.
    private static func fraction(_ value: Int, _ total: Int) -> String {
        guard total > 0 else { return "0/0" }
        let percent = Int((Double(value) / Double(total) * 100).rounded())
        return "\(value)/\(total) (\(percent) %)"
    }

    private static func provenance(_ report: QualityReport) -> String {
        var parts = [
            "czechator \(report.version)",
            report.measuredOn,
            "letterCase: \(report.letterCase.rawValue)",
        ]
        if report.verificationForced { parts.append("ověřování vynuceno") }
        parts.append("`\(report.invocation)`")
        return parts.joined(separator: " · ")
    }
}

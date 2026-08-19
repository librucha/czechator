/// How much freedom the model gets over letter case.
///
/// Capitalizing the first word of a sentence is good Czech, and small models do
/// it whatever the prompt says. But case is not diacritics, and the tool's
/// guarantee — `fold(output) == fold(input)` — is what proves nothing else
/// changed. Allowing case everywhere gives that up: `PRAHA` may come back as
/// `Praha`, `ČSN` as `Čsn`, `iPhone` as `IPhone`.
public enum LetterCasePolicy: String, Sendable, Codable, Equatable, CaseIterable {
    /// Force the original case back. The strictest reading of the guarantee.
    case preserve
    /// Let the first letter of a segment change case, nothing else. A segment is
    /// a line of plain text, a JSON string value or one HTML text node — often a
    /// sentence, but not always one.
    case segmentStart
    /// Keep whatever the model returned. Verification can no longer prove that
    /// only diacritics changed.
    case model

    /// Comparison form: folds away diacritics, plus whatever case difference
    /// this policy tolerates.
    public func normalize(_ text: String) -> String {
        let folded = DiacriticFolding.fold(text)
        switch self {
        case .preserve:
            return folded
        case .model:
            return folded.lowercased()
        case .segmentStart:
            guard let first = folded.first else { return folded }
            return String(first).lowercased() + folded.dropFirst()
        }
    }
}

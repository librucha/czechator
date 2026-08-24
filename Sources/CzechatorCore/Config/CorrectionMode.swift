/// What the model is asked to do.
///
/// Drives both the prompt and how much the verifier tolerates, and the two must
/// move together: loosening verification on its own gains no fixes at all,
/// because the prompt still forbids them — it only widens the hole.
///
/// Only `strict` can prove that nothing but diacritics changed. The other two
/// prove something weaker: that no word was changed by more than its budget.
public enum CorrectionMode: String, Sendable, Codable, Equatable, CaseIterable {
    case strict
    case minorFixes = "minor-fixes"
    case proofread

    /// Alongside ModifierKey.label and LetterCasePolicy.label: the settings
    /// window needs a name for each case, and keeping it next to the case is
    /// what stops the two drifting.
    public var label: String {
        switch self {
        case .strict: return "Přísný"
        case .minorFixes: return "Drobné opravy"
        case .proofread: return "Korektura"
        }
    }

    public var isTolerant: Bool { self != .strict }
}

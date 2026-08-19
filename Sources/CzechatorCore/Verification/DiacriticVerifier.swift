/// The tool's single hard guarantee: after folding away Czech diacritics the
/// output must be *exactly* the input. This catches structural edits, casing
/// changes, reformatting, and any commentary the model volunteers.
///
/// It deliberately does NOT catch wrong diacritics — English text the model
/// decorated folds back to the same string. That is a prompt and model quality
/// problem, not an architectural one.
public enum DiacriticVerifier {

    public static func documentMatches(original: String, corrected: String) -> Bool {
        DiacriticFolding.fold(original) == DiacriticFolding.fold(corrected)
    }

    /// Indices of segments whose correction changed something other than
    /// diacritics. Used to retry just the offenders instead of the whole batch.
    public static func failingIndices(segments: [Segment], corrections: [String]) -> [Int] {
        guard segments.count == corrections.count else {
            return Array(segments.indices)
        }
        return segments.indices.filter {
            !documentMatches(original: segments[$0].text, corrected: corrections[$0])
        }
    }
}

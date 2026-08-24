/// In strict mode the tool's hard guarantee: after folding away Czech
/// diacritics a segment's correction must be *exactly* the original. This
/// catches structural edits, casing changes, reformatting, and any commentary
/// the model volunteers. A tolerant mode trades it for the weaker per-word
/// budget in `WordBudget`.
///
/// It deliberately does NOT catch wrong diacritics — English text the model
/// decorated folds back to the same string. That is a prompt and model quality
/// problem, not an architectural one.
public enum DiacriticVerifier {

    /// A segment longer than this is compared strictly whatever the mode says:
    /// the alignment is O(n*m) and not worth running on a paragraph that size.
    public static let toleranceLimit = 2_000

    /// Indices of segments whose correction changed more than the mode allows.
    /// Used to retry just the offenders instead of the whole batch.
    public static func failingIndices(
        segments: [Segment], corrections: [String],
        policy: LetterCasePolicy = .preserve,
        mode: CorrectionMode = .strict,
        budget: EditBudget = .builtIn
    ) -> [Int] {
        guard segments.count == corrections.count else {
            return Array(segments.indices)
        }
        return segments.indices.filter {
            !accepts(
                original: segments[$0].text, correction: corrections[$0],
                policy: policy, mode: mode, budget: budget)
        }
    }

    static func accepts(
        original: String, correction: String,
        policy: LetterCasePolicy, mode: CorrectionMode, budget: EditBudget
    ) -> Bool {
        guard mode.isTolerant,
            original.count <= toleranceLimit, correction.count <= toleranceLimit
        else {
            return policy.normalize(original) == policy.normalize(correction)
        }
        return WordBudget.withinBudget(
            original: original, correction: correction, budget: budget, limit: toleranceLimit)
    }

    /// The bytes between segments must survive untouched.
    ///
    /// Replaces the fold comparison, which tolerance makes inexpressible. It is
    /// an independent second implementation of the splice, and stays exact in
    /// every mode — including with verification switched off, because what it
    /// catches is our own reassembly bug rather than anything the model did.
    ///
    /// Weaker than the comparison it replaces. That is the cost of the feature,
    /// not an oversight.
    ///
    /// Unlike Reassembler.splice this does not sort: handlers report segments in
    /// document order, and an unsorted list is a bug worth failing on.
    public static func gapsMatch(
        original: String, output: String, segments: [Segment], replacements: [String]
    ) -> Bool {
        guard segments.count == replacements.count else { return false }
        var expected = ""
        expected.reserveCapacity(original.count)
        var cursor = original.startIndex
        for (segment, replacement) in zip(segments, replacements) {
            guard segment.range.lowerBound >= cursor else { return false }
            expected += original[cursor..<segment.range.lowerBound]
            expected += replacement
            cursor = segment.range.upperBound
        }
        expected += original[cursor...]
        return expected == output
    }
}

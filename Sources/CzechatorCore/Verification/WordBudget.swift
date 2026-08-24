/// Splits a segment into words and checks each one's edits against its own
/// allowance.
///
/// The character-level alignment gives the attribution for free, and that is
/// what makes a change in the number of words work at all: pairing words off
/// one by one would break the moment a space moved, which is precisely the
/// case this exists to allow.
public enum WordBudget {

    /// fold + lowercase + runs of whitespace collapsed to a single space.
    ///
    /// Deliberately does NOT strip whitespace or punctuation wholesale.
    /// Stripping them would be an exact comparison of the wrong thing: a model
    /// that glued "ahoj svete" into "ahojsvete" would pass. The budget covers
    /// those edits instead, and bounds them from above.
    public static func normalize(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var lastWasSpace = false
        for character in DiacriticFolding.fold(s).lowercased() {
            if character.isWhitespace {
                if !lastWasSpace { out.append(" ") }
                lastWasSpace = true
            } else {
                out.append(character)
                lastWasSpace = false
            }
        }
        return out
    }

    /// Grapheme ranges of the non-whitespace runs.
    static func words(in normalized: [Character]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start: Int?
        for (index, character) in normalized.enumerated() {
            if character.isWhitespace {
                if let from = start {
                    ranges.append(from..<index)
                    start = nil
                }
            } else if start == nil {
                start = index
            }
        }
        if let from = start { ranges.append(from..<normalized.count) }
        return ranges
    }

    /// The word an edit is charged to.
    ///
    /// An edit that lands on whitespace belongs to the word before it: a
    /// misplaced space is the fault of the word it was taken from. With no word
    /// before it, it belongs to the one after.
    static func wordIndex(for position: Int, in ranges: [Range<Int>]) -> Int {
        for (index, range) in ranges.enumerated() {
            if range.contains(position) { return index }
            if position < range.lowerBound { return Swift.max(0, index - 1) }
        }
        return ranges.count - 1
    }

    /// Whether every word stayed inside its own allowance.
    ///
    /// Returns false rather than true when the pair is too long to align —
    /// fail-closed. Callers that want the strict comparison in that case must
    /// check the length themselves before calling; DiacriticVerifier does.
    public static func withinBudget(
        original: String, correction: String, budget: EditBudget, limit: Int = 2_000
    ) -> Bool {
        let a = Array(normalize(original))
        let b = Array(normalize(correction))
        if a == b { return true }

        guard let alignment = EditAlignment.compute(a, b, limit: limit) else { return false }

        let ranges = words(in: a)
        guard !ranges.isEmpty else { return alignment.distance == 0 }

        var spent = [Int](repeating: 0, count: ranges.count)
        for position in alignment.editPositions {
            spent[wordIndex(for: position, in: ranges)] += 1
        }
        for (index, range) in ranges.enumerated() {
            if spent[index] > budget.allowance(forWordOfLength: range.count) { return false }
        }
        return true
    }
}

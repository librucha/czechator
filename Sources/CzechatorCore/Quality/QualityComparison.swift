/// Whether a measured output matches its reference.
///
/// Deliberately does NOT fold diacritics, unlike every other comparison in this
/// project. The reference already carries the correct accents, so folding would
/// score a wrongly accented answer as right — and wrong accents are exactly what
/// this tool exists to measure. `DiacriticVerifier` folds because it asks a
/// different question: whether anything *but* accents changed.
public enum QualityComparison {

    public static func matches(
        got: String, want: String, mode: CorrectionMode, policy: LetterCasePolicy
    ) -> Bool {
        // A tolerant run was asked to fix capitalization, so `letterCase` is
        // inert there and the comparison has to be too.
        guard !mode.isTolerant else { return got.lowercased() == want.lowercased() }

        switch policy {
        case .preserve:
            return got == want
        case .model:
            return got.lowercased() == want.lowercased()
        case .segmentStart:
            return lowercasedLineStarts(got) == lowercasedLineStarts(want)
        }
    }

    /// Lowercases the first character of every line, leaving everything else —
    /// including the line terminators — exactly as written.
    ///
    /// Walks characters rather than splitting on "\n": in Swift a CRLF pair is a
    /// SINGLE Character equal to neither "\n" nor "\r", so splitting on "\n"
    /// would not split a CRLF document at all and `segmentStart` would silently
    /// relax only the very first letter of the whole thing. `Character.isNewline`
    /// is true for the CRLF grapheme, so this handles all three conventions.
    static func lowercasedLineStarts(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        var atLineStart = true
        for character in text {
            if atLineStart {
                out += String(character).lowercased()
                atLineStart = false
            } else {
                out.append(character)
            }
            if character.isNewline { atLineStart = true }
        }
        return out
    }
}

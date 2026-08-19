/// Hides whitespace the model cannot be trusted with, then puts it back.
///
/// A non-breaking space after a one-letter preposition is standard Czech
/// typesetting, so it is in essentially everything copied from the web or from
/// Word — the primary input of this tool. The model rewrites U+00A0 as U+202F,
/// which fails verification every single time, making those documents
/// impossible to correct at all.
///
/// Escaping it as ` ` does not help: the model interprets the escape and
/// hands back a plain space. So the character is replaced with a plain space
/// *before* the prompt is built and restored by position afterwards. Diacritic
/// restoration preserves grapheme count, so the positions still line up — the
/// same reasoning `MarkupEntityStyle` relies on.
public struct FragileWhitespace: Sendable, Equatable {

    public static let characters: Set<Character> = [
        "\u{00A0}",  // no-break space
        "\u{202F}",  // narrow no-break space
        "\u{2002}", "\u{2003}", "\u{2004}", "\u{2005}", "\u{2006}",
        "\u{2007}", "\u{2008}", "\u{2009}", "\u{200A}",  // en/em/figure/thin spaces
        "\u{3000}",  // ideographic space
        "\u{200B}",  // zero width space
        "\u{2060}",  // word joiner
        "\u{00AD}",  // soft hyphen
        "\u{2011}",  // non-breaking hyphen
        "\u{FEFF}",  // byte order mark
    ]
    // U+200D (zero width joiner) is deliberately absent: masking it would tear
    // emoji sequences apart.

    /// The text with every fragile character replaced by a plain space.
    public let masked: String
    /// Grapheme index in `masked` to the character that was there.
    public let positions: [Int: Character]

    public init(masked: String, positions: [Int: Character]) {
        self.masked = masked
        self.positions = positions
    }

    public static func mask(_ text: String) -> FragileWhitespace {
        var masked = ""
        masked.reserveCapacity(text.count)
        var positions: [Int: Character] = [:]

        for (index, character) in text.enumerated() {
            if characters.contains(character) {
                positions[index] = character
                masked.append(" ")
            } else {
                masked.append(character)
            }
        }
        return FragileWhitespace(masked: masked, positions: positions)
    }

    /// Puts the original characters back at their recorded positions.
    ///
    /// If the model changed the length the indices no longer mean anything, so
    /// the correction is returned untouched and left to the verifier, which
    /// will reject it.
    public func restore(into corrected: String) -> String {
        guard !positions.isEmpty else { return corrected }
        guard corrected.count == masked.count else { return corrected }

        var out = ""
        out.reserveCapacity(corrected.count)
        for (index, character) in corrected.enumerated() {
            out.append(positions[index] ?? character)
        }
        return out
    }
}

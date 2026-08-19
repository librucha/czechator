/// Removes Czech diacritical marks.
///
/// Deliberately a hand-written table rather than
/// `String.folding(options: .diacriticInsensitive)`: that path goes through ICU,
/// which behaves differently in swift-corelibs-foundation on Linux. This is the
/// one function in the tool that must be byte-for-byte deterministic everywhere.
public enum DiacriticFolding {

    private static let table: [Character: Character] = [
        "á": "a", "é": "e", "í": "i", "ó": "o", "ú": "u", "ý": "y",
        "č": "c", "ď": "d", "ě": "e", "ň": "n", "ř": "r",
        "š": "s", "ť": "t", "ů": "u", "ž": "z",
        "Á": "A", "É": "E", "Í": "I", "Ó": "O", "Ú": "U", "Ý": "Y",
        "Č": "C", "Ď": "D", "Ě": "E", "Ň": "N", "Ř": "R",
        "Š": "S", "Ť": "T", "Ů": "U", "Ž": "Z",
    ]

    /// Swift compares and hashes `Character` by canonical equivalence, so a
    /// decomposed "s" + U+030C matches the precomposed "š" key.
    public static func fold(_ s: String) -> String {
        String(s.map { table[$0] ?? $0 })
    }
}

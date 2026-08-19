import Foundation

/// Where the source document used an entity, and which spelling it used.
///
/// Keyed by **character index in the unescaped text**, not by character. A
/// per-character map cannot tell `a & b &amp; c` apart: it would learn that
/// `&` is spelled `&amp;` and re-escape the bare one too, changing bytes the
/// model never touched. Diacritic restoration is grapheme-count preserving, so
/// indices line up between the unescaped and the corrected text.
public struct MarkupEntityStyle: Sendable, Equatable {
    public var spellings: [Int: String]

    public init(spellings: [Int: String]) { self.spellings = spellings }

    /// Walks `raw` exactly like `unescape` does, recording the output index of
    /// every character that came from an entity.
    public static func detect(in raw: String, table: [String: Character]) -> MarkupEntityStyle {
        var spellings: [Int: String] = [:]
        var outputIndex = 0
        var index = raw.startIndex

        while index < raw.endIndex {
            guard raw[index] == "&",
                let semicolon = raw[index...].firstIndex(of: ";"),
                raw.distance(from: index, to: semicolon) <= 10,
                MarkupEntities.resolveEntity(
                    raw[raw.index(after: index)..<semicolon], table: table) != nil
            else {
                outputIndex += 1
                index = raw.index(after: index)
                continue
            }
            spellings[outputIndex] = String(raw[index...semicolon])
            outputIndex += 1
            index = raw.index(after: semicolon)
        }
        return MarkupEntityStyle(spellings: spellings)
    }
}

public enum MarkupEntities {

    public static let xmlTable: [String: Character] = [
        "lt": "<", "gt": ">", "amp": "&", "quot": "\"", "apos": "'",
    ]

    public static let htmlTable: [String: Character] = xmlTable.merging([
        "nbsp": "\u{00A0}", "copy": "©", "reg": "®", "trade": "™",
        "hellip": "…", "mdash": "—", "ndash": "–",
        "laquo": "«", "raquo": "»", "bdquo": "„", "ldquo": "“", "rdquo": "”",
        "eacute": "é", "aacute": "á", "iacute": "í", "oacute": "ó", "uacute": "ú",
        "yacute": "ý", "scaron": "š", "zcaron": "ž", "ccaron": "č", "rcaron": "ř",
    ]) { current, _ in current }

    /// Resolves one entity body (the part between `&` and `;`).
    static func resolveEntity(_ body: Substring, table: [String: Character]) -> Character? {
        if body.hasPrefix("#x") || body.hasPrefix("#X") {
            guard let value = UInt32(body.dropFirst(2), radix: 16),
                let scalar = UnicodeScalar(value)
            else { return nil }
            return Character(scalar)
        }
        if body.hasPrefix("#") {
            guard let value = UInt32(body.dropFirst()), let scalar = UnicodeScalar(value) else {
                return nil
            }
            return Character(scalar)
        }
        return table[String(body)]
    }

    public static func unescape(_ s: Substring, table: [String: Character]) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var index = s.startIndex

        while index < s.endIndex {
            guard s[index] == "&",
                let semicolon = s[index...].firstIndex(of: ";"),
                s.distance(from: index, to: semicolon) <= 10,
                let character = resolveEntity(s[s.index(after: index)..<semicolon], table: table)
            else {
                out.append(s[index])
                index = s.index(after: index)
                continue
            }
            out.append(character)
            index = s.index(after: semicolon)
        }
        return out
    }

    /// Restores the entity spellings the source used, position by position.
    ///
    /// Never escapes on its own initiative: the model only adds diacritics, so
    /// no new `&` or `<` can appear, and replaying the recorded spellings is
    /// therefore exactly reversible. If the model did change the length, the
    /// indices misalign — the verifier then rejects the result, which is the
    /// designed fail-closed behaviour.
    public static func escape(_ s: String, style: MarkupEntityStyle) -> String {
        guard !style.spellings.isEmpty else { return s }
        var out = ""
        out.reserveCapacity(s.count)
        for (index, character) in s.enumerated() {
            if let spelling = style.spellings[index] {
                out += spelling
            } else {
                out.append(character)
            }
        }
        return out
    }
}

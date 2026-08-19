import Foundation

/// Which entity spelling the source document used for a given character.
/// Escaping is driven purely by this map, so an untouched segment escapes back
/// to exactly the bytes it came from.
public struct MarkupEntityStyle: Sendable, Equatable {
    public var preferred: [Character: String]

    public init(preferred: [Character: String]) { self.preferred = preferred }

    /// Records, for every entity the source actually used, the exact spelling.
    /// First spelling wins, so a document mixing `&#160;` and `&nbsp;` round
    /// trips the first form and fails verification for the rest — deliberate.
    public static func detect(in raw: String, table: [String: Character]) -> MarkupEntityStyle {
        var preferred: [Character: String] = [:]
        var index = raw.startIndex

        while index < raw.endIndex {
            guard raw[index] == "&",
                let semicolon = raw[index...].firstIndex(of: ";"),
                raw.distance(from: index, to: semicolon) <= 10,
                let character = MarkupEntities.resolveEntity(
                    raw[raw.index(after: index)..<semicolon], table: table)
            else {
                index = raw.index(after: index)
                continue
            }
            if preferred[character] == nil {
                preferred[character] = String(raw[index...semicolon])
            }
            index = raw.index(after: semicolon)
        }
        return MarkupEntityStyle(preferred: preferred)
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

    /// Escapes only what the source escaped. See `MarkupEntityStyle`.
    ///
    /// The model only ever adds diacritics, so no new `&` or `<` can appear;
    /// a style-driven escape is therefore both sufficient and exactly reversible.
    public static func escape(_ s: String, style: MarkupEntityStyle) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for character in s {
            if let spelling = style.preferred[character] {
                out += spelling
            } else {
                out.append(character)
            }
        }
        return out
    }
}

import Foundation

/// Which optional escapes the source document used. Preserved so that an
/// unchanged segment escapes back to exactly the bytes it came from.
/// Which optional escape the source used, recorded **per position** in the
/// unescaped text.
///
/// A per-flag style could not round trip a document that writes Czech letters
/// as `\u00e9` — the escape and the character are different byte sequences, so
/// `fold` sees them as different and the document check refuses every
/// correction. Python's `json.dumps` escapes non-ASCII by default, so that is
/// most machine-written JSON. Recording positions lets an escaped character stay
/// escaped while a newly accented one is written plainly, exactly as
/// `MarkupEntityStyle` does for entities.
public struct JSONEscapeStyle: Sendable, Equatable {
    /// Grapheme index in the unescaped text to the spelling the source used.
    public var spellings: [Int: String]
    public var escapedSolidus: Bool

    public init(spellings: [Int: String], escapedSolidus: Bool) {
        self.spellings = spellings
        self.escapedSolidus = escapedSolidus
    }

    public static func detect(in raw: String) -> JSONEscapeStyle {
        var spellings: [Int: String] = [:]
        var escapedSolidus = false
        var outputIndex = 0
        var index = raw.startIndex

        while index < raw.endIndex {
            guard raw[index] == "\\" else {
                outputIndex += 1
                index = raw.index(after: index)
                continue
            }
            let next = raw.index(after: index)
            guard next < raw.endIndex else { break }

            if raw[next] == "u",
                let hexEnd = raw.index(next, offsetBy: 5, limitedBy: raw.endIndex)
            {
                spellings[outputIndex] = String(raw[index..<hexEnd])
                outputIndex += 1
                index = hexEnd
                continue
            }
            if raw[next] == "/" { escapedSolidus = true }
            // Consume both characters, so an escaped backslash cannot be
            // mistaken for the start of the next escape.
            outputIndex += 1
            index = raw.index(after: next)
        }
        return JSONEscapeStyle(spellings: spellings, escapedSolidus: escapedSolidus)
    }
}

public enum JSONEscaping {

    public static func unescape(_ s: Substring) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var index = s.startIndex
        var pendingHighSurrogate: UInt32?

        func flushSurrogate() {
            if let high = pendingHighSurrogate {
                out.append(Character(UnicodeScalar(high) ?? UnicodeScalar(0xFFFD)!))
                pendingHighSurrogate = nil
            }
        }

        while index < s.endIndex {
            let character = s[index]
            guard character == "\\" else {
                flushSurrogate()
                out.append(character)
                index = s.index(after: index)
                continue
            }
            let next = s.index(after: index)
            guard next < s.endIndex else {
                flushSurrogate()
                out.append(character)
                break
            }
            let escape = s[next]
            if escape == "u" {
                let hexStart = s.index(after: next)
                guard let hexEnd = s.index(hexStart, offsetBy: 4, limitedBy: s.endIndex),
                    let value = UInt32(s[hexStart..<hexEnd], radix: 16)
                else {
                    flushSurrogate()
                    out.append(character)
                    index = next
                    continue
                }
                if (0xD800...0xDBFF).contains(value) {
                    flushSurrogate()
                    pendingHighSurrogate = value
                } else if (0xDC00...0xDFFF).contains(value), let high = pendingHighSurrogate {
                    let combined = 0x1_0000 + ((high - 0xD800) << 10) + (value - 0xDC00)
                    pendingHighSurrogate = nil
                    out.append(Character(UnicodeScalar(combined) ?? UnicodeScalar(0xFFFD)!))
                } else {
                    flushSurrogate()
                    out.append(Character(UnicodeScalar(value) ?? UnicodeScalar(0xFFFD)!))
                }
                index = hexEnd
                continue
            }
            flushSurrogate()
            switch escape {
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "r": out.append("\r")
            case "b": out.append("\u{08}")
            case "f": out.append("\u{0C}")
            case "\"": out.append("\"")
            case "\\": out.append("\\")
            case "/": out.append("/")
            default: out.append(escape)
            }
            index = s.index(after: next)
        }
        flushSurrogate()
        return out
    }

    public static func escape(_ s: String, style: JSONEscapeStyle) -> String {
        var out = ""
        out.reserveCapacity(s.count)

        for (index, character) in s.enumerated() {
            // A character the source wrote as an escape keeps that spelling,
            // byte for byte.
            if let spelling = style.spellings[index] {
                out += spelling
                continue
            }
            for scalar in String(character).unicodeScalars {
                switch scalar {
                case "\"": out += "\\\""
                case "\\": out += "\\\\"
                case "\n": out += "\\n"
                case "\t": out += "\\t"
                case "\r": out += "\\r"
                case "\u{08}": out += "\\b"
                case "\u{0C}": out += "\\f"
                case "/": out += style.escapedSolidus ? "\\/" : "/"
                default:
                    if scalar.value < 0x20 {
                        out += String(format: "\\u%04x", scalar.value)
                    } else {
                        out.unicodeScalars.append(scalar)
                    }
                }
            }
        }
        return out
    }
}

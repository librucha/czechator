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
        var escapedSolidus = false

        // One entry per grapheme of the unescaped text, in order, recording the
        // raw source it came from. A surrogate pair is two escapes but one
        // grapheme, and a combining mark attaches to the grapheme before it —
        // counting one index per escape shifted every later position.
        var spans: [(start: String.Index, end: String.Index, hasEscape: Bool)] = []

        var out = ""
        var index = raw.startIndex

        while index < raw.endIndex {
            let tokenStart = index
            let countBefore = out.count
            var tokenIsEscape = false

            if raw[index] == "\\", raw.index(after: index) < raw.endIndex {
                let next = raw.index(after: index)
                tokenIsEscape = true
                if raw[next] == "/" { escapedSolidus = true }
                if raw[next] == "u",
                    let hexEnd = raw.index(next, offsetBy: 5, limitedBy: raw.endIndex)
                {
                    index = hexEnd
                } else {
                    index = raw.index(after: next)
                }
            } else {
                index = raw.index(after: index)
            }
            out = JSONEscaping.unescape(raw[raw.startIndex..<index])

            if out.count > countBefore {
                if !spans.isEmpty { spans[spans.count - 1].end = tokenStart }
                spans.append((start: tokenStart, end: index, hasEscape: tokenIsEscape))
            } else if !spans.isEmpty {
                spans[spans.count - 1].hasEscape =
                    spans[spans.count - 1].hasEscape || tokenIsEscape
            }
        }
        if !spans.isEmpty { spans[spans.count - 1].end = raw.endIndex }

        var spellings: [Int: String] = [:]
        for (position, span) in spans.enumerated() where span.hasEscape {
            spellings[position] = String(raw[span.start..<span.end])
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

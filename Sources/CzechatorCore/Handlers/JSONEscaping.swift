import Foundation

/// Which optional escapes the source document used. Preserved so that an
/// unchanged segment escapes back to exactly the bytes it came from.
public struct JSONEscapeStyle: Sendable, Equatable {
    public var unicodeEscapes: Bool
    public var escapedSolidus: Bool
    /// Documents written with `\u00E9` must not come back as `\u00e9`; the
    /// document would no longer reassemble byte-for-byte and every correction
    /// touching such a value would be refused.
    public var uppercaseHex: Bool

    public init(unicodeEscapes: Bool, escapedSolidus: Bool, uppercaseHex: Bool = false) {
        self.unicodeEscapes = unicodeEscapes
        self.escapedSolidus = escapedSolidus
        self.uppercaseHex = uppercaseHex
    }

    /// Walks the escape sequences instead of substring-matching them.
    ///
    /// A naive `contains("\\u")` fires on an escaped backslash that happens to
    /// precede a literal `u` — `C:\\uzivatel` would be read as using \u escapes,
    /// and every non-ASCII character in that value would come back re-encoded.
    /// That changes bytes outside the corrected text, which the tool must never do.
    public static func detect(in raw: String) -> JSONEscapeStyle {
        var unicodeEscapes = false
        var escapedSolidus = false
        var uppercaseHex = false
        var index = raw.startIndex

        while index < raw.endIndex {
            guard raw[index] == "\\" else {
                index = raw.index(after: index)
                continue
            }
            let next = raw.index(after: index)
            guard next < raw.endIndex else { break }
            switch raw[next] {
            case "u":
                unicodeEscapes = true
                let hexStart = raw.index(after: next)
                if let hexEnd = raw.index(hexStart, offsetBy: 4, limitedBy: raw.endIndex),
                    raw[hexStart..<hexEnd].contains(where: { $0.isUppercase })
                {
                    uppercaseHex = true
                }
            case "/": escapedSolidus = true
            default: break
            }
            // Consume both characters, so an escaped backslash cannot be
            // mistaken for the start of the next escape.
            index = raw.index(after: next)
        }
        return JSONEscapeStyle(
            unicodeEscapes: unicodeEscapes, escapedSolidus: escapedSolidus,
            uppercaseHex: uppercaseHex)
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
        for scalar in s.unicodeScalars {
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
                let hex = style.uppercaseHex ? "\\u%04X" : "\\u%04x"
                if scalar.value < 0x20 {
                    out += String(format: hex, scalar.value)
                } else if style.unicodeEscapes, scalar.value > 0x7F {
                    for unit in String(scalar).utf16 {
                        out += String(format: hex, unit)
                    }
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }
}

import Foundation

/// Which optional escapes the source document used. Preserved so that an
/// unchanged segment escapes back to exactly the bytes it came from.
public struct JSONEscapeStyle: Sendable, Equatable {
    public var unicodeEscapes: Bool
    public var escapedSolidus: Bool

    public init(unicodeEscapes: Bool, escapedSolidus: Bool) {
        self.unicodeEscapes = unicodeEscapes
        self.escapedSolidus = escapedSolidus
    }

    public static func detect(in raw: String) -> JSONEscapeStyle {
        JSONEscapeStyle(
            unicodeEscapes: raw.contains("\\u"),
            escapedSolidus: raw.contains("\\/"))
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
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else if style.unicodeEscapes, scalar.value > 0x7F {
                    for unit in String(scalar).utf16 {
                        out += String(format: "\\u%04x", unit)
                    }
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }
}

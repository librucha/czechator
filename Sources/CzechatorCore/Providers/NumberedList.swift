import Foundation

public enum NumberedListError: Error, Equatable {
    case countMismatch(expected: Int, got: Int)
    case badNumbering(atItem: Int)
    case unexpectedContinuation(afterItem: Int)
}

/// Wire format between the tool and the model. Items are escaped so a segment
/// containing a real newline cannot break the list structure.
public enum NumberedList {

    public static func encode(_ items: [String]) -> String {
        items.enumerated()
            .map { "\($0.offset + 1). \(escape($0.element))" }
            .joined(separator: "\n")
    }

    public static func decode(_ text: String, expectedCount: Int) throws -> [String] {
        var items: [String] = []

        // Split on any newline grapheme, mirroring `escape`: a model answering
        // with CRLF would otherwise come back as a single unparsable line.
        for line in text.split(whereSeparator: \.isNewline) {
            // Only the structural wrapper is trimmed; the item body is not,
            // so the model cannot smuggle whitespace changes through.
            let structural = line.trimmingCharacters(in: .whitespaces)
            if structural.isEmpty || structural.hasPrefix("```") { continue }

            guard let dot = line.firstIndex(of: "."),
                let number = Int(line[line.startIndex..<dot].trimmingCharacters(in: .whitespaces))
            else {
                // Before the first item this is a preamble the model tacked on.
                // After it, the model wrapped an item across lines — dropping
                // that line would silently truncate the text while the item
                // count still added up.
                if items.isEmpty { continue }
                throw NumberedListError.unexpectedContinuation(afterItem: items.count)
            }

            guard number == items.count + 1 else {
                throw NumberedListError.badNumbering(atItem: items.count + 1)
            }
            var body = line[line.index(after: dot)...]
            if body.hasPrefix(" ") { body = body.dropFirst() }
            items.append(unescape(body))
        }

        guard items.count == expectedCount else {
            throw NumberedListError.countMismatch(expected: expectedCount, got: items.count)
        }
        return items
    }

    private static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for character in s {
            switch character {
            case "\\": out += "\\\\"
            case "\t": out += "\\t"
            default:
                // CRLF is a single grapheme equal to neither "\n" nor "\r";
                // matching on those alone let a real line break into the wire
                // format and broke the numbered list.
                if character.isNewline {
                    out += character == "\r\n" ? "\\r\\n" : (character == "\r" ? "\\r" : "\\n")
                } else {
                    out.append(character)
                }
            }
        }
        return out
    }

    private static func unescape(_ s: Substring) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var index = s.startIndex

        while index < s.endIndex {
            guard s[index] == "\\", s.index(after: index) < s.endIndex else {
                out.append(s[index])
                index = s.index(after: index)
                continue
            }
            let next = s[s.index(after: index)]
            if next == "u" {
                let hexStart = s.index(index, offsetBy: 2)
                if let hexEnd = s.index(hexStart, offsetBy: 4, limitedBy: s.endIndex),
                    let value = UInt32(s[hexStart..<hexEnd], radix: 16),
                    let scalar = UnicodeScalar(value)
                {
                    out.append(Character(scalar))
                    index = hexEnd
                    continue
                }
            }
            switch next {
            case "n": out.append("\n")
            case "r": out.append("\r")
            case "t": out.append("\t")
            case "\\": out.append("\\")
            default:
                out.append(s[index])
                out.append(next)
            }
            index = s.index(index, offsetBy: 2)
        }
        return out
    }
}

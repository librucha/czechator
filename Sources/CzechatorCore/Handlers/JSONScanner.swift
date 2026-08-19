public struct JSONStringLiteral: Sendable, Equatable {
    /// Range of the content between the quotes, still escaped.
    public let contentRange: Range<String.Index>
    public let isKey: Bool
    /// Object key this value belongs to, if any. Array elements inherit the
    /// key of the array itself.
    public let parentKey: String?

    public init(contentRange: Range<String.Index>, isKey: Bool, parentKey: String?) {
        self.contentRange = contentRange
        self.isKey = isKey
        self.parentKey = parentKey
    }
}

public enum JSONScanError: Error, Equatable {
    case unexpectedCharacter(offset: Int)
    case unterminatedString(offset: Int)
    case trailingContent(offset: Int)
}

/// Hand-written scanner. JSONSerialization is unusable here because it loses
/// key order, indentation and formatting — the document could never be
/// reassembled byte-for-byte.
public enum JSONScanner {

    public static func scan(_ text: String) throws -> [JSONStringLiteral] {
        var parser = Parser(text: text)
        parser.skipWhitespace()
        try parser.parseValue(parentKey: nil)
        parser.skipWhitespace()
        guard parser.isAtEnd else { throw JSONScanError.trailingContent(offset: parser.offset) }
        return parser.literals
    }

    private struct Parser {
        let text: String
        var index: String.Index
        var literals: [JSONStringLiteral] = []

        init(text: String) {
            self.text = text
            self.index = text.startIndex
        }

        var isAtEnd: Bool { index >= text.endIndex }
        var current: Character? { isAtEnd ? nil : text[index] }
        var offset: Int { text.distance(from: text.startIndex, to: index) }

        mutating func advance() { index = text.index(after: index) }

        mutating func skipWhitespace() {
            // Character-based, so the CRLF grapheme is consumed too. Missing it
            // meant a Windows JSON file failed to scan and fell through to the
            // plain handler, where its keys and braces become correctable text.
            while let c = current, c.isWhitespace { advance() }
        }

        mutating func expect(_ character: Character) throws {
            guard current == character else {
                throw JSONScanError.unexpectedCharacter(offset: offset)
            }
            advance()
        }

        mutating func parseValue(parentKey: String?) throws {
            skipWhitespace()
            switch current {
            case "{": try parseObject()
            case "[": try parseArray(parentKey: parentKey)
            case "\"": _ = try parseString(isKey: false, parentKey: parentKey)
            case nil: throw JSONScanError.unexpectedCharacter(offset: offset)
            default: try parseBareLiteral()
            }
        }

        mutating func parseObject() throws {
            try expect("{")
            skipWhitespace()
            if current == "}" {
                advance()
                return
            }
            while true {
                skipWhitespace()
                guard current == "\"" else {
                    throw JSONScanError.unexpectedCharacter(offset: offset)
                }
                let key = try parseString(isKey: true, parentKey: nil)
                skipWhitespace()
                try expect(":")
                try parseValue(parentKey: key)
                skipWhitespace()
                if current == "," {
                    advance()
                    continue
                }
                try expect("}")
                return
            }
        }

        mutating func parseArray(parentKey: String?) throws {
            try expect("[")
            skipWhitespace()
            if current == "]" {
                advance()
                return
            }
            while true {
                try parseValue(parentKey: parentKey)
                skipWhitespace()
                if current == "," {
                    advance()
                    continue
                }
                try expect("]")
                return
            }
        }

        @discardableResult
        mutating func parseString(isKey: Bool, parentKey: String?) throws -> String {
            try expect("\"")
            let start = index
            while true {
                guard let character = current else {
                    throw JSONScanError.unterminatedString(offset: offset)
                }
                if character == "\\" {
                    advance()
                    guard let escape = current else {
                        throw JSONScanError.unterminatedString(offset: offset)
                    }
                    switch escape {
                    case "\"", "\\", "/", "b", "f", "n", "r", "t":
                        advance()
                    case "u":
                        advance()
                        for _ in 0..<4 {
                            guard let digit = current, digit.isHexDigit else {
                                throw JSONScanError.unexpectedCharacter(offset: offset)
                            }
                            advance()
                        }
                    default:
                        throw JSONScanError.unexpectedCharacter(offset: offset)
                    }
                    continue
                }
                if character == "\"" { break }
                advance()
            }
            let content = start..<index
            advance()
            literals.append(
                JSONStringLiteral(contentRange: content, isKey: isKey, parentKey: parentKey))
            return String(text[content])
        }

        /// Numbers, true, false, null — not segmented, but still validated, so
        /// text that merely looks like JSON does not win the format auction.
        mutating func parseBareLiteral() throws {
            let start = index
            let startOffset = offset
            while let character = current,
                character != ",", character != "]", character != "}", !character.isWhitespace
            { advance() }
            guard index > start else { throw JSONScanError.unexpectedCharacter(offset: offset) }

            let token = text[start..<index]
            guard token == "true" || token == "false" || token == "null"
                || Parser.isJSONNumber(token)
            else {
                throw JSONScanError.unexpectedCharacter(offset: startOffset)
            }
        }

        /// JSON number grammar: `-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?`.
        /// Deliberately not `Double(token)`, which also accepts hex floats,
        /// `infinity` and `nan`.
        static func isJSONNumber(_ token: Substring) -> Bool {
            var rest = Substring(token)
            if rest.hasPrefix("-") { rest = rest.dropFirst() }

            guard let first = rest.first, first.isNumber else { return false }
            if first == "0" {
                rest = rest.dropFirst()
            } else {
                rest = rest.drop { $0.isNumber }
            }

            if rest.hasPrefix(".") {
                rest = rest.dropFirst()
                let digits = rest.prefix { $0.isNumber }
                guard !digits.isEmpty else { return false }
                rest = rest.dropFirst(digits.count)
            }

            if rest.hasPrefix("e") || rest.hasPrefix("E") {
                rest = rest.dropFirst()
                if rest.hasPrefix("+") || rest.hasPrefix("-") { rest = rest.dropFirst() }
                let digits = rest.prefix { $0.isNumber }
                guard !digits.isEmpty else { return false }
                rest = rest.dropFirst(digits.count)
            }

            return rest.isEmpty
        }
    }
}

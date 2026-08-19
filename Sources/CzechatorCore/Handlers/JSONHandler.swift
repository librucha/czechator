import Foundation

public struct JSONHandler: FormatHandler {

    public static let id = "json"

    public static func confidence(for input: ClipboardInput) -> Double {
        let trimmed = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { return 0 }
        return (try? JSONScanner.scan(input.text)) != nil ? 0.9 : 0
    }

    private let rules: JSONRules
    private let builder: SegmentBuilder

    public init(rules: SegmentationRules) throws {
        self.rules = rules.json
        self.builder = try SegmentBuilder(common: rules.common)
    }

    public func segments(in text: String) throws -> [Segment] {
        let literals = try JSONScanner.scan(text)
        let prepared = builder.prepared(for: text)
        var result: [Segment] = []

        for literal in literals {
            if literal.isKey, rules.skipKeys { continue }
            if let key = literal.parentKey, rules.skipValuesForKeys.contains(key) { continue }
            result += prepared.build(candidate: literal.contentRange, kind: .jsonString) {
                JSONEscaping.unescape($0)
            }
        }
        return result
    }

    public func escape(_ corrected: String, like original: Segment) -> String {
        JSONEscaping.escape(corrected, style: .detect(in: original.raw))
    }
}

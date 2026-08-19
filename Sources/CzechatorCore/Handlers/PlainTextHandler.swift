/// Plain text and Markdown. Each line is its own candidate, which keeps
/// newlines outside segments and gives the batcher a natural granularity.
public struct PlainTextHandler: FormatHandler {

    public static let id = "plain"

    /// Constant low value: this is the fallback every other handler outbids.
    public static func confidence(for input: ClipboardInput) -> Double { 0.1 }

    private let builder: SegmentBuilder

    public init(rules: SegmentationRules) throws {
        builder = try SegmentBuilder(
            common: rules.common, extraSkipPatterns: rules.plain.skipPatterns)
    }

    public func segments(in text: String) throws -> [Segment] {
        let prepared = builder.prepared(for: text)
        var result: [Segment] = []
        var lineStart = text.startIndex
        var index = text.startIndex

        while index < text.endIndex {
            if text[index] == "\n" {
                result += prepared.build(candidate: lineStart..<index, kind: .plain) { String($0) }
                lineStart = text.index(after: index)
            }
            index = text.index(after: index)
        }
        result += prepared.build(candidate: lineStart..<text.endIndex, kind: .plain) { String($0) }
        return result
    }

    public func escape(_ corrected: String, like original: Segment) -> String { corrected }
}

public enum SegmentKind: String, Sendable, Codable, Equatable {
    case plain
    case jsonString
    case xmlText
    case htmlText
}

/// One correctable text node, located by its range in the original document.
///
/// Handlers never serialize anything — they only report ranges. Everything
/// outside those ranges is guaranteed to survive byte-for-byte.
public struct Segment: Sendable, Equatable {
    /// Range in the original document.
    public let range: Range<String.Index>
    /// Original source text at `range`, still escaped.
    public let raw: String
    /// Unescaped content handed to the model.
    public let text: String
    public let kind: SegmentKind

    public init(range: Range<String.Index>, raw: String, text: String, kind: SegmentKind) {
        self.range = range
        self.raw = raw
        self.text = text
        self.kind = kind
    }
}

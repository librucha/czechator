/// A format handler never serializes the document. It only reports the ranges
/// of correctable text nodes and knows how to escape a corrected string back
/// into the format's syntax.
public protocol FormatHandler: Sendable {
    static var id: String { get }

    /// 0.0 means "not my format". The registry picks the highest bidder.
    static func confidence(for input: ClipboardInput) -> Double

    func segments(in text: String) throws -> [Segment]

    /// Must satisfy `escape(unescape(raw), like: segment) == raw` for the
    /// formats' realistic inputs.
    ///
    /// Returns nil when a protected index did not survive the correction — see
    /// `protectedIndices(in:)`. Nothing is written in that case.
    func escape(_ corrected: String, like original: Segment, alignment: EditAlignment?) -> String?

    /// Grapheme indices in the segment's unescaped text that must survive a
    /// length-changing correction.
    ///
    /// An entity or an escape is replayed by position, so losing its slot moves
    /// it somewhere else in the document. Checking this at verification time
    /// rather than at escape time is what lets the retry branch have a go at it
    /// instead of failing the whole document outright.
    ///
    /// A requirement rather than only an extension member: the pipeline holds
    /// an `any FormatHandler`, and a method that lives solely in the extension
    /// is dispatched statically, so every handler's override would be skipped
    /// and every segment would report no protected indices at all.
    func protectedIndices(in segment: Segment) -> Set<Int>
}

extension FormatHandler {
    /// Formats with no escaping syntax of their own protect nothing.
    public func protectedIndices(in segment: Segment) -> Set<Int> { [] }
}

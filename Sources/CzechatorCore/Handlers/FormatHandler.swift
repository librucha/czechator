/// A format handler never serializes the document. It only reports the ranges
/// of correctable text nodes and knows how to escape a corrected string back
/// into the format's syntax.
public protocol FormatHandler: Sendable {
    static var id: String { get }

    /// 0.0 means "not my format". The registry picks the highest bidder.
    static func confidence(for input: ClipboardInput) -> Double

    func segments(in text: String) throws -> [Segment]

    /// Must satisfy `escape(unescape(raw), like: segment) == raw` for the
    /// formats' realistic inputs. Residual mismatches are caught by the
    /// verifier, which then refuses to write anything.
    func escape(_ corrected: String, like original: Segment) -> String
}

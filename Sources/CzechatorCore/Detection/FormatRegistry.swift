import Foundation

/// Picks the handler with the highest confidence. Ties are broken by
/// registration order, so `plain` — which always bids a constant 0.1 — only
/// wins when nobody else claims the input.
public struct FormatRegistry: Sendable {

    private struct Entry: Sendable {
        let id: String
        let confidence: @Sendable (ClipboardInput) -> Double
        let handler: any FormatHandler
    }

    private let entries: [Entry]

    public init(rules: SegmentationRules) throws {
        entries = [
            Entry(
                id: JSONHandler.id, confidence: JSONHandler.confidence,
                handler: try JSONHandler(rules: rules)),
            Entry(
                id: HTMLHandler.id, confidence: HTMLHandler.confidence,
                handler: try HTMLHandler(rules: rules)),
            Entry(
                id: XMLHandler.id, confidence: XMLHandler.confidence,
                handler: try XMLHandler(rules: rules)),
            Entry(
                id: PlainTextHandler.id, confidence: PlainTextHandler.confidence,
                handler: try PlainTextHandler(rules: rules)),
        ]
    }

    public var availableIDs: [String] { entries.map(\.id) }

    public func handler(id: String) -> (any FormatHandler)? {
        entries.first { $0.id == id }?.handler
    }

    /// Text that carries the signature of a structured document but that no
    /// structured handler could parse.
    ///
    /// Falling back to plain text here is not safe: the plain handler would
    /// treat `"nazev":` as correctable prose and the model would rename the key.
    /// `fold` cannot catch that — `fold("název") == fold("nazev")` — so the
    /// corruption would reach the clipboard silently. JSONC, a trailing comma,
    /// NDJSON and a truncated fragment all land here.
    ///
    /// The signature is a quoted key followed by a colon, not the first
    /// character: a leading comment pushes the brace off the front, while
    /// ordinary prose starting with `[` (a Markdown link, a citation) or `<`
    /// would be refused for no reason.
    public func looksStructuredButUnclaimed(_ input: ClipboardInput) -> Bool {
        guard select(input).id == PlainTextHandler.id else { return false }
        return Self.quotedKeyPattern.firstMatch(
            in: input.text, options: [],
            range: NSRange(input.text.startIndex..<input.text.endIndex, in: input.text)) != nil
    }

    /// A double-quoted string immediately followed by a colon — the one shape
    /// that means "this is a mapping", in JSON and every dialect of it.
    private static let quotedKeyPattern = try! NSRegularExpression(
        pattern: #""[^"\n]*"\s*:"#, options: [])

    public func select(_ input: ClipboardInput) -> (id: String, handler: any FormatHandler) {
        // Seeded with the last entry, which is the plain-text fallback.
        var best = entries[entries.count - 1]
        var bestScore = best.confidence(input)
        for entry in entries {
            let score = entry.confidence(input)
            if score > bestScore {
                best = entry
                bestScore = score
            }
        }
        return (best.id, best.handler)
    }
}

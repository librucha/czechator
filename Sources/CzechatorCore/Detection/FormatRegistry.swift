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
    /// treat `"nazev":` or `slozka = "data"` as correctable prose and the model
    /// would rename it. `fold` cannot catch that — `fold("název") ==
    /// fold("nazev")` — so the corruption would reach the clipboard silently.
    ///
    /// Refusing is the honest answer. The alternative, skipping key-shaped
    /// tokens inside plain text, was tried and made things worse: cutting
    /// `Poznamka:` out of a sentence left the model a fragment it capitalized,
    /// which failed verification for the whole document.
    public func looksStructuredButUnclaimed(_ input: ClipboardInput) -> Bool {
        guard select(input).id == PlainTextHandler.id else { return false }
        return Self.hasMappingSignature(input.text)
    }

    /// A quoted key followed by a colon, at the start of a line or right after
    /// `{` or `,` — the shape of a JSON mapping. The position matters: without
    /// it, a sentence like `Kniha "Osud": recenze vysla vcera` reads as JSON.
    private static let jsonKeyPattern = try! NSRegularExpression(
        pattern: #"(?:^|[{,])[ \t]*"[^"\n]*"[ \t]*:"#, options: [.anchorsMatchLines])

    /// A line that is nothing but `[section]` — TOML and INI. Prose does not do
    /// this; a Markdown link or a citation always has text around the bracket.
    private static let sectionPattern = try! NSRegularExpression(
        pattern: #"^[ \t]*\[{1,2}[^\]\n]+\]{1,2}[ \t]*$"#, options: [.anchorsMatchLines])

    /// A YAML list item whose element is a mapping: `- jmeno: Petr`.
    private static let yamlItemPattern = try! NSRegularExpression(
        pattern: #"^[ \t]*-[ \t]+[A-Za-z_][A-Za-z0-9_.\-]*[ \t]*:"#, options: [.anchorsMatchLines])

    /// `key = value` or `key: value` at the start of a line.
    private static let keyValuePattern = try! NSRegularExpression(
        pattern: #"^[ \t]*"?[A-Za-z_][A-Za-z0-9_.\- ]*"?[ \t]*[:=][ \t]*\S"#,
        options: [.anchorsMatchLines])

    static func hasMappingSignature(_ text: String) -> Bool {
        let whole = NSRange(text.startIndex..<text.endIndex, in: text)
        func matches(_ regex: NSRegularExpression) -> Int {
            regex.numberOfMatches(in: text, options: [], range: whole)
        }

        // Signatures prose does not produce at all.
        if matches(jsonKeyPattern) > 0 { return true }
        if matches(sectionPattern) > 0 { return true }
        if matches(yamlItemPattern) > 0 { return true }

        // A run of `key = value` lines. Two discriminators keep prose out: a
        // note has at most a line or two of them among other text, and its
        // values are sentences, which end in sentence punctuation.
        let lines = text.split(whereSeparator: \.isNewline).filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard lines.count >= 2 else { return false }

        let keyValueLines = lines.filter { line in
            // Indices must come from the very String being searched.
            let text = String(line)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return keyValuePattern.firstMatch(in: text, options: [], range: range) != nil
        }
        guard keyValueLines.count >= 2, keyValueLines.count * 2 >= lines.count else { return false }

        let sentenceLike = keyValueLines.filter {
            let last = $0.trimmingCharacters(in: .whitespaces).last
            return last == "." || last == "!" || last == "?"
        }
        return sentenceLike.count * 2 < keyValueLines.count
    }

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

import Foundation

public struct HTMLHandler: FormatHandler {

    public static let id = "html"

    /// Element names that only appear in HTML.
    ///
    /// Deliberately excludes `a`, `b` and `i`: they are plausible element names
    /// in hand-written XML, and claiming them would steal XML documents. A bare
    /// anchor fragment therefore loses to XML — acceptable, because anything
    /// copied from a browser arrives with the `public.html` UTI anyway.
    private static let signatureElements: Set<String> = [
        "html", "head", "body", "div", "span", "p", "br", "hr", "img",
        "ul", "ol", "li", "table", "thead", "tbody", "tr", "td", "th",
        "h1", "h2", "h3", "h4", "h5", "h6", "em", "strong", "script", "style",
        "form", "input", "button", "select", "option", "textarea", "iframe",
        "nav", "header", "footer", "section", "article", "aside", "main",
        "figure", "figcaption", "blockquote", "picture", "video", "audio",
    ]

    public static func confidence(for input: ClipboardInput) -> Double {
        if input.uti == "public.html" { return 1.0 }
        if input.text.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().hasPrefix("<!doctype html")
        {
            return 0.95
        }
        // Match parsed element names, not substrings: prose that mentions
        // "<br" without ever closing a tag must not read as HTML.
        let names = MarkupScanner.elementNames(in: input.text)
        return names.contains(where: signatureElements.contains) ? 0.75 : 0
    }

    private let options: MarkupScanOptions
    private let builder: SegmentBuilder

    public init(rules: SegmentationRules) throws {
        options = MarkupScanOptions(
            skipElements: Set(rules.html.skipElements.map { $0.lowercased() }),
            skipComments: rules.html.skipComments,
            skipProcessingInstructions: true,
            skipCDATA: true,
            includeAttributeValues: !rules.html.skipAttributes,
            voidElements: MarkupScanOptions.htmlVoidElements
        )
        builder = try SegmentBuilder(common: rules.common)
    }

    public func segments(in text: String) throws -> [Segment] {
        let prepared = builder.prepared(for: text)
        return MarkupScanner.scan(text, options: options).flatMap { node in
            prepared.build(candidate: node.range, kind: .htmlText) {
                MarkupEntities.unescape($0, table: MarkupEntities.htmlTable)
            }
        }
    }

    public func escape(_ corrected: String, like original: Segment) -> String {
        MarkupEntities.escape(
            corrected, style: .detect(in: original.raw, table: MarkupEntities.htmlTable))
    }
}

import Foundation

public struct HTMLHandler: FormatHandler {

    public static let id = "html"

    /// Element names that mark a document as HTML rather than generic XML.
    private static let markers = [
        "<html", "<div", "<span", "<body", "<p>", "<p ", "<br", "<ul", "<table",
    ]

    public static func confidence(for input: ClipboardInput) -> Double {
        if input.uti == "public.html" { return 1.0 }
        let lowered = input.text.lowercased()
        return markers.contains(where: lowered.contains) ? 0.75 : 0
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

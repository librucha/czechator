import Foundation

public struct XMLHandler: FormatHandler {

    public static let id = "xml"

    public static func confidence(for input: ClipboardInput) -> Double {
        if input.uti == "public.xml" { return 0.95 }
        let trimmed = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<?xml") { return 0.95 }
        return MarkupScanner.looksLikeMarkup(trimmed) ? 0.6 : 0
    }

    private let options: MarkupScanOptions
    private let builder: SegmentBuilder

    public init(rules: SegmentationRules) throws {
        options = MarkupScanOptions(
            skipElements: Set(rules.xml.skipElements.map { $0.lowercased() }),
            skipComments: rules.xml.skipComments,
            skipProcessingInstructions: rules.xml.skipProcessingInstructions,
            skipCDATA: rules.xml.skipCDATA,
            includeAttributeValues: !rules.xml.skipAttributes,
            voidElements: []
        )
        builder = try SegmentBuilder(common: rules.common)
    }

    public func segments(in text: String) throws -> [Segment] {
        let prepared = builder.prepared(for: text)
        return MarkupScanner.scan(text, options: options).flatMap { node in
            prepared.build(candidate: node.range, kind: .xmlText) {
                MarkupEntities.unescape($0, table: MarkupEntities.xmlTable)
            }
        }
    }

    public func escape(_ corrected: String, like original: Segment) -> String {
        MarkupEntities.escape(
            corrected, style: .detect(in: original.raw, table: MarkupEntities.xmlTable))
    }
}

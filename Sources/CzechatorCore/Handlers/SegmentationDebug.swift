import Foundation

public struct ExcludedSpan: Sendable, Equatable {
    public let pattern: String
    public let text: String
    public let offset: Int

    public init(pattern: String, text: String, offset: Int) {
        self.pattern = pattern
        self.text = text
        self.offset = offset
    }
}

/// Support for `czechator segments`. Tuning the skip rules is an empirical
/// loop, so it has to be possible to see what a rule actually removed without
/// rebuilding anything.
public enum SegmentationDebug {

    public static func patterns(rules: SegmentationRules, formatID: String) -> [String] {
        rules.common.skipPatterns
            + (formatID == PlainTextHandler.id ? rules.plain.skipPatterns : [])
    }

    /// Ranges the patterns are actually allowed to match in, mirroring the
    /// scope each handler uses. Reporting document-wide matches would show
    /// spans that never fire — a debug view that lies is worse than none.
    static func scopes(in text: String, rules: SegmentationRules, formatID: String)
        -> [Range<String.Index>]
    {
        switch formatID {
        case JSONHandler.id:
            guard let literals = try? JSONScanner.scan(text) else {
                return [text.startIndex..<text.endIndex]
            }
            return
                literals
                .filter { literal in
                    if literal.isKey, rules.json.skipKeys { return false }
                    // Values the rules drop wholesale are never scanned by the
                    // handler either; reporting a pattern match inside one would
                    // give the wrong reason for a missing segment.
                    if let key = literal.parentKey, rules.json.skipValuesForKeys.contains(key) {
                        return false
                    }
                    return true
                }
                .map(\.contentRange)

        case XMLHandler.id:
            let options = MarkupScanOptions(
                skipElements: Set(rules.xml.skipElements.map { $0.lowercased() }),
                skipComments: rules.xml.skipComments,
                skipProcessingInstructions: rules.xml.skipProcessingInstructions,
                skipCDATA: rules.xml.skipCDATA,
                includeAttributeValues: !rules.xml.skipAttributes,
                voidElements: [])
            return MarkupScanner.scan(text, options: options).map(\.range)

        case HTMLHandler.id:
            let options = MarkupScanOptions(
                skipElements: Set(rules.html.skipElements.map { $0.lowercased() }),
                skipComments: rules.html.skipComments,
                skipProcessingInstructions: true,
                skipCDATA: true,
                includeAttributeValues: !rules.html.skipAttributes,
                voidElements: MarkupScanOptions.htmlVoidElements)
            return MarkupScanner.scan(text, options: options).map(\.range)

        default:
            return [text.startIndex..<text.endIndex]
        }
    }

    public static func excludedSpans(
        in text: String, rules: SegmentationRules, formatID: String
    ) throws -> [ExcludedSpan] {
        var spans: [ExcludedSpan] = []
        let ranges = scopes(in: text, rules: rules, formatID: formatID)

        for pattern in patterns(rules: rules, formatID: formatID) {
            let regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
            for scope in ranges {
                for match in regex.matches(
                    in: text, options: [], range: NSRange(scope, in: text))
                {
                    guard let range = Range(match.range, in: text), !range.isEmpty else { continue }
                    spans.append(
                        ExcludedSpan(
                            pattern: pattern,
                            text: String(text[range]),
                            offset: text.distance(from: text.startIndex, to: range.lowerBound)))
                }
            }
        }
        return spans.sorted { $0.offset < $1.offset }
    }

    public static func activeRuleSummary(rules: SegmentationRules, formatID: String) -> [String] {
        var lines = [
            "common.minLength = \(rules.common.minLength)",
            "common.requireLetters = \(rules.common.requireLetters)",
            "common.skipPatterns = \(rules.common.skipPatterns)",
        ]
        switch formatID {
        case JSONHandler.id:
            lines.append("json.skipKeys = \(rules.json.skipKeys)")
            lines.append("json.skipValuesForKeys = \(rules.json.skipValuesForKeys)")
        case HTMLHandler.id:
            lines.append("html.skipElements = \(rules.html.skipElements)")
            lines.append("html.skipAttributes = \(rules.html.skipAttributes)")
            lines.append("html.skipComments = \(rules.html.skipComments)")
        case XMLHandler.id:
            lines.append("xml.skipElements = \(rules.xml.skipElements)")
            lines.append("xml.skipAttributes = \(rules.xml.skipAttributes)")
            lines.append("xml.skipComments = \(rules.xml.skipComments)")
            lines.append("xml.skipProcessingInstructions = \(rules.xml.skipProcessingInstructions)")
            lines.append("xml.skipCDATA = \(rules.xml.skipCDATA)")
        default:
            lines.append("plain.skipPatterns = \(rules.plain.skipPatterns)")
        }
        return lines
    }
}

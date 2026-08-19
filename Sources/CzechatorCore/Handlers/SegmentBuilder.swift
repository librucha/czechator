import Foundation

/// Shared segmentation mechanics: excluded spans, whitespace trimming,
/// length and letter filters. Handlers only decide *where* the candidate
/// ranges are; everything else happens here so the rules apply uniformly.
///
/// `@unchecked Sendable`: NSRegularExpression is documented as thread-safe
/// and the array is never mutated after init.
public struct SegmentBuilder: @unchecked Sendable {

    private let minLength: Int
    private let requireLetters: Bool
    private let regexes: [NSRegularExpression]

    public init(common: CommonRules, extraSkipPatterns: [String] = []) throws {
        minLength = common.minLength
        requireLetters = common.requireLetters
        regexes = try (common.skipPatterns + extraSkipPatterns).map {
            try NSRegularExpression(pattern: $0, options: [.anchorsMatchLines])
        }
    }

    /// Computes the excluded spans once for the whole document, so multi-line
    /// patterns (fenced code blocks) work even when candidates are single lines.
    public func prepared(for text: String) -> PreparedSegmenter {
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        var spans: [Range<String.Index>] = []
        for regex in regexes {
            for match in regex.matches(in: text, options: [], range: full) {
                if let range = Range(match.range, in: text), !range.isEmpty {
                    spans.append(range)
                }
            }
        }
        return PreparedSegmenter(text: text,
                                 excludedSpans: PreparedSegmenter.merge(spans),
                                 minLength: minLength,
                                 requireLetters: requireLetters)
    }
}

public struct PreparedSegmenter: Sendable {

    public let text: String
    public let excludedSpans: [Range<String.Index>]
    public let minLength: Int
    public let requireLetters: Bool

    /// Splits `candidate` around the excluded spans, trims and filters the
    /// remaining pieces, and turns each into a `Segment`.
    public func build(candidate: Range<String.Index>,
                      kind: SegmentKind,
                      unescape: (Substring) -> String) -> [Segment] {
        var pieces: [Range<String.Index>] = []
        var cursor = candidate.lowerBound

        for span in excludedSpans
        where span.upperBound > candidate.lowerBound && span.lowerBound < candidate.upperBound {
            let lower = Swift.max(span.lowerBound, candidate.lowerBound)
            if lower > cursor { pieces.append(cursor..<lower) }
            cursor = Swift.max(cursor, Swift.min(span.upperBound, candidate.upperBound))
        }
        if cursor < candidate.upperBound { pieces.append(cursor..<candidate.upperBound) }

        return pieces.compactMap { piece in
            guard let trimmed = trim(piece) else { return nil }
            let body = text[trimmed]
            guard body.count >= minLength else { return nil }
            if requireLetters, !body.contains(where: { $0.isLetter }) { return nil }
            return Segment(range: trimmed, raw: String(body), text: unescape(body), kind: kind)
        }
    }

    /// Whitespace stays outside segments so the model cannot swallow it.
    private func trim(_ range: Range<String.Index>) -> Range<String.Index>? {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, text[lower].isWhitespace { lower = text.index(after: lower) }
        while upper > lower, text[text.index(before: upper)].isWhitespace {
            upper = text.index(before: upper)
        }
        return lower < upper ? lower..<upper : nil
    }

    static func merge(_ spans: [Range<String.Index>]) -> [Range<String.Index>] {
        let sorted = spans.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for span in sorted {
            if let last = merged.last, span.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<Swift.max(last.upperBound, span.upperBound)
            } else {
                merged.append(span)
            }
        }
        return merged
    }
}

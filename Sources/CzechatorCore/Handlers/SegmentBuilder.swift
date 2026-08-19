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

    /// Where a skip pattern is allowed to match.
    public enum PatternScope: Sendable {
        /// Across the whole document, so multi-line patterns (fenced code
        /// blocks) work even when candidates are single lines. Correct only
        /// when nothing but whitespace separates candidates.
        case document
        /// Confined to one candidate. Structured formats need this: a greedy
        /// `\S+` in a URL pattern would otherwise run past a closing quote or
        /// tag and silently swallow text belonging to the next node.
        case candidate
    }

    /// Computes the excluded spans once for the whole document, so multi-line
    /// patterns (fenced code blocks) work even when candidates are single lines.
    public func prepared(for text: String, scope: PatternScope = .document) -> PreparedSegmenter {
        let documentSpans: [Range<String.Index>]
        switch scope {
        case .document:
            documentSpans = PreparedSegmenter.merge(Self.matches(of: regexes, in: text, range: text.startIndex..<text.endIndex))
        case .candidate:
            documentSpans = []
        }
        return PreparedSegmenter(text: text,
                                 excludedSpans: documentSpans,
                                 scope: scope,
                                 regexes: regexes,
                                 minLength: minLength,
                                 requireLetters: requireLetters)
    }

    static func matches(of regexes: [NSRegularExpression],
                        in text: String,
                        range: Range<String.Index>) -> [Range<String.Index>] {
        let nsRange = NSRange(range, in: text)
        var spans: [Range<String.Index>] = []
        for regex in regexes {
            for match in regex.matches(in: text, options: [], range: nsRange) {
                if let found = Range(match.range, in: text), !found.isEmpty {
                    spans.append(found)
                }
            }
        }
        return spans
    }
}

/// `@unchecked Sendable`: NSRegularExpression is documented as thread-safe and
/// the array is never mutated after init.
public struct PreparedSegmenter: @unchecked Sendable {

    public let text: String
    /// Internal on purpose: it is populated only in `.document` scope, and a
    /// public field that silently reads empty for three of the four handlers is
    /// a trap for anyone building on it.
    let excludedSpans: [Range<String.Index>]
    let scope: SegmentBuilder.PatternScope
    let regexes: [NSRegularExpression]
    public let minLength: Int
    public let requireLetters: Bool

    /// Splits `candidate` around the excluded spans, trims and filters the
    /// remaining pieces, and turns each into a `Segment`.
    public func build(candidate: Range<String.Index>,
                      kind: SegmentKind,
                      unescape: (Substring) -> String) -> [Segment] {
        let spans: [Range<String.Index>]
        switch scope {
        case .document:
            spans = excludedSpans
        case .candidate:
            spans = PreparedSegmenter.merge(
                SegmentBuilder.matches(of: regexes, in: text, range: candidate))
        }

        var pieces: [Range<String.Index>] = []
        var cursor = candidate.lowerBound

        for span in spans
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

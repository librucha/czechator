public enum ReassemblyError: Error, Equatable {
    case countMismatch(expected: Int, got: Int)
    case overlappingRanges
}

public enum Reassembler {

    /// Rebuilds the document by walking it forward and swapping each segment's
    /// range for its replacement. Builds a new string rather than mutating in
    /// place, because String indices are not guaranteed to stay valid across
    /// mutations of the same value.
    public static func splice(
        _ original: String,
        segments: [Segment],
        replacements: [String]
    ) throws -> String {
        guard segments.count == replacements.count else {
            throw ReassemblyError.countMismatch(expected: segments.count, got: replacements.count)
        }

        let pairs = zip(segments, replacements)
            .sorted { $0.0.range.lowerBound < $1.0.range.lowerBound }

        var out = ""
        out.reserveCapacity(original.count)
        var cursor = original.startIndex

        for (segment, replacement) in pairs {
            guard segment.range.lowerBound >= cursor else {
                throw ReassemblyError.overlappingRanges
            }
            out += original[cursor..<segment.range.lowerBound]
            out += replacement
            cursor = segment.range.upperBound
        }
        out += original[cursor...]
        return out
    }
}

public enum SegmentBatcher {

    /// Greedy packing by character count. Returns indices into `segments` so the
    /// caller can map results back without rebuilding the segment list.
    ///
    /// A single segment larger than `maxChars` still gets its own batch — the
    /// alternative would be splitting it, which would break reassembly.
    public static func batches(_ segments: [Segment], maxChars: Int) -> [[Int]] {
        var result: [[Int]] = []
        var current: [Int] = []
        var currentSize = 0

        for (index, segment) in segments.enumerated() {
            let size = segment.text.count
            if !current.isEmpty, currentSize + size > maxChars {
                result.append(current)
                current = []
                currentSize = 0
            }
            current.append(index)
            currentSize += size
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

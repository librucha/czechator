/// Optimal string alignment — Damerau-Levenshtein without repeated edits —
/// between two grapheme arrays.
///
/// One DP table serves three callers: the verifier's per-word budget, the
/// attribution of each edit to the word it landed in, and the index remapping
/// that puts entities, JSON escapes and non-breaking spaces back after a
/// correction that changed the length.
public struct EditAlignment: Sendable, Equatable {
    public let distance: Int
    /// Old grapheme index -> new grapheme index. A missing key means that
    /// grapheme was deleted and has nowhere to go.
    public let map: [Int: Int]
    /// Index in the ORIGINAL where each edit applies, ascending. An insertion
    /// is attributed to the grapheme it follows, or to index 0 at the start.
    public let editPositions: [Int]

    public init(distance: Int, map: [Int: Int], editPositions: [Int]) {
        self.distance = distance
        self.map = map
        self.editPositions = editPositions
    }

    /// Returns nil when either side is longer than `limit`: the table is
    /// O(n*m) and a paragraph that size is not worth aligning. Callers fall
    /// back to a strict comparison.
    public static func compute(
        _ a: [Character], _ b: [Character], limit: Int = 2_000
    ) -> EditAlignment? {
        guard a.count <= limit, b.count <= limit else { return nil }
        let n = a.count
        let m = b.count

        var d = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { d[i][0] = i }
        for j in 0...m { d[0][j] = j }

        if n > 0, m > 0 {
            for i in 1...n {
                for j in 1...m {
                    var best = Swift.min(d[i - 1][j] + 1, d[i][j - 1] + 1)
                    best = Swift.min(best, d[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                    // The transposition rule. Without it two swapped letters
                    // cost 2 and the commonest typo of all falls outside a
                    // budget of 1.
                    if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                        best = Swift.min(best, d[i - 2][j - 2] + 1)
                    }
                    d[i][j] = best
                }
            }
        }

        var map: [Int: Int] = [:]
        var edits: [Int] = []
        var i = n
        var j = m

        while i > 0 || j > 0 {
            if i > 0, j > 0, a[i - 1] == b[j - 1], d[i][j] == d[i - 1][j - 1] {
                map[i - 1] = j - 1
                i -= 1
                j -= 1
            } else if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1],
                d[i][j] == d[i - 2][j - 2] + 1
            {
                map[i - 1] = j - 2
                map[i - 2] = j - 1
                edits.append(i - 2)
                i -= 2
                j -= 2
            } else if i > 0, j > 0, d[i][j] == d[i - 1][j - 1] + 1 {
                map[i - 1] = j - 1
                edits.append(i - 1)
                i -= 1
                j -= 1
            } else if i > 0, d[i][j] == d[i - 1][j] + 1 {
                edits.append(i - 1)
                i -= 1
            } else {
                edits.append(Swift.max(0, i - 1))
                j -= 1
            }
        }

        return EditAlignment(
            distance: d[n][m], map: map, editPositions: Array(edits.reversed()))
    }
}

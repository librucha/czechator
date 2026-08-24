/// How many edits one word of a segment may absorb.
///
/// Per word rather than per segment: a segment-wide budget grows with length,
/// so a 300-character paragraph would be allowed enough edits to rewrite a
/// whole sentence. A per-word budget bounds the damage locally and does not
/// inflate with the size of the paragraph it sits in.
///
/// Clamped on every write rather than at validation time, matching
/// TriggerConfig.intervalMs: a hand-edited config must never reach a state the
/// code does not expect.
public struct EditBudget: Sendable, Codable, Equatable {
    public var percent: Int { didSet { percent = percent.clamped(to: Self.percentRange) } }
    public var minimum: Int { didSet { minimum = minimum.clamped(to: Self.minimumRange) } }

    static let percentRange = 0...100
    static let minimumRange = 0...5

    /// Verified against real examples rather than guessed: `bil`->`byl`,
    /// `kndeliky`->`knedliky` and a missing comma each land exactly on the
    /// allowance, not comfortably inside it.
    public static let builtIn = EditBudget(percent: 20, minimum: 1)

    /// `didSet` does not fire during initialisation, so this clamps explicitly
    /// — exactly as TriggerConfig.init does, and for the same reason: a value
    /// built in code must not get past a range a decoded one could not.
    public init(percent: Int, minimum: Int) {
        self.percent = percent.clamped(to: Self.percentRange)
        self.minimum = minimum.clamped(to: Self.minimumRange)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = EditBudget.builtIn
        self.init(
            percent: try container.decodeIfPresent(Int.self, forKey: .percent)
                ?? defaults.percent,
            minimum: try container.decodeIfPresent(Int.self, forKey: .minimum)
                ?? defaults.minimum)
    }

    /// Integer arithmetic, floored.
    public func allowance(forWordOfLength n: Int) -> Int {
        Swift.max(minimum, (n * percent) / 100)
    }
}

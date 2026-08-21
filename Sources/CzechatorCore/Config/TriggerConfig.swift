public enum TriggerKind: String, Sendable, Codable, Equatable, CaseIterable {
    case combination
    case doubleTap
}

/// How the user starts a correction.
///
/// The default is `combination`, and it has to stay that way: the config file
/// is materialized on first run and from then on overrides the built-in values,
/// so a new default would never reach an existing installation — but a changed
/// one would surprise everyone who upgrades.
public struct TriggerConfig: Sendable, Codable, Equatable {
    public var kind: TriggerKind
    public var modifier: ModifierKey
    /// Milliseconds allowed between the first release and the second press.
    ///
    /// Clamped on every write, not only in the initialiser: the settings window
    /// binds straight to this, and a range enforced in one place only is a
    /// range that holds until someone finds the other way in.
    public var intervalMs: Int {
        didSet { intervalMs = intervalMs.clamped(to: Self.allowedMs) }
    }
    /// Milliseconds a tap may last before it counts as holding the key.
    public var maxHoldMs: Int {
        didSet { maxHoldMs = maxHoldMs.clamped(to: Self.allowedMs) }
    }
    /// Logs every modifier event with its key code.
    ///
    /// Lives in the config rather than only in an environment variable because
    /// an app launched from the Dock or Finder never sees the environment the
    /// user set it in — which made the variable useless for the one case it
    /// existed to diagnose.
    public var debug: Bool

    /// A hand-edited config can hold nonsense: 0 ms would make every press a
    /// double tap, and 10 s would make the trigger feel broken.
    static let allowedMs = 10...2000

    public static let builtIn = TriggerConfig(
        kind: .combination, modifier: .rightCommand, intervalMs: 300, maxHoldMs: 500,
        debug: false)

    /// Clamps here rather than only in `init(from:)`, so a value constructed in
    /// code cannot get past the range a decoded one could not.
    public init(
        kind: TriggerKind, modifier: ModifierKey, intervalMs: Int, maxHoldMs: Int,
        debug: Bool = false
    ) {
        self.kind = kind
        self.modifier = modifier
        self.intervalMs = intervalMs.clamped(to: Self.allowedMs)
        self.maxHoldMs = maxHoldMs.clamped(to: Self.allowedMs)
        self.debug = debug
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = TriggerConfig.builtIn
        self.init(
            kind: try container.decodeIfPresent(TriggerKind.self, forKey: .kind) ?? defaults.kind,
            modifier: try container.decodeIfPresent(ModifierKey.self, forKey: .modifier)
                ?? defaults.modifier,
            intervalMs: try container.decodeIfPresent(Int.self, forKey: .intervalMs)
                ?? defaults.intervalMs,
            maxHoldMs: try container.decodeIfPresent(Int.self, forKey: .maxHoldMs)
                ?? defaults.maxHoldMs,
            debug: try container.decodeIfPresent(Bool.self, forKey: .debug) ?? defaults.debug)
    }
}

extension Int {
    fileprivate func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

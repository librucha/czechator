import Foundation

public enum DoubleTapEvent: Sendable, Equatable {
    case modifierPressed(ModifierKey)
    case modifierReleased(ModifierKey)
    /// Any non-modifier key went down — the user was typing a shortcut.
    case otherKeyDown
    /// A different modifier joined or left.
    case otherModifierChanged
}

/// Decides whether a sequence of modifier events is a deliberate double tap.
///
/// Pure logic on purpose: no AppKit, no clock, no permission. The time comes in
/// from the caller, which is what makes this testable without sleeping — the
/// same reason `Pipeline` takes its provider from outside.
///
/// The thresholds are deliberately strict. A false trigger touches the
/// clipboard when the user did not ask for it, which is worse than a tap that
/// did not register.
public struct DoubleTapDetector: Sendable {

    private enum State: Sendable {
        case idle
        /// The modifier is down; `since` is when it went down.
        case pressed(since: TimeInterval, spoiled: Bool)
        /// One clean tap is complete; `endedAt` is when it was released.
        case awaitingSecond(endedAt: TimeInterval)
        /// The modifier is down for what may be the second tap.
        case secondPressed(since: TimeInterval, spoiled: Bool)
    }

    private let modifier: ModifierKey
    private let interval: TimeInterval
    private let maxHold: TimeInterval
    private var state: State = .idle

    public init(modifier: ModifierKey, intervalMs: Int, maxHoldMs: Int) {
        self.modifier = modifier
        self.interval = TimeInterval(intervalMs) / 1000
        self.maxHold = TimeInterval(maxHoldMs) / 1000
    }

    /// Returns true exactly once, on the release that completes a double tap.
    public mutating func accept(_ event: DoubleTapEvent, at time: TimeInterval) -> Bool {
        switch event {
        case .otherKeyDown, .otherModifierChanged:
            spoil()
            return false

        case .modifierPressed(let key):
            guard key == modifier else {
                state = .idle
                return false
            }
            switch state {
            case .awaitingSecond(let endedAt) where time - endedAt <= interval:
                state = .secondPressed(since: time, spoiled: false)
            case .pressed, .secondPressed:
                // A press with no matching release behind it: the state is not
                // what it claims to be, so start over rather than guess.
                state = .idle
            default:
                state = .pressed(since: time, spoiled: false)
            }
            return false

        case .modifierReleased(let key):
            guard key == modifier else {
                state = .idle
                return false
            }
            switch state {
            case .pressed(let since, let spoiled):
                state =
                    (spoiled || time - since > maxHold)
                    ? .idle
                    : .awaitingSecond(endedAt: time)
                return false

            case .secondPressed(let since, let spoiled):
                let clean = !spoiled && time - since <= maxHold
                state = .idle
                return clean

            case .idle, .awaitingSecond:
                // A release with nothing to close.
                state = .idle
                return false
            }
        }
    }

    /// Marks the tap in progress as unusable without forgetting that the
    /// modifier is still physically down.
    private mutating func spoil() {
        switch state {
        case .pressed(let since, _):
            state = .pressed(since: since, spoiled: true)
        case .secondPressed(let since, _):
            state = .secondPressed(since: since, spoiled: true)
        case .idle, .awaitingSecond:
            state = .idle
        }
    }
}

import AppKit
import CzechatorCore
import Foundation

/// Watches modifier keys and fires on a deliberate double tap.
///
/// A passive `NSEvent` monitor, not a `CGEventTap`: the tap's one advantage is
/// swallowing events, and swallowing is exactly what must not happen here — a
/// single press has to reach whatever application the user is in. The tap also
/// gets disabled by the system on a slow handler, which would make the trigger
/// die quietly.
@MainActor
final class DoubleTapMonitor: Trigger {

    enum MonitorError: Error, Equatable {
        case accessibilityDenied
    }

    private let modifier: ModifierKey
    private let debug: Bool
    private var detector: DoubleTapDetector
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var action: (@MainActor () -> Void)?

    init(modifier: ModifierKey, intervalMs: Int, maxHoldMs: Int, debug: Bool = false) {
        self.modifier = modifier
        self.debug = debug
        self.detector = DoubleTapDetector(
            modifier: modifier, intervalMs: intervalMs, maxHoldMs: maxHoldMs)
    }

    func start(_ action: @escaping @MainActor () -> Void) throws {
        stop()
        guard AccessibilityPermission.isGranted else { throw MonitorError.accessibilityDenied }
        self.action = action

        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        // A global monitor sees nothing while this app is frontmost, which
        // happens whenever the settings window is open.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        action = nil
    }

    private func handle(_ event: NSEvent) {
        guard let translated = Self.translate(event, watching: modifier) else { return }
        if debug {
            FileHandle.standardError.write(
                Data("czechator: keyCode=\(event.keyCode) → \(translated)\n".utf8))
        }
        if detector.accept(translated, at: event.timestamp) {
            action?()
        }
    }

    /// Turns an AppKit event into the vocabulary the detector understands.
    static func translate(_ event: NSEvent, watching modifier: ModifierKey) -> DoubleTapEvent? {
        switch event.type {
        case .keyDown:
            return .otherKeyDown
        case .flagsChanged:
            guard let key = ModifierKey.from(keyCode: Int(event.keyCode)) else {
                return .otherModifierChanged
            }
            guard key == modifier else { return .otherModifierChanged }
            // flagsChanged carries no up/down flag; the modifier is down when
            // its own flag is still set in the event. With both keys of a pair
            // held the flag outlives the first release, so that release reads
            // as a press — which the detector discards as an impossible
            // sequence. Failing closed is the right side to err on.
            let isDown = event.modifierFlags.contains(modifier.flag)
            return isDown ? .modifierPressed(key) : .modifierReleased(key)
        default:
            return nil
        }
    }
}

extension ModifierKey {
    /// The flag that is set while this key is physically down.
    var flag: NSEvent.ModifierFlags {
        switch self {
        case .rightCommand, .leftCommand: return .command
        case .rightOption, .leftOption: return .option
        }
    }
}

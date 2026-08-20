import CzechatorCore

/// What starts a correction.
///
/// Both implementations end in the same `AppModel.run()`, so nothing behind
/// this protocol knows which one is active — otherwise swapping the trigger
/// would leak through the whole application.
@MainActor
protocol Trigger: AnyObject {
    func start(_ action: @escaping @MainActor () -> Void) throws
    func stop()
}

/// What `AppModel` decided to install, before anything system-wide happens.
///
/// Separating the decision from the installation is what lets the choice be
/// tested: the rules for picking a trigger are ordinary logic, while creating
/// one registers a global hotkey or opens an event monitor.
enum TriggerPlan: Equatable {
    case combination(ShortcutSpec)
    case doubleTap(TriggerConfig)
}

@MainActor
func makeLiveTrigger(_ plan: TriggerPlan) -> any Trigger {
    switch plan {
    case .combination(let spec):
        return HotKeyManager(spec: spec)
    case .doubleTap(let config):
        return DoubleTapMonitor(
            modifier: config.modifier, intervalMs: config.intervalMs,
            maxHoldMs: config.maxHoldMs, debug: config.debug)
    }
}

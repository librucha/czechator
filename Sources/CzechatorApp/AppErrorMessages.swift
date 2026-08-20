import CzechatorCore

/// The app-target counterpart to `ErrorMessages`.
///
/// The core cannot describe `HotKeyError` or `MonitorError` — it does not know
/// they exist, and must not, if it is to stay portable. Without this they would
/// reach the menu as `registrationFailed(-9878)`, which is exactly the kind of
/// dead end the trigger rework was meant to remove.
enum AppErrorMessages {

    static func describe(_ error: any Error) -> String {
        switch error {
        case let error as HotKeyManager.HotKeyError:
            return describe(error)
        case let error as DoubleTapMonitor.MonitorError:
            return describe(error)
        default:
            return ErrorMessages.describe(error)
        }
    }

    private static func describe(_ error: HotKeyManager.HotKeyError) -> String {
        switch error {
        case .unsupportedKey(let key):
            return "Klávesu „\(key)“ zkratka neumí. Použitelná jsou písmena a číslice."
        case .registrationFailed:
            // The usual cause by far: something else already holds it. Carbon
            // does not say what, so neither can we.
            return "Zkratku se nepodařilo zaregistrovat — nejspíš ji už drží jiná "
                + "aplikace. Zvolte jinou, nebo přepněte na dvojí stisk."
        }
    }

    private static func describe(_ error: DoubleTapMonitor.MonitorError) -> String {
        switch error {
        case .accessibilityDenied:
            return ErrorMessages.accessibilityRequired
        }
    }
}

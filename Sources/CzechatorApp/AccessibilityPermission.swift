import AppKit
import ApplicationServices

/// The Accessibility permission, which is what lets the app see key presses at
/// all.
///
/// Note for anyone testing this: the permission is tied to the app's code
/// signature, and Czechator is signed ad-hoc, so every `make install` produces
/// what macOS considers a different application. The permission has to be
/// granted again after each build, and the stale entry may need removing from
/// the list by hand.
enum AccessibilityPermission {

    /// Checks without ever showing a dialog, so it is safe to call on every
    /// menu open.
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system dialog. Only ever called when the user picks the
    /// double-tap trigger — never at launch.
    static func request() {
        // The literal rather than `kAXTrustedCheckOptionPrompt`: the imported
        // constant is a mutable global, which strict concurrency rejects. The
        // string is the constant's documented value and does not change.
        let options = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func openSystemSettings() {
        guard
            let url = URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
        else { return }
        NSWorkspace.shared.open(url)
    }
}

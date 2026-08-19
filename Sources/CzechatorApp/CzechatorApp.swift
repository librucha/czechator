import AppKit
import SwiftUI

/// Minimal entry point. The task that adds the model, history and error states
/// replaces the menu contents; this version exists so the target links and the
/// hotkey layer can be built and reviewed on its own.
@main
struct CzechatorApp: App {
    var body: some Scene {
        MenuBarExtra("Czechator", systemImage: "textformat.abc.dottedunderline") {
            Button("Ukončit") { NSApplication.shared.terminate(nil) }
        }
    }
}

import AppKit
import SwiftUI

@main
struct CzechatorApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra("Czechator", systemImage: model.iconName) {
            MenuContent(model: model)
        }

        Settings {
            SettingsView(model: model)
        }
    }
}

/// Bootstraps the model once the app is actually running — the hotkey needs a
/// live event target and the notification prompt needs a foreground session.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.start() }
    }
}

struct MenuContent: View {

    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            Button("Doplnit diakritiku") { model.run() }

            if let problem = model.startupProblem {
                Divider()
                Text(problem)
            }

            if let detail = model.lastErrorDetail {
                Divider()
                Text("Poslední chyba: \(detail)")
            }

            if !model.history.isEmpty {
                Divider()
                Text("Historie")
                ForEach(model.history) { entry in
                    Button(entry.preview) { model.restore(entry) }
                        .disabled(!entry.succeeded)
                        // The label is truncated to 40 characters; the full
                        // message stays reachable on hover.
                        .help(entry.detail ?? entry.preview)
                }
            }

            Divider()
            SettingsLink { Text("Nastavení…") }
            Button("Ukončit") { NSApplication.shared.terminate(nil) }
        }
        // Opening the menu counts as acknowledging the error: the badge clears
        // but the detail stays readable in the history below.
        .onAppear { model.acknowledgeError() }
    }
}

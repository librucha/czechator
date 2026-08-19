import AppKit
import SwiftUI

@main
struct CzechatorApp: App {

    static let settingsWindowID = "settings"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra("Czechator", systemImage: model.iconName) {
            MenuContent(model: model)
        }

        // A plain Window, not the Settings scene. Measured on macOS 26: in an
        // accessory app (LSUIElement) the Settings scene never materializes —
        // showSettingsWindow: reports success and no window is created, so both
        // SettingsLink and the selector silently do nothing. openWindow(id:)
        // works.
        Window("Nastavení Czechator", id: Self.settingsWindowID) {
            SettingsView(model: model)
        }
        .defaultSize(width: 480, height: 420)
    }
}

/// Bootstraps the model once the app is actually running — the hotkey needs a
/// live event target and the notification prompt needs a foreground session.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.start() }
    }
}

/// The standard AppKit panel, not a SwiftUI scene.
///
/// Verified in an accessory bundle on macOS 26: this one really does create a
/// visible window, unlike the Settings scene. It reads the name, version and
/// copyright straight from Info.plist, which the Makefile stamps from
/// `Czechator.version`.
@MainActor
private func showAbout() {
    NSApplication.shared.activate(ignoringOtherApps: true)
    NSApplication.shared.orderFrontStandardAboutPanel(
        options: [
            .credits: NSAttributedString(
                string: "Doplňuje českou diakritiku do obsahu schránky.\n"
                    + "github.com/librucha/czechator",
                attributes: [.font: NSFont.systemFont(ofSize: 11)])
        ])
}

struct MenuContent: View {

    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

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
            Button("O aplikaci Czechator") { showAbout() }
            Button("Nastavení…") {
                openWindow(id: CzechatorApp.settingsWindowID)
                // An accessory app is never frontmost, so without this the
                // window opens behind whatever the user is looking at.
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            Button("Ukončit") { NSApplication.shared.terminate(nil) }
        }
        // Opening the menu counts as acknowledging the error: the badge clears
        // but the detail stays readable in the history below.
        .onAppear { model.acknowledgeError() }
    }
}

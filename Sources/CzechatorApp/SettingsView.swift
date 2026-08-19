import CzechatorCore
import SwiftUI

struct SettingsView: View {

    @ObservedObject var model: AppModel

    @State private var activeProfile: String = ""
    @State private var shortcut: String = ""
    @State private var apiKey: String = ""
    @State private var warning: String?
    /// A shortcut that will not parse must not reach the config file: the app
    /// would then fail to register it on every launch and the hotkey would be
    /// silently dead.
    @State private var shortcutIsValid = true

    var body: some View {
        Form {
            Section("Profil") {
                Picker("Aktivní profil", selection: $activeProfile) {
                    ForEach(model.profileNames, id: \.self) { Text($0) }
                }
                if let endpoint = model.endpointDescription(for: activeProfile) {
                    Text(endpoint).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Zkratka") {
                TextField("Zkratka", text: $shortcut)
                if let warning {
                    Text(warning).font(.caption).foregroundStyle(.orange)
                }
            }

            Section("Klíč pro cloudový profil") {
                SecureField("API klíč", text: $apiKey)
                    .disabled(model.keychainAccount(for: activeProfile) == nil)
                Text("Uloží se do Keychainu, nikoli do konfiguračního souboru.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Uložit") { save() }.disabled(!shortcutIsValid)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { load() }
        .onChange(of: shortcut) { _, new in validate(new) }
    }

    private func load() {
        activeProfile = model.activeProfileName
        shortcut = model.shortcutText
        validate(shortcut)
    }

    private func validate(_ text: String) {
        do {
            let spec = try ShortcutSpec.parse(text)
            shortcutIsValid = true
            // A collision warning is advisory — the user may genuinely want it.
            warning =
                spec.isCommonSystemShortcut
                ? "Tohle je běžná systémová zkratka — v ostatních aplikacích přestane fungovat."
                : nil
        } catch {
            shortcutIsValid = false
            warning = "Zkratku se nepodařilo přečíst. Příklad: cmd+ctrl+d"
        }
    }

    private func save() {
        if !apiKey.isEmpty, let account = model.keychainAccount(for: activeProfile) {
            do {
                try KeychainSecretResolver().store(apiKey, account: account)
                apiKey = ""
            } catch {
                // Clearing the field on a failed write would look like success
                // and the problem would only surface at the next model call.
                warning = ErrorMessages.describe(error)
                return
            }
        }
        model.applySettings(activeProfile: activeProfile, shortcut: shortcut)
    }
}

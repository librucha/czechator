import CzechatorCore
import SwiftUI

struct SettingsView: View {

    @ObservedObject var model: AppModel

    @State private var activeProfile: String = ""
    @State private var shortcut: String = ""
    @State private var apiKey: String = ""
    @State private var warning: String?

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
                Button("Uložit") { save() }.disabled(warning != nil && shortcut.isEmpty)
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
            warning =
                spec.isCommonSystemShortcut
                ? "Tohle je běžná systémová zkratka — v ostatních aplikacích přestane fungovat."
                : nil
        } catch {
            warning = "Zkratku se nepodařilo přečíst."
        }
    }

    private func save() {
        if !apiKey.isEmpty, let account = model.keychainAccount(for: activeProfile) {
            try? KeychainSecretResolver().store(apiKey, account: account)
            apiKey = ""
        }
        model.applySettings(activeProfile: activeProfile, shortcut: shortcut)
    }
}

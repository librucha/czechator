import CzechatorCore
import SwiftUI

struct SettingsView: View {

    @ObservedObject var model: AppModel

    /// Everything the window can change, plus the rules that follow from it.
    /// See SettingsFormState — the decisions live there so they can be tested.
    @State private var form = SettingsFormState()
    @State private var apiKey: String = ""
    /// Only ever set by a failed Keychain write; the shortcut's own warning is
    /// derived from the shortcut itself.
    @State private var keychainProblem: String?

    var body: some View {
        Form {
            Section("Profil") {
                Picker("Aktivní profil", selection: $form.activeProfile) {
                    ForEach(model.profileNames, id: \.self) { Text($0) }
                }
                if let endpoint = model.endpointDescription(for: form.activeProfile) {
                    Text(endpoint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Spouštění") {
                Picker("Spouštěč", selection: $form.triggerKind) {
                    Text("Klávesová zkratka").tag(TriggerKind.combination)
                    Text("Dvojí stisk modifikátoru").tag(TriggerKind.doubleTap)
                }

                if form.triggerKind == .combination {
                    TextField("Zkratka", text: $form.shortcut, prompt: Text("cmd+ctrl+d"))
                    if let warning = form.warning {
                        Label(
                            warning,
                            systemImage: form.shortcutIsValid
                                ? "exclamationmark.triangle" : "xmark.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(form.shortcutIsValid ? .orange : .red)
                    }
                } else {
                    if !form.shortcutIsValid {
                        // The shortcut is stored either way, so it has to parse
                        // either way — otherwise switching back later would
                        // leave the app with no trigger at all.
                        Label(
                            "Uloženou zkratku se nepodařilo přečíst. Opravte ji "
                                + "v režimu klávesové zkratky, jinak nepůjde uložit.",
                            systemImage: "xmark.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                    Picker("Modifikátor", selection: $form.triggerModifier) {
                        ForEach(ModifierKey.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Text(
                        "Jedno stisknutí projde beze změny dál, takže se žádné "
                            + "aplikaci nic nebere."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if model.needsAccessibility {
                        Label(ErrorMessages.accessibilityRequired, systemImage: "lock")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button("Povolit v Nastavení systému…") { model.grantAccessibility() }
                    }
                }
            }

            Section("Klíč pro cloudový profil") {
                SecureField("API klíč", text: $apiKey)
                    .disabled(model.keychainAccount(for: form.activeProfile) == nil)
                if let keychainProblem {
                    Label(keychainProblem, systemImage: "xmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Uloží se do Keychainu, nikoli do konfiguračního souboru.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // Without this the form renders as bare rows: a plain Window does not
        // get the grouped appearance the Settings scene applies for free.
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Uložit") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!form.canSave)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .frame(minWidth: 460, minHeight: 380)
        .onAppear { load() }
        .onChange(of: form.triggerKind) { _, new in
            guard
                form.shouldRequestPermission(forNewKind: new, granted: model.isAccessibilityGranted)
            else { return }
            model.grantAccessibility()
        }
    }

    private func load() {
        form.load(
            activeProfile: model.activeProfileName, shortcut: model.shortcutText,
            triggerKind: model.triggerKind, triggerModifier: model.triggerModifier)
        keychainProblem = nil
    }

    private func save() {
        if !apiKey.isEmpty, let account = model.keychainAccount(for: form.activeProfile) {
            do {
                try KeychainSecretResolver().store(apiKey, account: account)
                apiKey = ""
                keychainProblem = nil
            } catch {
                // Clearing the field on a failed write would look like success
                // and the problem would only surface at the next model call.
                keychainProblem = ErrorMessages.describe(error)
                return
            }
        }
        model.applySettings(
            activeProfile: form.activeProfile, shortcut: form.shortcut,
            triggerKind: form.triggerKind, triggerModifier: form.triggerModifier)
    }
}

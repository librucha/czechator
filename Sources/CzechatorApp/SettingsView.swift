import CzechatorCore
import SwiftUI

struct SettingsView: View {

    @ObservedObject var model: AppModel

    @Environment(\.dismiss) private var dismiss

    /// Everything the window can change, plus the rules that follow from it.
    /// See SettingsFormState — the decisions live there so they can be tested.
    @State private var form = SettingsFormState()
    @State private var apiKey: String = ""
    /// Only ever set by a failed Keychain write; the shortcut's own warning is
    /// derived from the shortcut itself.
    @State private var keychainProblem: String?

    var body: some View {
        TabView {
            basic
                .tabItem { Label("Základní", systemImage: "slider.horizontal.3") }
            advanced
                .tabItem { Label("Pokročilé", systemImage: "gearshape.2") }
        }
        .safeAreaInset(edge: .bottom) { saveBar }
        .frame(minWidth: 520, minHeight: 520)
        .onAppear { load() }
    }

    // MARK: - Základní

    private var basic: some View {
        Form {
            Section("Profil") {
                Picker("Aktivní profil", selection: $form.config.activeProfile) {
                    ForEach(model.profileNames, id: \.self) { Text($0) }
                }
                if let endpoint = model.endpointDescription(for: form.config.activeProfile) {
                    Text(endpoint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Spouštění") {
                Picker("Spouštěč", selection: $form.config.trigger.kind) {
                    Text("Klávesová zkratka").tag(TriggerKind.combination)
                    Text("Dvojí stisk modifikátoru").tag(TriggerKind.doubleTap)
                }

                if form.config.trigger.kind == .combination {
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
                    Picker("Modifikátor", selection: $form.config.trigger.modifier) {
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
                        Button("Udělit oprávnění…") { model.grantAccessibility() }
                    }
                }
            }

            Section("Chování") {
                Picker("Velikost písmen", selection: $form.config.features.letterCase) {
                    ForEach(LetterCasePolicy.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Text(letterCaseExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Historie v menu", isOn: $form.config.features.history)
                if form.config.features.history {
                    Stepper(
                        "Kolik položek: \(form.config.features.historySize)",
                        value: $form.config.features.historySize, in: 1...100)
                }
            }

            Section("Klíč pro cloudový profil") {
                SecureField("API klíč", text: $apiKey)
                    .disabled(model.keychainAccount(for: form.config.activeProfile) == nil)
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
    }

    private var letterCaseExplanation: String {
        switch form.config.features.letterCase {
        case .preserve:
            return "Nic než diakritika se nezmění. Nejpřísnější, ale model nesmí "
                + "opravit ani malé písmeno na začátku věty."
        case .segmentStart:
            return "Model smí změnit první písmeno segmentu. Zbytek zůstane, "
                + "takže ČSN ani iPhone se nerozbijí."
        case .model:
            return "Model si s velikostí písmen dělá, co chce. Ověření už "
                + "nedokáže prokázat, že se změnila jen diakritika."
        }
    }

    // MARK: - Pokročilé

    private var advanced: some View {
        Form {
            if form.config.trigger.kind == .doubleTap {
                Section("Časy dvojího stisku") {
                    Stepper(
                        "Mezera mezi ťuknutími: \(form.config.trigger.intervalMs) ms",
                        value: $form.config.trigger.intervalMs, in: 10...2000, step: 25)
                    Stepper(
                        "Nejdelší ťuknutí: \(form.config.trigger.maxHoldMs) ms",
                        value: $form.config.trigger.maxHoldMs, in: 10...2000, step: 25)
                    Text(
                        "Přísné hodnoty jsou schválně: planý poplach přepíše schránku, "
                            + "kdyžs o to nežádal, což je horší než ťuknutí, které neprošlo."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Toggle("Zapisovat stisky do systémového logu", isOn: $form.config.trigger.debug)
                    if form.config.trigger.debug {
                        Text("log stream --predicate 'subsystem == \"cz.czechator.app\"'")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Section("Limity") {
                LabeledContent("Největší vstup") {
                    TextField(
                        "", value: $form.config.limits.maxInputBytes, format: .number
                    )
                    .labelsHidden()
                    .frame(width: 90)
                    Text("B")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Největší dávka") {
                    TextField(
                        "", value: $form.config.limits.maxBatchChars, format: .number
                    )
                    .labelsHidden()
                    .frame(width: 90)
                    Text("znaků")
                        .foregroundStyle(.secondary)
                }
                Text(
                    "Dávka je to, co jde do modelu najednou. Menší dávky jsou "
                        + "spolehlivější, ale pomalejší."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Vlastní prompt") {
                TextEditor(text: promptOverride)
                    .font(.body.monospaced())
                    .frame(minHeight: 120)
                Text(
                    "Prázdné pole znamená vestavěný prompt. Vlastní prompt musí "
                        + "modelu říct, že smí měnit jen diakritiku — ověření sice "
                        + "nepustí dál nic jiného, ale opravu tím zahodí celou."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// The config stores nil for "use the built-in prompt"; a text editor needs
    /// a string, and an empty one means the same thing.
    private var promptOverride: Binding<String> {
        Binding(
            get: { form.config.prompt.override ?? "" },
            set: { form.config.prompt.override = $0.isEmpty ? nil : $0 })
    }

    // MARK: - Uložit

    private var saveBar: some View {
        HStack {
            if let problem = form.configProblem {
                Label(problem, systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            Spacer()
            Button("Uložit") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(!form.canSave)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func load() {
        form.load(from: model.currentConfig)
        keychainProblem = nil
    }

    private func save() {
        if !apiKey.isEmpty, let account = model.keychainAccount(for: form.config.activeProfile) {
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
        model.apply(form.config)
        // Saving is the end of the errand. Anything that went wrong is waiting
        // in the menu, which is where the app reports for the rest of its life.
        dismiss()
    }
}

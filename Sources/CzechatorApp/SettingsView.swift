import CzechatorCore
import CzechatorKeychain
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
            dictionary
                .tabItem { Label("Slovník", systemImage: "character.book.closed") }
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
                    ForEach(form.profileNames, id: \.self) { Text($0).tag($0) }
                }
                if let endpoint = form.activeProfileDescription {
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
                .disabled(!form.letterCaseIsEditable)
                Text(letterCaseExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Historie v menu", isOn: $form.config.features.history)
                if form.config.features.history {
                    Stepper(
                        "Velikost historie: \(form.config.features.historySize)",
                        value: $form.config.features.historySize, in: 1...100)
                }
            }

            if form.activeProfileNeedsKey {
                Section("Klíč pro cloudový profil") {
                    Text(
                        "Klíč patří k profilu, takže se zadává tam: Pokročilé → "
                            + "Profily → vyberte profil."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
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
            profilesSection

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
                    Text("bytů")
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

            Section("Segmentace — společné") {
                Stepper(
                    "Nejkratší úsek: \(form.config.segmentation.common.minLength) znaky",
                    value: $form.config.segmentation.common.minLength, in: 1...50)
                Toggle(
                    "Jen úseky obsahující písmena",
                    isOn: $form.config.segmentation.common.requireLetters)
                patternList(.commonSkipPatterns)
            }

            Section("Segmentace — prostý text") {
                patternList(.plainSkipPatterns)
            }

            Section("Segmentace — HTML") {
                Toggle("Přeskočit atributy", isOn: $form.config.segmentation.html.skipAttributes)
                Toggle("Přeskočit komentáře", isOn: $form.config.segmentation.html.skipComments)
                patternList(.htmlSkipElements)
            }

            Section("Segmentace — XML") {
                Toggle("Přeskočit atributy", isOn: $form.config.segmentation.xml.skipAttributes)
                Toggle("Přeskočit komentáře", isOn: $form.config.segmentation.xml.skipComments)
                Toggle(
                    "Přeskočit instrukce zpracování",
                    isOn: $form.config.segmentation.xml.skipProcessingInstructions)
                Toggle("Přeskočit CDATA", isOn: $form.config.segmentation.xml.skipCDATA)
                patternList(.xmlSkipElements)
            }

            Section("Segmentace — JSON") {
                Toggle("Přeskočit klíče", isOn: $form.config.segmentation.json.skipKeys)
                patternList(.jsonSkipValuesForKeys)
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

    @ViewBuilder
    private var profilesSection: some View {
        Section("Profily") {
            HStack {
                // A picker rather than the list a mock-up might suggest: a list
                // with a selection inside a Form fights the form's own layout,
                // and with a handful of profiles this shows the same thing.
                Picker("Upravovaný profil", selection: editedProfile) {
                    ForEach(form.profileNames, id: \.self) { Text($0).tag($0) }
                }
                Button {
                    form.addProfile()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Přidat profil")
                Button {
                    form.removeEditedProfile()
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(!form.canRemoveProfile)
                .help(
                    form.canRemoveProfile
                        ? "Odebrat profil" : "Poslední profil odebrat nelze")
            }

            if form.editedProfileFields != nil {
                TextField("Název", text: $form.editedProfileName)
                    .onSubmit { form.commitRename() }
                if let problem = form.profileNameProblem {
                    Label(problem, systemImage: "xmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Picker("Typ", selection: profileKind) {
                    ForEach(ProfileKind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                TextField("Endpoint", text: profileEndpoint)
                TextField("Model", text: profileModel)
                LabeledContent("Teplota") {
                    TextField("", value: profileTemperature, format: .number)
                        .labelsHidden()
                        .frame(width: 70)
                }
                LabeledContent("Timeout") {
                    TextField("", value: profileTimeout, format: .number)
                        .labelsHidden()
                        .frame(width: 70)
                    Text("s").foregroundStyle(.secondary)
                }

                Picker(
                    "Režim oprav",
                    selection: Binding(
                        get: { form.editedProfileCorrections },
                        set: { form.selectCorrectionMode($0) })
                ) {
                    ForEach(CorrectionMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                if form.editedProfileCorrections == .proofread {
                    Text("U malých lokálních modelů může model tiše přepsat slova.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if form.budgetIsEditable {
                    Stepper(
                        "Rozpočet: \(form.editedProfileBudget.percent) % délky slova",
                        value: Binding(
                            get: { form.editedProfileBudget.percent },
                            set: { form.editedProfileBudget.percent = $0 }),
                        in: 0...100, step: 5)
                    Stepper(
                        "Nejméně editů na slovo: \(form.editedProfileBudget.minimum)",
                        value: Binding(
                            get: { form.editedProfileBudget.minimum },
                            set: { form.editedProfileBudget.minimum = $0 }),
                        in: 0...5)
                }

                Toggle("Ověřovat výsledek", isOn: $form.editedProfileVerification)
                if !form.editedProfileVerification {
                    Text(
                        "Bez ověření se do schránky zapíše cokoli, co model vrátí — "
                            + "včetně ztracených nedělitelných mezer."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if form.editedProfileNeedsKey {
                    SecureField("API klíč", text: $apiKey, prompt: Text("vloží se do Keychainu"))
                    if let keychainProblem {
                        Label(keychainProblem, systemImage: "xmark.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if let account = form.editedProfileKeychainAccount {
                        Text("Uloženo v Keychainu jako „\(account)“, nikoli v konfiguraci.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if form.editedProfileFields?.apiKey != nil {
                        Text(
                            "Tento profil bere klíč odjinud než z Keychainu — "
                                + "nastavení do toho nesahá."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("Uloží se do Keychainu, nikoli do konfiguračního souboru.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if form.editedProfile == form.config.activeProfile {
                    Text("Tento profil se právě používá.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Použít tento profil") {
                        form.config.activeProfile = form.editedProfile
                    }
                }
            }
        }
    }

    /// Selecting is a method rather than a plain field, because switching has to
    /// commit whatever was typed into the rename box first.
    private var editedProfile: Binding<String> {
        Binding(
            get: { form.editedProfile },
            set: { form.selectProfile($0) })
    }

    private var profileKind: Binding<ProfileKind> {
        Binding(
            get: { form.editedProfileFields?.kind ?? .ollama },
            set: { form.editedProfileFields?.kind = $0 })
    }

    /// Typed as text, not as a URL: half-finished input like `http://loc` is
    /// not a URL yet, and a field that resists being typed into is worse than
    /// one that says what is wrong. `Config.validate` is what refuses it.
    private var profileEndpoint: Binding<String> {
        Binding(
            get: { form.editedProfileFields?.endpoint.absoluteString ?? "" },
            set: {
                form.editedProfileFields?.endpoint = URL(string: $0) ?? URL(string: "about:blank")!
            })
    }

    private var profileModel: Binding<String> {
        Binding(
            get: { form.editedProfileFields?.model ?? "" },
            set: { form.editedProfileFields?.model = $0 })
    }

    private var profileTemperature: Binding<Double> {
        Binding(
            get: { form.editedProfileFields?.temperature ?? 0 },
            set: { form.editedProfileFields?.temperature = $0 })
    }

    private var profileTimeout: Binding<Double> {
        Binding(
            get: { form.editedProfileFields?.timeoutSeconds ?? 30 },
            set: { form.editedProfileFields?.timeoutSeconds = $0 })
    }

    /// One list, edited as lines.
    ///
    /// Bound to the text rather than to the array: folding it back through the
    /// array on every keystroke would delete the blank line being typed.
    @ViewBuilder
    private func patternList(_ list: SettingsFormState.PatternList) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(list.label)
            TextEditor(
                text: Binding(
                    get: { form.listText[list] ?? "" },
                    set: { form.listText[list] = $0 })
            )
            .font(.body.monospaced())
            .frame(minHeight: 70)
            Text(list.hint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The config stores nil for "use the built-in prompt"; a text editor needs
    /// a string, and an empty one means the same thing.
    private var promptOverride: Binding<String> {
        Binding(
            get: { form.config.prompt.override ?? "" },
            set: { form.config.prompt.override = $0.isEmpty ? nil : $0 })
    }

    // MARK: - Uložit

    // MARK: - Slovník

    private var dictionary: some View {
        Form {
            Section("Osobní slovník") {
                Text(
                    "Pravidla se uplatní na každý výstup modelu, ještě před ověřením. "
                        + "Smí měnit jen diakritiku. Stejný text v obou polích chrání "
                        + "výraz před háčky a čárkami, které by model přidal "
                        + "(google docs → google docs). Diakritiku, kterou jste napsali "
                        + "sami, slovník nepřepíše."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                ForEach($form.dictionaryRows) { $row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("Zadaný text", text: $row.from, prompt: Text("Zadaný text"))
                                .labelsHidden()
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                            TextField("Požadovaný text", text: $row.to, prompt: Text("Požadovaný text"))
                                .labelsHidden()
                            Button {
                                form.removeDictionaryRow(id: row.id)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Odebrat pravidlo")
                        }
                        if let problem = form.dictionaryProblem(for: row.id) {
                            Label(problem, systemImage: "xmark.circle")
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if let warning = form.dictionaryWarning(for: row.id) {
                            Label(LocalizedStringKey(warning), systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button("Přidat pravidlo") { form.addDictionaryRow() }
            }
        }
        .formStyle(.grouped)
    }

    private var saveBar: some View {
        HStack {
            if let problem = form.patternProblem ?? form.configProblem {
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
        // A name typed but never confirmed with Return would otherwise be lost.
        form.commitRename()

        if !apiKey.isEmpty {
            guard let account = form.ensureKeychainReference() else {
                keychainProblem =
                    "Tento profil klíč z Keychainu nebere, takže ho tu nelze uložit."
                return
            }
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
        model.apply(form.resolvedConfig)
        // Saving is the end of the errand. Anything that went wrong is waiting
        // in the menu, which is where the app reports for the rest of its life.
        dismiss()
    }
}

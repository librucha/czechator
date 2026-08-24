import CzechatorCore
import Foundation

/// The configuration the settings window is editing, and the decisions that
/// follow from it.
///
/// A working copy of the whole `Config` rather than a field per control: the
/// window now edits most of what the file holds, and threading thirty values
/// through a save call would be its own kind of bug. Nothing here draws
/// anything — whether saving is allowed and what the warnings say are ordinary
/// rules that happened to live inside a `body`, and every one of them was wrong
/// at some point without a test noticing.
struct SettingsFormState: Equatable {

    /// Bound to directly by the controls, so a plain `var`.
    var config: Config = .builtIn

    /// Which profile the detail fields below are describing. Not the same as
    /// the active one: you can edit a profile you are not currently using.
    private(set) var editedProfile: String = ""

    /// The lists as typed, one item per line.
    ///
    /// Kept as text rather than folded through the array on every keystroke:
    /// an array cannot hold the blank line you are in the middle of typing, so
    /// it would vanish under the cursor.
    var listText: [PatternList: String] = [:]

    /// The name in the rename field, which is a draft until it is committed.
    ///
    /// Renaming on every keystroke would work — each intermediate name is
    /// usually valid — but the sorted list would reshuffle under the cursor,
    /// and the first collision would have to be undone rather than refused.
    var editedProfileName: String = ""

    /// The shortcut, reached through the first binding.
    ///
    /// `load` guarantees there is one, so this never has to invent it.
    var shortcut: String {
        get { config.hotkeys.first?.shortcut ?? "" }
        set {
            if config.hotkeys.isEmpty {
                config.hotkeys = [
                    HotkeyBinding(shortcut: newValue, source: "clipboard", sink: "clipboard")
                ]
            } else {
                config.hotkeys[0].shortcut = newValue
            }
        }
    }

    /// Computed rather than stored: the flag this replaces was refreshed by an
    /// `onChange` and could describe a shortcut the field no longer held.
    var shortcutIsValid: Bool {
        (try? ShortcutSpec.parse(shortcut)) != nil
    }

    var warning: String? {
        guard let spec = try? ShortcutSpec.parse(shortcut) else {
            return "Zkratku se nepodařilo přečíst. Příklad: cmd+ctrl+d"
        }
        // Advisory: the user may genuinely want it.
        return spec.isCommonSystemShortcut
            ? "Tohle je běžná systémová zkratka — v ostatních aplikacích přestane fungovat."
            : nil
    }

    /// Whatever `Config.validate` objects to, in the words the rest of the app
    /// already uses. Asked rather than reimplemented, so the window and the
    /// file can never disagree about what is acceptable.
    var configProblem: String? {
        do {
            try resolvedConfig.validate()
            return nil
        } catch {
            return ErrorMessages.describe(error)
        }
    }

    /// The shortcut is written to the config whichever trigger is in use, so it
    /// has to parse whichever trigger is in use. Saving an unreadable one from
    /// the double-tap side would leave no trigger at all on switching back.
    var canSave: Bool {
        shortcutIsValid && configProblem == nil && profileNameProblem == nil
            && patternProblem == nil
    }

    /// Replaces the draft with what is actually in effect. The window is not a
    /// draft that survives closing: an unsaved edit does not come back.
    mutating func load(from config: Config) {
        var config = config
        // `hotkeys: []` parses fine and leaves nothing to register. Repairing
        // it here means every control below can assume a binding exists.
        if config.hotkeys.isEmpty {
            config.hotkeys = [
                HotkeyBinding(shortcut: "cmd+ctrl+d", source: "clipboard", sink: "clipboard")
            ]
        }
        self.config = config
        for list in PatternList.allCases {
            listText[list] = Self.text(from: config[keyPath: list.keyPath])
        }
        selectProfile(config.activeProfile)
    }

    // MARK: - Segmentation lists

    /// A list the window edits as lines of text.
    enum PatternList: String, CaseIterable, Sendable, Hashable {
        case commonSkipPatterns
        case plainSkipPatterns
        case htmlSkipElements
        case xmlSkipElements
        case jsonSkipValuesForKeys

        /// Whether the entries are compiled. Element and key names are matched
        /// literally, so a bracket in one is a name, not a broken pattern.
        var isPattern: Bool {
            self == .commonSkipPatterns || self == .plainSkipPatterns
        }

        var keyPath: WritableKeyPath<Config, [String]> {
            switch self {
            case .commonSkipPatterns: return \.segmentation.common.skipPatterns
            case .plainSkipPatterns: return \.segmentation.plain.skipPatterns
            case .htmlSkipElements: return \.segmentation.html.skipElements
            case .xmlSkipElements: return \.segmentation.xml.skipElements
            case .jsonSkipValuesForKeys: return \.segmentation.json.skipValuesForKeys
            }
        }

        var label: String {
            switch self {
            case .commonSkipPatterns: return "Přeskočit vzory"
            case .plainSkipPatterns: return "Přeskočit vzory"
            case .htmlSkipElements: return "Přeskočit elementy"
            case .xmlSkipElements: return "Přeskočit elementy"
            case .jsonSkipValuesForKeys: return "Přeskočit hodnoty u klíčů"
            }
        }

        var hint: String {
            switch self {
            case .commonSkipPatterns, .plainSkipPatterns:
                return "Regulární výrazy, jeden na řádek."
            case .htmlSkipElements, .xmlSkipElements:
                return "Názvy elementů, jeden na řádek. Přeskočí se i vše uvnitř."
            case .jsonSkipValuesForKeys:
                return "Názvy klíčů, jeden na řádek."
            }
        }
    }

    /// One entry per non-empty line, trimmed.
    ///
    /// A blank line must not become an entry: as a regular expression the empty
    /// string matches everything, which would skip the whole document.
    static func items(from text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func text(from items: [String]) -> String {
        items.joined(separator: "\n")
    }

    /// The first entry that will not compile, in the words the field needs.
    ///
    /// Checked the way `SegmentBuilder` will build it, so a pattern accepted
    /// here cannot fail later at the first correction, far from the window that
    /// accepted it.
    var patternProblem: String? {
        for list in PatternList.allCases where list.isPattern {
            for pattern in Self.items(from: listText[list] ?? "") {
                do {
                    _ = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
                } catch {
                    return "Vzor „\(pattern)“ není platný regulární výraz."
                }
            }
        }
        return nil
    }

    /// The draft with the line-edited lists folded back in — what gets saved.
    var resolvedConfig: Config {
        var resolved = config
        for list in PatternList.allCases {
            resolved[keyPath: list.keyPath] = Self.items(from: listText[list] ?? "")
        }
        return resolved
    }

    // MARK: - Profiles

    var profileNames: [String] { config.profiles.keys.sorted() }

    /// The profile the detail fields edit, or nil if the selection has somehow
    /// come adrift — which the controls read as nothing to show.
    var editedProfileFields: Profile? {
        get { config.profiles[editedProfile] }
        set { config.profiles[editedProfile] = newValue }
    }

    /// Reads from the draft, not from the model: the description has to follow
    /// an endpoint the user has only just typed.
    var activeProfileDescription: String? {
        config.profiles[config.activeProfile].map {
            "\($0.kind.rawValue) · \($0.endpoint.absoluteString) · \($0.model)"
        }
    }

    /// Whether the profile in use wants a key — the Basic tab says where to
    /// put it, rather than offering a second field bound to the same state as
    /// the one in the profile editor.
    var activeProfileNeedsKey: Bool {
        config.profiles[config.activeProfile]?.kind == .openaiCompat
    }

    /// Whether the profile being edited talks to something that wants a key.
    var editedProfileNeedsKey: Bool { editedProfileFields?.kind == .openaiCompat }

    /// The Keychain entry this profile's key lives in, if it has one.
    ///
    /// Only a Keychain reference counts: a config may point at an environment
    /// variable on purpose, and the window has no business rewriting that.
    var editedProfileKeychainAccount: String? {
        if case .keychain(let account) = editedProfileFields?.apiKey { return account }
        return nil
    }

    /// Gives the profile somewhere to keep a key, and says where that is.
    ///
    /// A profile added from this window had no reference at all, so the key
    /// field was disabled and the only way in was to edit the file by hand.
    /// Returns nil when a key would be pointless — a local endpoint takes none
    /// — or when the profile already resolves its key some other way.
    @discardableResult
    mutating func ensureKeychainReference() -> String? {
        guard editedProfileNeedsKey else { return nil }
        if let existing = editedProfileKeychainAccount { return existing }
        guard editedProfileFields?.apiKey == nil else { return nil }
        let account = "czechator-\(editedProfile)"
        editedProfileFields?.apiKey = .keychain(account: account)
        return account
    }

    /// An application with no profile has nothing to talk to.
    var canRemoveProfile: Bool { config.profiles.count > 1 }

    var profileNameProblem: String? {
        let name = editedProfileName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return "Název profilu nesmí být prázdný." }
        if name != editedProfile, config.profiles[name] != nil {
            return "Profil s názvem „\(name)“ už existuje."
        }
        return nil
    }

    /// Shows a different profile, committing whatever was typed into the rename
    /// field first — a name typed and then abandoned would otherwise vanish
    /// without a word.
    mutating func selectProfile(_ name: String) {
        commitRename()
        editedProfile = config.profiles[name] != nil ? name : (profileNames.first ?? "")
        editedProfileName = editedProfile
    }

    mutating func addProfile() {
        commitRename()
        var name = "novy profil"
        var suffix = 2
        while config.profiles[name] != nil {
            name = "novy profil \(suffix)"
            suffix += 1
        }
        // A local Ollama profile is the one that works without an account.
        config.profiles[name] =
            Config.builtIn.profiles["local"]
            ?? Profile(
                kind: .ollama, endpoint: URL(string: "http://localhost:11434")!,
                model: "qwen3:4b-instruct", temperature: 0, timeoutSeconds: 30)
        // Adding is not choosing: the active profile is a separate decision.
        editedProfile = name
        editedProfileName = name
    }

    mutating func removeEditedProfile() {
        guard canRemoveProfile, config.profiles[editedProfile] != nil else { return }
        let removed = editedProfile
        config.profiles[removed] = nil
        // Leaving activeProfile pointing at nothing makes the file unloadable,
        // and Config.validate would then block saving with no obvious way out.
        if config.activeProfile == removed {
            config.activeProfile = profileNames.first ?? ""
        }
        editedProfile = profileNames.first ?? ""
        editedProfileName = editedProfile
    }

    /// Applies the name in the rename field. Silently does nothing when there
    /// is nothing to apply or the name is unusable — the field itself is what
    /// explains why, and saving is blocked until it is resolved.
    mutating func commitRename() {
        let name = editedProfileName.trimmingCharacters(in: .whitespaces)
        guard name != editedProfile, profileNameProblem == nil,
            let profile = config.profiles[editedProfile]
        else { return }
        config.profiles[editedProfile] = nil
        config.profiles[name] = profile
        if config.activeProfile == editedProfile { config.activeProfile = name }
        editedProfile = name
        editedProfileName = name
    }
}

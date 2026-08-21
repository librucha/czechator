import CzechatorCore

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
            try config.validate()
            return nil
        } catch {
            return ErrorMessages.describe(error)
        }
    }

    /// The shortcut is written to the config whichever trigger is in use, so it
    /// has to parse whichever trigger is in use. Saving an unreadable one from
    /// the double-tap side would leave no trigger at all on switching back.
    var canSave: Bool { shortcutIsValid && configProblem == nil }

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
    }
}

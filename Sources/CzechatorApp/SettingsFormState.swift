import CzechatorCore

/// What the settings window is currently showing, and the decisions that follow
/// from it.
///
/// Separate from the view because none of this is drawing: whether saving is
/// allowed, whether a change should ask macOS for a permission, and what the
/// warning says are ordinary rules that happened to live inside a `body`. Every
/// one of them was wrong at some point without a test noticing.
struct SettingsFormState: Equatable {

    var activeProfile: String = ""
    var shortcut: String = ""
    var triggerKind: TriggerKind = .combination
    var triggerModifier: ModifierKey = .rightCommand

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

    /// The shortcut is written to the config whichever trigger is in use, so it
    /// has to parse whichever trigger is in use. Saving an unreadable one from
    /// the double-tap side would leave no trigger at all on switching back.
    var canSave: Bool { shortcutIsValid }

    /// Replaces everything with what is actually in effect. The window is not a
    /// draft: an unsaved edit does not survive reopening it.
    mutating func load(
        activeProfile: String, shortcut: String,
        triggerKind: TriggerKind, triggerModifier: ModifierKey
    ) {
        self.activeProfile = activeProfile
        self.shortcut = shortcut
        self.triggerKind = triggerKind
        self.triggerModifier = triggerModifier
    }
}

import CzechatorCore
import Foundation
import Testing

@testable import CzechatorApp

private func loadedForm(
    shortcut: String = "cmd+ctrl+d",
    kind: TriggerKind = .combination
) -> SettingsFormState {
    var form = SettingsFormState()
    form.load(
        activeProfile: "local", shortcut: shortcut,
        triggerKind: kind, triggerModifier: .rightCommand)
    return form
}

// MARK: - Saving

@Test func anUnreadableShortcutBlocksSavingInBothModes() {
    // The shortcut is written to the config whichever trigger is chosen, so it
    // has to parse whichever trigger is chosen — otherwise switching back later
    // leaves the app with no trigger at all.
    for kind in TriggerKind.allCases {
        let form = loadedForm(shortcut: "cmd+ctr+d", kind: kind)
        #expect(form.canSave == false, "\(kind) should refuse an unreadable shortcut")
    }
}

@Test func aReadableShortcutAllowsSavingInBothModes() {
    for kind in TriggerKind.allCases {
        let form = loadedForm(shortcut: "cmd+alt+k", kind: kind)
        #expect(form.canSave, "\(kind) should accept a readable shortcut")
    }
}

@Test func anEmptyShortcutIsNotSaveable() {
    #expect(loadedForm(shortcut: "").canSave == false)
}

// MARK: - Validity and warnings

@Test func validityFollowsTheTextWithNothingToKeepInSync() {
    // Computed, not stored: the old flag was updated by an onChange and could
    // lag behind the field it described.
    var form = loadedForm()
    #expect(form.shortcutIsValid)
    form.shortcut = "nesmysl+++"
    #expect(form.shortcutIsValid == false)
    form.shortcut = "ctrl+shift+p"
    #expect(form.shortcutIsValid)
}

@Test func warnsAboutACombinationEveryApplicationUses() {
    let form = loadedForm(shortcut: "cmd+b")
    let warning = try? #require(form.warning)
    #expect(warning?.contains("běžná systémová zkratka") == true)
    // Advisory only — the user may genuinely want it.
    #expect(form.canSave)
}

@Test func staysQuietAboutACombinationNothingElseClaims() {
    #expect(loadedForm(shortcut: "cmd+shift+d").warning == nil)
    #expect(loadedForm(shortcut: "cmd+ctrl+d").warning == nil)
}

@Test func explainsAnUnreadableShortcutWithAnExample() {
    let form = loadedForm(shortcut: "cmd+ctr+d")
    let warning = try? #require(form.warning)
    #expect(warning?.contains("cmd+ctrl+d") == true)
}

// MARK: - Loading

@Test func loadTakesEveryFieldFromTheModel() {
    var form = SettingsFormState()
    form.load(
        activeProfile: "openai", shortcut: "ctrl+shift+p",
        triggerKind: .doubleTap, triggerModifier: .leftOption)

    #expect(form.activeProfile == "openai")
    #expect(form.shortcut == "ctrl+shift+p")
    #expect(form.triggerKind == .doubleTap)
    #expect(form.triggerModifier == .leftOption)
}

@Test func reopeningTheWindowDiscardsAnUnsavedEdit() {
    // The window is not a draft: what it shows on open is what is in effect.
    var form = loadedForm(shortcut: "cmd+ctrl+d")
    form.shortcut = "cmd+alt+k"
    form.triggerKind = .doubleTap

    form.load(
        activeProfile: "local", shortcut: "cmd+ctrl+d",
        triggerKind: .combination, triggerModifier: .rightCommand)

    #expect(form.shortcut == "cmd+ctrl+d")
    #expect(form.triggerKind == .combination)
}

@Test func loadIsNotAUserAction() {
    // The window used to ask macOS for the Accessibility permission the moment
    // it opened on a double-tap install, because load() assigning the trigger
    // kind is indistinguishable from the user picking it. Nothing here decides
    // anything about permissions any more — only the button does.
    var form = SettingsFormState()
    form.load(
        activeProfile: "local", shortcut: "cmd+ctrl+d",
        triggerKind: .doubleTap, triggerModifier: .rightCommand)
    #expect(form.triggerKind == .doubleTap)
    #expect(form.canSave)
}

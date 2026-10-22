import CzechatorCore
import Foundation
import Testing

@testable import CzechatorApp

private func loadedForm(_ mutate: (inout Config) -> Void = { _ in }) -> SettingsFormState {
    var config = Config.builtIn
    mutate(&config)
    var form = SettingsFormState()
    form.load(from: config)
    return form
}

// MARK: - The draft

@Test func loadTakesTheWholeConfiguration() {
    let form = loadedForm {
        $0.activeProfile = "openai"
        $0.features.letterCase = .model
        $0.limits.maxBatchChars = 900
    }
    #expect(form.config.activeProfile == "openai")
    #expect(form.config.features.letterCase == .model)
    #expect(form.config.limits.maxBatchChars == 900)
}

@Test func editingTheShortcutReachesTheBinding() {
    var form = loadedForm()
    form.shortcut = "cmd+alt+k"
    #expect(form.config.hotkeys.first?.shortcut == "cmd+alt+k")
    // The source and sink the rest of the app relies on are left alone.
    #expect(form.config.hotkeys.first?.source == "clipboard")
}

@Test func aFileWithNoBindingGetsOneOnLoad() {
    // `hotkeys: []` parses fine and leaves nothing to register. Repairing it on
    // load means the rest of the form can assume a binding exists.
    let form = loadedForm { $0.hotkeys = [] }
    #expect(form.config.hotkeys.count == 1)
    #expect(form.config.hotkeys[0].source == "clipboard")
    #expect(form.config.hotkeys[0].sink == "clipboard")
}

@Test func reopeningDiscardsAnUnsavedEdit() {
    var form = loadedForm()
    form.shortcut = "cmd+alt+k"
    form.config.features.history = false

    form.load(from: .builtIn)

    #expect(form.shortcut == Config.builtIn.hotkeys[0].shortcut)
    #expect(form.config.features.history)
}

// MARK: - Saving

@Test func anUnreadableShortcutBlocksSavingInBothModes() {
    // The shortcut is stored whichever trigger is chosen, so it has to parse
    // whichever trigger is chosen — otherwise switching back later would leave
    // the app with no trigger at all.
    for kind in TriggerKind.allCases {
        var form = loadedForm { $0.trigger.kind = kind }
        form.shortcut = "cmd+ctr+d"
        #expect(form.canSave == false, "\(kind) should refuse an unreadable shortcut")
    }
}

@Test func aReadableShortcutAllowsSavingInBothModes() {
    for kind in TriggerKind.allCases {
        var form = loadedForm { $0.trigger.kind = kind }
        form.shortcut = "cmd+alt+k"
        #expect(form.canSave, "\(kind) should accept a readable shortcut")
    }
}

@Test func anEmptyShortcutIsNotSaveable() {
    var form = loadedForm()
    form.shortcut = ""
    #expect(form.canSave == false)
}

@Test func aProfileThatDoesNotExistBlocksSaving() {
    // Config.validate already refuses this; the form asks it rather than
    // keeping a second copy of the rule.
    let form = loadedForm { $0.activeProfile = "neexistuje" }
    #expect(form.canSave == false)
    #expect(form.configProblem != nil)
}

@Test func anEndpointWithoutASchemeBlocksSaving() {
    let form = loadedForm {
        $0.profiles["local"]?.endpoint = URL(string: "localhost:11434")!
    }
    #expect(form.canSave == false)
    #expect(form.configProblem?.isEmpty == false)
}

@Test func aSoundConfigurationHasNothingToReport() {
    let form = loadedForm()
    #expect(form.canSave)
    #expect(form.configProblem == nil)
}

// MARK: - Validity and warnings

@Test func validityFollowsTheTextWithNothingToKeepInSync() {
    var form = loadedForm()
    #expect(form.shortcutIsValid)
    form.shortcut = "nesmysl+++"
    #expect(form.shortcutIsValid == false)
    form.shortcut = "ctrl+shift+p"
    #expect(form.shortcutIsValid)
}

@Test func warnsAboutACombinationEveryApplicationUses() {
    var form = loadedForm()
    form.shortcut = "cmd+b"
    #expect(form.warning?.contains("běžná systémová zkratka") == true)
    // Advisory only — the user may genuinely want it.
    #expect(form.canSave)
}

@Test func staysQuietAboutACombinationNothingElseClaims() {
    var form = loadedForm()
    form.shortcut = "cmd+shift+d"
    #expect(form.warning == nil)
}

@Test func explainsAnUnreadableShortcutWithAnExample() {
    var form = loadedForm()
    form.shortcut = "cmd+ctr+d"
    #expect(form.warning?.contains("cmd+ctrl+d") == true)
}

@Test func loadIsNotAUserAction() {
    // The window used to ask macOS for the Accessibility permission the moment
    // it opened, because load() assigning the trigger kind is indistinguishable
    // from the user picking it. Nothing here decides anything about permissions.
    let form = loadedForm { $0.trigger.kind = .doubleTap }
    #expect(form.config.trigger.kind == .doubleTap)
    #expect(form.canSave)
}

// MARK: - Personal dictionary

@Test func dictionaryRowsLoadFromTheConfig() {
    let form = loadedForm { $0.dictionary = [DictionaryRule(from: "docs", to: "docs")] }
    #expect(form.dictionaryRows.map(\.from) == ["docs"])
}

@Test func aNewRowCopiesTheInputIntoTheTarget() {
    var form = loadedForm()
    form.addDictionaryRow(copying: "google docs")
    #expect(form.dictionaryRows.last?.to == "google docs")
}

@Test func aRowThatChangesLettersBlocksSaving() {
    var form = loadedForm()
    form.addDictionaryRow(copying: "teda")
    form.dictionaryRows[0].to = "tedy"
    #expect(form.dictionaryProblem(for: form.dictionaryRows[0].id) != nil)
    #expect(!form.canSave)
}

@Test func aDuplicateRowBlocksSaving() {
    var form = loadedForm()
    form.addDictionaryRow(copying: "rad")
    form.dictionaryRows[0].to = "rád"
    form.addDictionaryRow(copying: "Rad")
    form.dictionaryRows[1].to = "řad"
    #expect(form.dictionaryProblem(for: form.dictionaryRows[0].id) == nil)
    #expect(form.dictionaryProblem(for: form.dictionaryRows[1].id) != nil)
    #expect(!form.canSave)
}

@Test func anEmptyRowIsDroppedNotRejected() {
    var form = loadedForm()
    form.addDictionaryRow()
    #expect(form.canSave)
    #expect(form.resolvedConfig.dictionary.isEmpty)
}

@Test func aSingleWordRuleWarnsButSaves() {
    var form = loadedForm()
    form.addDictionaryRow(copying: "rad")
    form.dictionaryRows[0].to = "rád"
    #expect(form.dictionaryWarning(for: form.dictionaryRows[0].id)?.contains("chce byt") == true)
    #expect(form.canSave)
    form.dictionaryRows[0].from = "chce byt"
    form.dictionaryRows[0].to = "chce být"
    #expect(form.dictionaryWarning(for: form.dictionaryRows[0].id) == nil)
}

@Test func removingARowDropsItFromTheConfig() {
    var form = loadedForm { $0.dictionary = [DictionaryRule(from: "docs", to: "docs")] }
    form.removeDictionaryRow(id: form.dictionaryRows[0].id)
    #expect(form.resolvedConfig.dictionary.isEmpty)
}

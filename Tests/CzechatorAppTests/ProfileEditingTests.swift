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

// MARK: - Which profile the fields are showing

@Test func startsOnTheProfileInUse() {
    let form = loadedForm { $0.activeProfile = "openai" }
    #expect(form.editedProfile == "openai")
    #expect(form.editedProfileName == "openai")
}

@Test func listsProfilesInAStableOrder() {
    let form = loadedForm()
    #expect(form.profileNames == form.profileNames.sorted())
    #expect(form.profileNames.contains("local"))
}

// MARK: - Adding

@Test func addingGivesANameThatIsNotTakenAndSelectsIt() {
    var form = loadedForm()
    let before = form.profileNames.count

    form.addProfile()

    #expect(form.profileNames.count == before + 1)
    // The new one is what the fields below now describe, or adding it would
    // look like nothing happened.
    #expect(form.config.profiles[form.editedProfile] != nil)
    #expect(form.editedProfileName == form.editedProfile)
    #expect(form.canSave)
}

@Test func addingTwiceDoesNotCollide() {
    var form = loadedForm()
    form.addProfile()
    let first = form.editedProfile
    form.addProfile()

    #expect(form.editedProfile != first)
    #expect(form.profileNames.count == Set(form.profileNames).count)
    #expect(form.canSave)
}

@Test func aNewProfileDoesNotChangeWhichOneIsInUse() {
    // Adding is not choosing. The active profile is a separate decision.
    var form = loadedForm { $0.activeProfile = "local" }
    form.addProfile()
    #expect(form.config.activeProfile == "local")
}

// MARK: - Removing

@Test func removingTheProfileInUseFallsBackToAnother() {
    // Leaving activeProfile pointing at nothing would make the config
    // unloadable — Config.validate refuses it, so saving would be blocked with
    // no obvious way out.
    var form = loadedForm { $0.activeProfile = "openai" }
    form.selectProfile("openai")

    form.removeEditedProfile()

    #expect(form.config.profiles["openai"] == nil)
    #expect(form.config.profiles[form.config.activeProfile] != nil)
    #expect(form.canSave)
}

@Test func removingAnUnusedProfileLeavesTheActiveOneAlone() {
    var form = loadedForm { $0.activeProfile = "local" }
    form.selectProfile("openai")

    form.removeEditedProfile()

    #expect(form.config.activeProfile == "local")
    #expect(form.config.profiles["local"] != nil)
}

@Test func theLastProfileCannotBeRemoved() {
    // An application with no profile has nothing to talk to.
    var form = loadedForm { $0.profiles = ["local": $0.profiles["local"]!] }
    #expect(form.canRemoveProfile == false)

    form.removeEditedProfile()

    #expect(form.profileNames == ["local"])
}

@Test func removingLeavesTheFieldsShowingSomethingReal() {
    var form = loadedForm()
    form.selectProfile("openai")
    form.removeEditedProfile()
    #expect(form.config.profiles[form.editedProfile] != nil)
    #expect(form.editedProfileName == form.editedProfile)
}

// MARK: - Renaming

@Test func renamingKeepsTheProfileAndItsSettings() {
    var form = loadedForm()
    form.selectProfile("local")
    let model = form.config.profiles["local"]?.model

    form.editedProfileName = "domaci"
    form.commitRename()

    #expect(form.config.profiles["local"] == nil)
    #expect(form.config.profiles["domaci"]?.model == model)
    #expect(form.editedProfile == "domaci")
}

@Test func renamingTheProfileInUseFollowsIt() {
    var form = loadedForm { $0.activeProfile = "local" }
    form.selectProfile("local")

    form.editedProfileName = "domaci"
    form.commitRename()

    #expect(form.config.activeProfile == "domaci")
    #expect(form.canSave)
}

@Test func aNameAlreadyTakenIsRefusedRatherThanOverwriting() {
    // Committing it would silently destroy the other profile.
    var form = loadedForm()
    form.selectProfile("local")
    form.editedProfileName = "openai"

    #expect(form.profileNameProblem != nil)
    #expect(form.canSave == false)

    form.commitRename()
    #expect(form.config.profiles["local"] != nil)
    #expect(form.config.profiles["openai"]?.kind == .openaiCompat)
}

@Test func anEmptyNameIsRefused() {
    var form = loadedForm()
    form.editedProfileName = "   "
    #expect(form.profileNameProblem != nil)
    #expect(form.canSave == false)
}

@Test func keepingTheSameNameIsNotACollisionWithItself() {
    var form = loadedForm()
    form.selectProfile("local")
    form.editedProfileName = "local"
    #expect(form.profileNameProblem == nil)
    #expect(form.canSave)
}

@Test func switchingProfilesCommitsAPendingRename() {
    // Otherwise a name typed but not confirmed disappears without a word.
    var form = loadedForm()
    form.selectProfile("local")
    form.editedProfileName = "domaci"

    form.selectProfile("openai")

    #expect(form.config.profiles["domaci"] != nil)
    #expect(form.config.profiles["local"] == nil)
    #expect(form.editedProfile == "openai")
    #expect(form.editedProfileName == "openai")
}

@Test func switchingAwayFromABadNameKeepsTheOldOne() {
    var form = loadedForm()
    form.selectProfile("local")
    form.editedProfileName = "openai"

    form.selectProfile("openai")

    #expect(form.config.profiles["local"] != nil)
    #expect(form.profileNames.count == 2)
}

// MARK: - Editing the fields

@Test func editingReachesTheProfileBeingShown() {
    var form = loadedForm()
    form.selectProfile("local")

    form.editedProfileFields?.model = "qwen3:8b"
    form.editedProfileFields?.temperature = 0.3

    #expect(form.config.profiles["local"]?.model == "qwen3:8b")
    #expect(form.config.profiles["local"]?.temperature == 0.3)
    // And nothing else moved.
    #expect(form.config.profiles["openai"]?.model == Config.builtIn.profiles["openai"]?.model)
}

@Test func anEndpointThatIsNotAURLBlocksSaving() {
    var form = loadedForm()
    form.selectProfile("local")
    form.editedProfileFields?.endpoint = URL(string: "localhost:11434")!
    #expect(form.canSave == false)
}

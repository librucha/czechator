import CzechatorCore
import Testing

@testable import CzechatorApp

private func loadedForm() -> SettingsFormState {
    var form = SettingsFormState()
    form.load(from: .builtIn)
    return form
}

@Test func correctionSettingsHideTheBudgetInStrictMode() {
    var form = loadedForm()
    form.selectCorrectionMode(.strict)
    #expect(!form.budgetIsEditable)
    #expect(form.letterCaseIsEditable)
}

@Test func correctionSettingsShowTheBudgetInTolerantModes() {
    var form = loadedForm()
    form.selectCorrectionMode(.minorFixes)
    #expect(form.budgetIsEditable)
    // letterCase does nothing outside strict mode, so the window must stop
    // pretending it is a live control.
    #expect(!form.letterCaseIsEditable)
}

@Test func correctionSettingsSeedTheBudgetWhenTheModeChanges() {
    var form = loadedForm()
    form.selectCorrectionMode(.minorFixes)
    #expect(form.editedProfileBudget == EditBudget(percent: 20, minimum: 1))
    form.selectCorrectionMode(.proofread)
    #expect(form.editedProfileBudget == EditBudget(percent: 35, minimum: 2))
}

@Test func correctionSettingsKeepAnExplicitBudgetOverTheSeed() {
    // The seed is a one-off suggestion, not a binding: a user who tuned the
    // numbers must not have them reset by touching an unrelated control.
    var form = loadedForm()
    form.selectCorrectionMode(.minorFixes)
    form.editedProfileBudget = EditBudget(percent: 45, minimum: 3)
    form.editedProfileVerification = false
    #expect(form.editedProfileBudget == EditBudget(percent: 45, minimum: 3))
}

@Test func letterCasePopupFollowsTheActiveProfileNotTheEditedOne() {
    // Active profile goes tolerant; the profile editor is left open on a
    // different, still-strict profile. The "Velikost písmen" picker on the
    // Základní tab is bound to the active profile's setting, so it must go
    // dead — even though the profile in the editor is strict.
    var form = loadedForm()
    form.config.profiles["local"]?.corrections = .proofread
    form.selectProfile("openai")
    #expect(form.config.activeProfile == "local")
    #expect(form.editedProfile == "openai")
    #expect(form.editedProfileCorrections == .strict)
    #expect(!form.letterCaseIsEditable)
}

@Test func correctionSettingsAreStoredOnTheEditedProfileOnly() {
    var form = loadedForm()
    let edited = form.editedProfile
    form.selectCorrectionMode(.proofread)
    #expect(form.config.profiles[edited]?.corrections == .proofread)
    for (name, profile) in form.config.profiles where name != edited {
        #expect(profile.corrections == .strict)
    }
}

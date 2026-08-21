import CzechatorCore
import Foundation
import Testing

@testable import CzechatorApp

// macOS shows its "wants to control this computer" dialog once per app, and
// that dialog already offers both Open System Settings and Deny. Calling both
// the prompt and the settings pane at once took the Deny away: whatever the
// user chose, System Settings opened anyway.

@MainActor
@Test func theFirstAskLetsTheSystemDialogDoTheTalking() throws {
    let harness = try Harness(baseConfig + "\ntrigger:\n  kind: doubleTap\n")
    harness.granted = false
    let model = harness.startedModel()

    model.grantAccessibility()

    #expect(harness.permissionRequests == 1)
    // Not both: the dialog has its own way into System Settings, and its own
    // way out.
    #expect(harness.settingsOpened == 0)
}

@MainActor
@Test func askingAgainOpensSystemSettingsInstead() throws {
    // The dialog will not appear a second time, so a second press has to do
    // something else or the button looks broken.
    let harness = try Harness(baseConfig + "\ntrigger:\n  kind: doubleTap\n")
    harness.granted = false
    let model = harness.startedModel()

    model.grantAccessibility()
    model.grantAccessibility()
    model.grantAccessibility()

    #expect(harness.permissionRequests == 1)
    #expect(harness.settingsOpened == 2)
}

@MainActor
@Test func savingTheDoubleTapAsksStraightAway() throws {
    // Saving is the moment to ask: the user has just chosen the double tap, so
    // the dialog arrives with its reason obvious. Leaving it to a button they
    // have not looked for yet means they never find out where to go.
    let harness = try Harness(baseConfig)
    harness.granted = false
    let model = harness.startedModel()
    #expect(harness.permissionRequests == 0)

    model.applySettings(
        activeProfile: "local", shortcut: "cmd+ctrl+d",
        triggerKind: .doubleTap, triggerModifier: .rightCommand)

    #expect(harness.permissionRequests == 1)
    #expect(harness.settingsOpened == 0)
}

@MainActor
@Test func savingStaysQuietWhenThePermissionIsAlreadyThere() throws {
    let harness = try Harness(baseConfig)
    let model = harness.startedModel()

    model.applySettings(
        activeProfile: "local", shortcut: "cmd+ctrl+d",
        triggerKind: .doubleTap, triggerModifier: .rightCommand)

    #expect(harness.permissionRequests == 0)
    #expect(model.needsAccessibility == false)
}

@MainActor
@Test func savingTheCombinationNeverAsks() throws {
    let harness = try Harness(baseConfig)
    harness.granted = false
    let model = harness.startedModel()

    model.applySettings(
        activeProfile: "local", shortcut: "cmd+ctrl+d",
        triggerKind: .combination, triggerModifier: .rightCommand)

    #expect(harness.permissionRequests == 0)
    #expect(harness.settingsOpened == 0)
}

@MainActor
@Test func launchingAndRecheckingNeverAsk() throws {
    // Only saving and the button may raise a dialog. Starting the app with the
    // double tap already chosen must not, or every launch would interrupt.
    let harness = try Harness(baseConfig + "\ntrigger:\n  kind: doubleTap\n")
    harness.granted = false
    let model = harness.startedModel()

    model.refreshAccessibilityState()
    model.reload()

    #expect(harness.permissionRequests == 0)
    #expect(harness.settingsOpened == 0)
}

@MainActor
@Test func theButtonAfterSavingGoesToSystemSettings() throws {
    // Saving used up the one dialog macOS will show, so the button in the menu
    // has to lead somewhere that still works.
    let harness = try Harness(baseConfig)
    harness.granted = false
    let model = harness.startedModel()

    model.applySettings(
        activeProfile: "local", shortcut: "cmd+ctrl+d",
        triggerKind: .doubleTap, triggerModifier: .rightCommand)
    model.grantAccessibility()

    #expect(harness.permissionRequests == 1)
    #expect(harness.settingsOpened == 1)
}

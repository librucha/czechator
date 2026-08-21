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
@Test func nothingIsAskedWithoutTheUserAskingForIt() throws {
    // Reloading, re-checking the permission, saving — none of it may raise a
    // system dialog. Only the button does.
    let harness = try Harness(baseConfig + "\ntrigger:\n  kind: doubleTap\n")
    harness.granted = false
    let model = harness.startedModel()

    model.refreshAccessibilityState()
    model.applySettings(
        activeProfile: "local", shortcut: "cmd+ctrl+d",
        triggerKind: .doubleTap, triggerModifier: .rightCommand)
    model.reload()

    #expect(harness.permissionRequests == 0)
    #expect(harness.settingsOpened == 0)
}

import CzechatorCore
import Foundation
import Testing

@testable import CzechatorApp

// The settings window is the only thing in the whole project that writes the
// config file — the CLI never does. These tests are about what actually lands
// on disk, and what the app does with it immediately afterwards.

@MainActor
@Test func writesEveryFieldTheWindowCanChange() throws {
    let harness = try Harness(baseConfig)
    let model = harness.startedModel()

    model.applyChange {
        $0.activeProfile = "openai"
        $0.hotkeys[0].shortcut = "cmd+alt+k"
        $0.trigger.kind = .doubleTap
        $0.trigger.modifier = .leftOption
    }

    let saved = try harness.reloadedFromDisk()
    #expect(saved.activeProfile == "openai")
    #expect(saved.hotkeys.first?.shortcut == "cmd+alt+k")
    #expect(saved.trigger.kind == .doubleTap)
    #expect(saved.trigger.modifier == .leftOption)
}

@MainActor
@Test func theSavedSettingsSurviveARestart() throws {
    // The file is the whole point: a setting that only lives in memory is a
    // setting the user loses on the next launch.
    let harness = try Harness(baseConfig)
    harness.startedModel().applyChange {
        $0.activeProfile = "openai"
        $0.hotkeys[0].shortcut = "ctrl+shift+p"
        $0.trigger.kind = .doubleTap
        $0.trigger.modifier = .rightOption
    }

    let fresh = harness.startedModel()
    #expect(fresh.currentConfig.activeProfile == "openai")
    #expect(fresh.currentConfig.hotkeys[0].shortcut == "ctrl+shift+p")
    #expect(fresh.currentConfig.trigger.kind == .doubleTap)
    #expect(fresh.currentConfig.trigger.modifier == .rightOption)
}

@MainActor
@Test func doesNotDisturbTheRestOfTheFile() throws {
    // Saving from the window must not quietly rewrite settings the window does
    // not show — the profiles, the limits, the segmentation rules the user
    // tuned by hand, or a key this version has never heard of.
    let harness = try Harness(baseConfig + "\nmojePoznamka: nesahat\n")
    let model = harness.startedModel()

    model.applyChange {
        $0.activeProfile = "local"
        $0.hotkeys[0].shortcut = "cmd+ctrl+d"
        $0.trigger.kind = .doubleTap
        $0.trigger.modifier = .rightCommand
    }

    let text = try harness.fileContents()
    #expect(text.contains("mojePoznamka: nesahat"))

    let saved = try harness.reloadedFromDisk()
    #expect(saved.profiles.count == 2)
    #expect(saved.profiles["openai"]?.model == "gpt-4o-mini")
    #expect(saved.profiles["local"]?.model == "qwen3:4b-instruct")
}

@MainActor
@Test func reportsAConfigWithNoBindingAtAll() throws {
    // `hotkeys: []` parses fine and leaves nothing to register. The settings
    // window repairs it on load — see SettingsFormState — but a file edited by
    // hand has to say so rather than fail silently.
    let harness = try Harness(
        baseConfig.replacingOccurrences(
            of: """
                hotkeys:
                  - shortcut: cmd+ctrl+d
                    source: clipboard
                    sink: clipboard
                """, with: "hotkeys: []"))
    let model = harness.startedModel()

    #expect(harness.plans.isEmpty)
    #expect(model.startupProblem?.contains("žádnou zkratku") == true)
}

@MainActor
@Test func installsTheNewTriggerWithoutWaitingForARestart() throws {
    let harness = try Harness(baseConfig)
    let model = harness.startedModel()
    #expect(harness.plans.count == 1)

    model.applyChange {
        $0.activeProfile = "local"
        $0.hotkeys[0].shortcut = "cmd+ctrl+d"
        $0.trigger.kind = .doubleTap
        $0.trigger.modifier = .rightOption
    }

    #expect(harness.plans.count == 2)
    if case .doubleTap(let config) = harness.plans[1] {
        #expect(config.modifier == .rightOption)
    } else {
        Issue.record("expected the double tap to be installed, got \(harness.plans[1])")
    }
    // And the combination it replaced was taken down.
    #expect(harness.triggers[0].stopCount >= 1)
}

@MainActor
@Test func savingTheDoubleTapWithoutPermissionLeavesNoTrigger() throws {
    // The user can choose it before granting anything; what must not happen is
    // a silent fall back to a combination they deliberately stopped using.
    let harness = try Harness(baseConfig)
    harness.granted = false
    let model = harness.startedModel()

    model.applyChange {
        $0.activeProfile = "local"
        $0.hotkeys[0].shortcut = "cmd+ctrl+d"
        $0.trigger.kind = .doubleTap
        $0.trigger.modifier = .rightCommand
    }

    #expect(harness.plans.count == 1)  // only the original combination
    #expect(model.needsAccessibility)
    #expect(model.startupProblem == ErrorMessages.accessibilityRequired)
    // The choice still reached the file, so granting the permission later is
    // all it takes.
    #expect(try harness.reloadedFromDisk().trigger.kind == .doubleTap)
}

@MainActor
@Test func reportsAFailedWriteInsteadOfLookingLikeItWorked() throws {
    let harness = try Harness(baseConfig)
    let model = harness.startedModel()
    // Make the directory unwritable so the save cannot succeed.
    let directory = harness.url.deletingLastPathComponent()
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
    defer {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    model.applyChange {
        $0.activeProfile = "openai"
        $0.hotkeys[0].shortcut = "cmd+alt+k"
        $0.trigger.kind = .doubleTap
        $0.trigger.modifier = .leftOption
    }

    #expect(model.startupProblem != nil)
    // The old settings are still what the app is running on.
    #expect(model.currentConfig.activeProfile == "local")
}

@MainActor
@Test func refusesToSaveAConfigItCouldNotLoadBack() throws {
    // ConfigStore validates before writing. An unknown profile must not reach
    // the file, or the next launch fails on a file the user cannot easily fix.
    let harness = try Harness(baseConfig)
    let model = harness.startedModel()

    model.applyChange {
        $0.activeProfile = "neexistuje"
        $0.hotkeys[0].shortcut = "cmd+ctrl+d"
        $0.trigger.kind = .combination
        $0.trigger.modifier = .rightCommand
    }

    #expect(model.startupProblem != nil)
    #expect(try harness.reloadedFromDisk().activeProfile == "local")
}

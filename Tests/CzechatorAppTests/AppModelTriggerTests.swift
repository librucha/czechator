import CzechatorCore
import Foundation
import Testing

@testable import CzechatorApp

@MainActor
@Test func installsTheCombinationWhenThatIsWhatTheConfigSays() throws {
    let harness = try Harness(baseConfig)
    let model = harness.makeModel()
    model.reload()

    #expect(harness.plans.count == 1)
    if case .combination(let spec) = harness.plans[0] {
        #expect(spec.key == "d")
    } else {
        Issue.record("expected a combination plan, got \(harness.plans[0])")
    }
    #expect(harness.triggers[0].startCount == 1)
    #expect(model.needsAccessibility == false)
    #expect(model.startupProblem == nil)
}

@MainActor
@Test func installsNothingWhenTheDoubleTapHasNoPermission() throws {
    // The point of the whole feature: no silent fallback to a combination that
    // steals a shortcut the user deliberately stopped stealing.
    let harness = try Harness(baseConfig + "\ntrigger:\n  kind: doubleTap\n")
    harness.granted = false
    let model = harness.makeModel()
    model.reload()

    #expect(harness.plans.isEmpty)
    #expect(model.needsAccessibility)
    #expect(model.startupProblem == ErrorMessages.accessibilityRequired)
}

@MainActor
@Test func installsTheDoubleTapOncePermitted() throws {
    let harness = try Harness(
        baseConfig + "\ntrigger:\n  kind: doubleTap\n  modifier: leftOption\n  intervalMs: 250\n")
    let model = harness.makeModel()
    model.reload()

    #expect(harness.plans.count == 1)
    if case .doubleTap(let config) = harness.plans[0] {
        #expect(config.modifier == .leftOption)
        #expect(config.intervalMs == 250)
    } else {
        Issue.record("expected a double-tap plan, got \(harness.plans[0])")
    }
    #expect(model.needsAccessibility == false)
    #expect(model.startupProblem == nil)
}

@MainActor
@Test func stopsThePreviousTriggerBeforeInstallingTheNext() throws {
    // The claim the removed deinits rest on. If it stops being true, an NSEvent
    // monitor or a Carbon registration outlives the object that owns it.
    let harness = try Harness(baseConfig)
    let model = harness.makeModel()
    model.reload()
    model.reload()

    #expect(harness.triggers.count == 2)
    #expect(harness.triggers[0].stopCount >= 1)
    #expect(harness.triggers[1].startCount == 1)
}

@MainActor
@Test func reportsAnUnreadableShortcutInsteadOfInstallingNothingQuietly() throws {
    let harness = try Harness(
        baseConfig.replacingOccurrences(of: "cmd+ctrl+d", with: "cmd+ctr+d"))
    let model = harness.makeModel()
    model.reload()

    #expect(harness.plans.isEmpty)
    #expect(model.startupProblem != nil)
}

@MainActor
@Test func reportsAFailedRegistrationInCzech() throws {
    let harness = try Harness(baseConfig)
    harness.nextFailure = HotKeyManager.HotKeyError.registrationFailed(-9878)
    let model = harness.makeModel()
    model.reload()

    let problem = try #require(model.startupProblem)
    // The message that used to read "registrationFailed(-9878)".
    #expect(problem.contains("jiná aplikace"))
    #expect(!problem.contains("-9878"))
}

@MainActor
@Test func noticesThePermissionAppearingWhileTheAppRuns() throws {
    let harness = try Harness(baseConfig + "\ntrigger:\n  kind: doubleTap\n")
    harness.granted = false
    let model = harness.makeModel()
    model.reload()
    #expect(model.needsAccessibility)

    harness.granted = true
    model.refreshAccessibilityState()

    #expect(model.needsAccessibility == false)
    #expect(harness.plans.count == 1)
}

@MainActor
@Test func noticesThePermissionBeingRevokedWhileTheAppRuns() throws {
    let harness = try Harness(baseConfig + "\ntrigger:\n  kind: doubleTap\n")
    let model = harness.makeModel()
    model.reload()
    #expect(harness.plans.count == 1)

    harness.granted = false
    model.refreshAccessibilityState()

    #expect(model.needsAccessibility)
    #expect(harness.triggers[0].stopCount >= 1)
}

@MainActor
@Test func doesNotChurnWhenNothingAboutThePermissionChanged() throws {
    // refreshAccessibilityState runs on every menu open and every activation.
    // Re-registering the trigger each time would be wasted work at best.
    let harness = try Harness(baseConfig + "\ntrigger:\n  kind: doubleTap\n")
    let model = harness.makeModel()
    model.reload()
    model.refreshAccessibilityState()
    model.refreshAccessibilityState()

    #expect(harness.plans.count == 1)
}

@MainActor
@Test func leavesTheCombinationAloneOnAPermissionCheck() throws {
    let harness = try Harness(baseConfig)
    let model = harness.makeModel()
    model.reload()
    harness.granted = false
    model.refreshAccessibilityState()

    #expect(harness.plans.count == 1)
    #expect(model.needsAccessibility == false)
}

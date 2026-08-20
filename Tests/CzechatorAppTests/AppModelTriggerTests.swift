import CzechatorCore
import Foundation
import Testing

@testable import CzechatorApp

/// A trigger that records what was asked of it instead of touching the system.
@MainActor
private final class SpyTrigger: Trigger {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    var failToStart: (any Error)?

    func start(_ action: @escaping @MainActor () -> Void) throws {
        if let failToStart { throw failToStart }
        startCount += 1
    }

    func stop() { stopCount += 1 }
}

@MainActor
private final class Harness {
    let url: URL
    private(set) var plans: [TriggerPlan] = []
    private(set) var triggers: [SpyTrigger] = []
    var granted = true
    var nextFailure: (any Error)?

    init(_ yaml: String) throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("czechator-\(UUID().uuidString)")
            .appendingPathComponent("config.yaml")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }

    func makeModel() -> AppModel {
        AppModel(
            store: ConfigStore(url: url),
            accessibilityGranted: { [unowned self] in self.granted },
            makeTrigger: { [unowned self] plan in
                self.plans.append(plan)
                let spy = SpyTrigger()
                spy.failToStart = self.nextFailure
                self.triggers.append(spy)
                return spy
            })
    }
}

private let base = """
    activeProfile: local
    profiles:
      local:
        kind: ollama
        endpoint: http://localhost:11434
        model: qwen3:4b-instruct
        temperature: 0
        timeoutSeconds: 30
    hotkeys:
      - shortcut: cmd+ctrl+d
        source: clipboard
        sink: clipboard
    """

@MainActor
@Test func installsTheCombinationWhenThatIsWhatTheConfigSays() throws {
    let harness = try Harness(base)
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
    let harness = try Harness(base + "\ntrigger:\n  kind: doubleTap\n")
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
        base + "\ntrigger:\n  kind: doubleTap\n  modifier: leftOption\n  intervalMs: 250\n")
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
    let harness = try Harness(base)
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
        base.replacingOccurrences(of: "cmd+ctrl+d", with: "cmd+ctr+d"))
    let model = harness.makeModel()
    model.reload()

    #expect(harness.plans.isEmpty)
    #expect(model.startupProblem != nil)
}

@MainActor
@Test func reportsAFailedRegistrationInCzech() throws {
    let harness = try Harness(base)
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
    let harness = try Harness(base + "\ntrigger:\n  kind: doubleTap\n")
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
    let harness = try Harness(base + "\ntrigger:\n  kind: doubleTap\n")
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
    let harness = try Harness(base + "\ntrigger:\n  kind: doubleTap\n")
    let model = harness.makeModel()
    model.reload()
    model.refreshAccessibilityState()
    model.refreshAccessibilityState()

    #expect(harness.plans.count == 1)
}

@MainActor
@Test func leavesTheCombinationAloneOnAPermissionCheck() throws {
    let harness = try Harness(base)
    let model = harness.makeModel()
    model.reload()
    harness.granted = false
    model.refreshAccessibilityState()

    #expect(harness.plans.count == 1)
    #expect(model.needsAccessibility == false)
}

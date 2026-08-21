import AppKit
import CzechatorCore
import Foundation
import Testing

@testable import CzechatorApp

// Opening the menu bar menu is one of the two ways the user dismisses an error
// badge, and it used to be wired to `.onAppear` on the menu's content — which
// SwiftUI runs once, when it builds that content at launch, and never again.
// Measured: two menu opens produced no callback at all.

@MainActor
@Test func openingTheMenuIsNoticedAtAll() throws {
    // The wiring is observed through the permission re-check, which shares the
    // same hook: nothing else about the model is reachable from a test without
    // driving a real correction.
    let harness = try Harness(baseConfig + "\ntrigger:\n  kind: doubleTap\n")
    harness.granted = false
    let model = harness.startedModel()
    #expect(model.needsAccessibility)
    #expect(harness.plans.isEmpty)

    harness.granted = true
    NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: nil)

    #expect(model.needsAccessibility == false)
    #expect(harness.plans.count == 1)
}

@MainActor
@Test func aMenuOpenedBeforeTheModelStartedChangesNothing() {
    // The observer is installed by start(); posting before that must not reach
    // a model that has not read its config yet.
    NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: nil)
}

@MainActor
@Test func theMenuHookSurvivesRepeatedOpens() throws {
    let harness = try Harness(baseConfig + "\ntrigger:\n  kind: doubleTap\n")
    let model = harness.startedModel()
    #expect(harness.plans.count == 1)

    for _ in 0..<3 {
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: nil)
    }

    // Nothing changed about the permission, so nothing should be re-installed.
    #expect(harness.plans.count == 1)
    #expect(model.needsAccessibility == false)
}

import AppKit
import CzechatorCore
import Foundation
import Testing

@testable import CzechatorApp

/// Builds the kind of event a real keyboard produces for a modifier change.
///
/// `flagsChanged` carries no up/down bit — whether the key is down is inferred
/// from the modifier flag still being set, which is the ambiguity these tests
/// exist to pin down.
private func flagsChanged(keyCode: Int, flags: NSEvent.ModifierFlags, at time: TimeInterval)
    -> NSEvent
{
    NSEvent.keyEvent(
        with: .flagsChanged, location: .zero, modifierFlags: flags,
        timestamp: time, windowNumber: 0, context: nil,
        characters: "", charactersIgnoringModifiers: "", isARepeat: false,
        keyCode: UInt16(keyCode))!
}

private func keyDown(_ keyCode: Int, at time: TimeInterval) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [],
        timestamp: time, windowNumber: 0, context: nil,
        characters: "a", charactersIgnoringModifiers: "a", isARepeat: false,
        keyCode: UInt16(keyCode))!
}

@Test func readsAPressFromTheFlagStillBeingSet() {
    let event = flagsChanged(keyCode: 54, flags: [.command], at: 1)
    #expect(
        DoubleTapMonitor.translate(event, watching: .rightCommand)
            == .modifierPressed(.rightCommand))
}

@Test func readsAReleaseFromTheFlagBeingGone() {
    let event = flagsChanged(keyCode: 54, flags: [], at: 1)
    #expect(
        DoubleTapMonitor.translate(event, watching: .rightCommand)
            == .modifierReleased(.rightCommand))
}

@Test func theOtherSideOfTheSameKeyIsAnotherModifier() {
    // Left cmd while watching right cmd must not read as the watched key, or
    // cmd+C typed with the left hand would look like a tap.
    let event = flagsChanged(keyCode: 55, flags: [.command], at: 1)
    #expect(DoubleTapMonitor.translate(event, watching: .rightCommand) == .otherModifierChanged)
}

@Test func anUnknownModifierIsAnotherModifier() {
    // Shift (56) is not one of the four the trigger knows.
    let event = flagsChanged(keyCode: 56, flags: [.shift], at: 1)
    #expect(DoubleTapMonitor.translate(event, watching: .rightCommand) == .otherModifierChanged)
}

@Test func anyKeyDownSpoilsTheTap() {
    #expect(DoubleTapMonitor.translate(keyDown(0, at: 1), watching: .rightCommand) == .otherKeyDown)
}

@Test func aMouseEventIsIgnoredEntirely() {
    let click = NSEvent.mouseEvent(
        with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 1,
        windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    #expect(DoubleTapMonitor.translate(click, watching: .rightCommand) == nil)
}

@Test func bothCommandKeysHeldFailsClosed() {
    // The documented ambiguity, end to end through the real detector: with both
    // command keys down the flag outlives the first release, so that release
    // arrives as a second press. The result must be no trigger — never a
    // spurious one, which would rewrite the clipboard uninvited.
    var detector = DoubleTapDetector(modifier: .rightCommand, intervalMs: 300, maxHoldMs: 500)
    let events = [
        flagsChanged(keyCode: 54, flags: [.command], at: 0.00),  // right down
        flagsChanged(keyCode: 55, flags: [.command], at: 0.05),  // left down too
        flagsChanged(keyCode: 54, flags: [.command], at: 0.10),  // right up, flag remains
        flagsChanged(keyCode: 55, flags: [], at: 0.15),  // left up
    ]
    let fired = events.reduce(0) { count, event in
        guard let translated = DoubleTapMonitor.translate(event, watching: .rightCommand) else {
            return count
        }
        return count + (detector.accept(translated, at: event.timestamp) ? 1 : 0)
    }
    #expect(fired == 0)
}

@Test func aRealDoubleTapSurvivesTheWholeChain() {
    // The counterpart: the same path a genuine double tap takes, using the
    // timings measured from an actual keyboard (44 ms hold, 78 ms gap).
    var detector = DoubleTapDetector(modifier: .rightCommand, intervalMs: 300, maxHoldMs: 500)
    let events = [
        flagsChanged(keyCode: 54, flags: [.command], at: 0.000),
        flagsChanged(keyCode: 54, flags: [], at: 0.044),
        flagsChanged(keyCode: 54, flags: [.command], at: 0.122),
        flagsChanged(keyCode: 54, flags: [], at: 0.179),
    ]
    let fired = events.reduce(0) { count, event in
        guard let translated = DoubleTapMonitor.translate(event, watching: .rightCommand) else {
            return count
        }
        return count + (detector.accept(translated, at: event.timestamp) ? 1 : 0)
    }
    #expect(fired == 1)
}

@Test func mapsEachModifierToTheFlagItSets() {
    #expect(ModifierKey.rightCommand.flag == .command)
    #expect(ModifierKey.leftCommand.flag == .command)
    #expect(ModifierKey.rightOption.flag == .option)
    #expect(ModifierKey.leftOption.flag == .option)
}

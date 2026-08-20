import Foundation
import Testing

@testable import CzechatorCore

private func detector(
    _ modifier: ModifierKey = .rightCommand,
    intervalMs: Int = 300,
    maxHoldMs: Int = 500
) -> DoubleTapDetector {
    DoubleTapDetector(modifier: modifier, intervalMs: intervalMs, maxHoldMs: maxHoldMs)
}

/// Feeds a sequence and returns how many times the detector fired.
private func fires(_ steps: [(DoubleTapEvent, TimeInterval)], into d: inout DoubleTapDetector)
    -> Int
{
    steps.reduce(0) { $0 + (d.accept($1.0, at: $1.1) ? 1 : 0) }
}

@Test func honestDoubleTapFires() {
    var d = detector()
    let count = fires(
        [
            (.modifierPressed(.rightCommand), 0.00),
            (.modifierReleased(.rightCommand), 0.05),
            (.modifierPressed(.rightCommand), 0.20),
            (.modifierReleased(.rightCommand), 0.25),
        ], into: &d)
    #expect(count == 1)
}

@Test func commandCDoesNotFire() {
    // A key pressed while the modifier is held means the user typed a shortcut.
    var d = detector()
    let count = fires(
        [
            (.modifierPressed(.rightCommand), 0.00),
            (.otherKeyDown, 0.02),
            (.modifierReleased(.rightCommand), 0.05),
            (.modifierPressed(.rightCommand), 0.20),
            (.modifierReleased(.rightCommand), 0.25),
        ], into: &d)
    #expect(count == 0)
}

@Test func addingAnotherModifierDoesNotFire() {
    var d = detector()
    let count = fires(
        [
            (.modifierPressed(.rightCommand), 0.00),
            (.otherModifierChanged, 0.02),
            (.modifierReleased(.rightCommand), 0.05),
            (.modifierPressed(.rightCommand), 0.20),
            (.modifierReleased(.rightCommand), 0.25),
        ], into: &d)
    #expect(count == 0)
}

@Test func holdingTooLongDoesNotFire() {
    // Holding cmd while cycling windows with Tab must not count as a tap.
    var d = detector(maxHoldMs: 500)
    let count = fires(
        [
            (.modifierPressed(.rightCommand), 0.00),
            (.modifierReleased(.rightCommand), 0.60),
            (.modifierPressed(.rightCommand), 0.70),
            (.modifierReleased(.rightCommand), 0.75),
        ], into: &d)
    #expect(count == 0)
}

@Test func secondTapTooLateDoesNotFire() {
    var d = detector(intervalMs: 300)
    let count = fires(
        [
            (.modifierPressed(.rightCommand), 0.00),
            (.modifierReleased(.rightCommand), 0.05),
            (.modifierPressed(.rightCommand), 0.40),
            (.modifierReleased(.rightCommand), 0.45),
        ], into: &d)
    #expect(count == 0)
}

@Test func tripleTapFiresExactlyOnce() {
    var d = detector()
    let count = fires(
        [
            (.modifierPressed(.rightCommand), 0.00),
            (.modifierReleased(.rightCommand), 0.05),
            (.modifierPressed(.rightCommand), 0.15),
            (.modifierReleased(.rightCommand), 0.20),
            (.modifierPressed(.rightCommand), 0.30),
            (.modifierReleased(.rightCommand), 0.35),
        ], into: &d)
    #expect(count == 1)
}

@Test func theOtherSideDoesNotFire() {
    var d = detector(.rightCommand)
    let count = fires(
        [
            (.modifierPressed(.leftCommand), 0.00),
            (.modifierReleased(.leftCommand), 0.05),
            (.modifierPressed(.leftCommand), 0.20),
            (.modifierReleased(.leftCommand), 0.25),
        ], into: &d)
    #expect(count == 0)
}

@Test func boundariesAreInclusive() {
    // Exactly at the limit still counts; one millisecond past does not.
    //
    // The timings here are chosen to be exact in binary (0.5, 0.25) so that the
    // test measures the comparison — `<=` rather than `<` — and not floating
    // point drift: 0.8 - 0.5 is 0.30000000000000004, which is past a 300 ms
    // interval by a hair.
    var atLimit = detector(intervalMs: 250, maxHoldMs: 500)
    #expect(
        fires(
            [
                (.modifierPressed(.rightCommand), 0.0),
                (.modifierReleased(.rightCommand), 0.5),
                (.modifierPressed(.rightCommand), 0.75),
                (.modifierReleased(.rightCommand), 0.80),
            ], into: &atLimit) == 1)

    // One tick past the interval: the first tap is clean and short, only the
    // gap is too wide. Without the separate case this half re-tested maxHoldMs.
    var pastInterval = detector(intervalMs: 250, maxHoldMs: 500)
    #expect(
        fires(
            [
                (.modifierPressed(.rightCommand), 0.0),
                (.modifierReleased(.rightCommand), 0.25),
                (.modifierPressed(.rightCommand), 0.5009765625),
                (.modifierReleased(.rightCommand), 0.55),
            ], into: &pastInterval) == 0)

    // One tick past the hold: the gap is fine, the first press was held too
    // long to count as a tap.
    var pastHold = detector(intervalMs: 250, maxHoldMs: 500)
    #expect(
        fires(
            [
                (.modifierPressed(.rightCommand), 0.0),
                (.modifierReleased(.rightCommand), 0.5009765625),
                (.modifierPressed(.rightCommand), 0.6),
                (.modifierReleased(.rightCommand), 0.65),
            ], into: &pastHold) == 0)
}

@Test func aKeyPressedBetweenTheTapsCancelsTheFirst() {
    // The gap is not a free window: typing in it means the first tap was part
    // of something else.
    var d = detector()
    let count = fires(
        [
            (.modifierPressed(.rightCommand), 0.00),
            (.modifierReleased(.rightCommand), 0.05),
            (.otherKeyDown, 0.08),
            (.modifierPressed(.rightCommand), 0.15),
            (.modifierReleased(.rightCommand), 0.20),
        ], into: &d)
    #expect(count == 0)
}

@Test func aKeyPressedDuringTheSecondTapCancelsIt() {
    var d = detector()
    let count = fires(
        [
            (.modifierPressed(.rightCommand), 0.00),
            (.modifierReleased(.rightCommand), 0.05),
            (.modifierPressed(.rightCommand), 0.15),
            (.otherKeyDown, 0.17),
            (.modifierReleased(.rightCommand), 0.20),
        ], into: &d)
    #expect(count == 0)
}

@Test func aSecondTapHeldTooLongDoesNotFire() {
    var d = detector(maxHoldMs: 500)
    let count = fires(
        [
            (.modifierPressed(.rightCommand), 0.00),
            (.modifierReleased(.rightCommand), 0.05),
            (.modifierPressed(.rightCommand), 0.15),
            (.modifierReleased(.rightCommand), 0.80),
        ], into: &d)
    #expect(count == 0)
}

@Test func unexpectedOrderResetsInsteadOfGuessing() {
    // A release without a press, or a press without a release, must not leave
    // half a pair behind that a later event could complete.
    var d = detector()
    let count = fires(
        [
            (.modifierReleased(.rightCommand), 0.00),
            (.modifierPressed(.rightCommand), 0.05),
            (.modifierPressed(.rightCommand), 0.10),
            (.modifierReleased(.rightCommand), 0.15),
        ], into: &d)
    #expect(count == 0)
}

@Test func bothSidesHeldAtOnceDoesNotFire() {
    // With both command keys down the flag stays set when one is released, so
    // the monitor reports a second press instead of a release. The detector has
    // to fail closed on that: no trigger, rather than a spurious one.
    var d = detector()
    let count = fires(
        [
            (.modifierPressed(.rightCommand), 0.00),
            (.modifierPressed(.rightCommand), 0.05),
            (.modifierPressed(.rightCommand), 0.10),
            (.modifierReleased(.rightCommand), 0.15),
        ], into: &d)
    #expect(count == 0)
}

@Test func firingResetsSoTheNextDoubleTapAlsoWorks() {
    var d = detector()
    let first = fires(
        [
            (.modifierPressed(.rightCommand), 0.00),
            (.modifierReleased(.rightCommand), 0.05),
            (.modifierPressed(.rightCommand), 0.15),
            (.modifierReleased(.rightCommand), 0.20),
        ], into: &d)
    let second = fires(
        [
            (.modifierPressed(.rightCommand), 5.00),
            (.modifierReleased(.rightCommand), 5.05),
            (.modifierPressed(.rightCommand), 5.15),
            (.modifierReleased(.rightCommand), 5.20),
        ], into: &d)
    #expect(first == 1)
    #expect(second == 1)
}

@Test func aSpoiledFirstTapDoesNotBecomeTheSecond() {
    // cmd+C then a genuine tap: the spoiled press must not leave the detector
    // one tap away from firing.
    var d = detector()
    let count = fires(
        [
            (.modifierPressed(.rightCommand), 0.00),
            (.otherKeyDown, 0.02),
            (.modifierReleased(.rightCommand), 0.05),
            (.modifierPressed(.rightCommand), 0.10),
            (.modifierReleased(.rightCommand), 0.15),
        ], into: &d)
    #expect(count == 0)
}

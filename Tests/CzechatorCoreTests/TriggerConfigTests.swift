import Foundation
import Testing

@testable import CzechatorCore

@Test func defaultsToTheCombinationTrigger() {
    // An upgrade must not change anyone's behaviour: a config written before
    // this feature existed has no trigger block at all.
    #expect(TriggerConfig.builtIn.kind == .combination)
    #expect(TriggerConfig.builtIn.modifier == .rightCommand)
    #expect(TriggerConfig.builtIn.intervalMs == 300)
    #expect(TriggerConfig.builtIn.maxHoldMs == 500)
}

@Test func triggerFillsMissingKeysFromDefaults() throws {
    let json = Data(#"{"kind":"doubleTap"}"#.utf8)
    let config = try JSONDecoder().decode(TriggerConfig.self, from: json)
    #expect(config.kind == .doubleTap)
    #expect(config.modifier == .rightCommand)
    #expect(config.intervalMs == 300)
    #expect(config.maxHoldMs == 500)
}

@Test func clampsNonsensicalTimingsFromTheFile() throws {
    let tooSmall = try JSONDecoder().decode(
        TriggerConfig.self, from: Data(#"{"intervalMs":0,"maxHoldMs":0}"#.utf8))
    #expect(tooSmall.intervalMs == 10)
    #expect(tooSmall.maxHoldMs == 10)

    let tooLarge = try JSONDecoder().decode(
        TriggerConfig.self, from: Data(#"{"intervalMs":999999,"maxHoldMs":999999}"#.utf8))
    #expect(tooLarge.intervalMs == 2000)
    #expect(tooLarge.maxHoldMs == 2000)
}

@Test func clampsValuesConstructedInCodeToo() {
    // The decoder is not the only way in, and `intervalMs` is `private(set)`
    // precisely so that this initialiser is the only other one.
    let config = TriggerConfig(
        kind: .doubleTap, modifier: .rightCommand, intervalMs: -5, maxHoldMs: 100_000)
    #expect(config.intervalMs == 10)
    #expect(config.maxHoldMs == 2000)
}

@Test func aConfigWithoutATriggerBlockKeepsTheCombination() throws {
    let json = Data(#"{"activeProfile":"local"}"#.utf8)
    let config = try JSONDecoder().decode(Config.self, from: json)
    #expect(config.trigger.kind == .combination)
    #expect(config.trigger.modifier == .rightCommand)
}

@Test func triggerConfigRoundTripsThroughJSON() throws {
    let original = TriggerConfig(
        kind: .doubleTap, modifier: .leftOption, intervalMs: 250, maxHoldMs: 400)
    let data = try JSONEncoder().encode(original)
    #expect(try JSONDecoder().decode(TriggerConfig.self, from: data) == original)
}

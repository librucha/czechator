import Foundation
import Testing

@testable import CzechatorCore

@Test func mapsEachModifierToItsKeyCode() {
    #expect(ModifierKey.rightCommand.keyCode == 54)
    #expect(ModifierKey.leftCommand.keyCode == 55)
    #expect(ModifierKey.rightOption.keyCode == 61)
    #expect(ModifierKey.leftOption.keyCode == 58)
}

@Test func mapsKeyCodesBack() {
    for modifier in ModifierKey.allCases {
        #expect(ModifierKey.from(keyCode: modifier.keyCode) == modifier)
    }
    #expect(ModifierKey.from(keyCode: 0) == nil)
}

@Test func distinguishesSides() {
    // The whole point of the feature: a left press must not fire a trigger
    // configured for the right key.
    #expect(ModifierKey.rightCommand != ModifierKey.leftCommand)
    #expect(ModifierKey.rightCommand.keyCode != ModifierKey.leftCommand.keyCode)
}

@Test func hasACzechLabelForEveryCase() {
    for modifier in ModifierKey.allCases {
        #expect(!modifier.label.isEmpty)
    }
    #expect(ModifierKey.rightCommand.label == "pravý ⌘")
}

@Test func modifierKeyRoundTripsThroughJSON() throws {
    for modifier in ModifierKey.allCases {
        let data = try JSONEncoder().encode(modifier)
        #expect(try JSONDecoder().decode(ModifierKey.self, from: data) == modifier)
    }
}

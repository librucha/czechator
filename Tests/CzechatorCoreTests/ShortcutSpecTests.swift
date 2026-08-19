import Foundation
import Testing

@testable import CzechatorCore

@Test func parsesTheDefaultShortcut() throws {
    let spec = try ShortcutSpec.parse("cmd+ctrl+d")
    #expect(spec.modifiers == [.cmd, .ctrl])
    #expect(spec.key == "d")
}

@Test func isCaseAndWhitespaceInsensitive() throws {
    #expect(try ShortcutSpec.parse("  CMD + Ctrl + D ") == (try ShortcutSpec.parse("cmd+ctrl+d")))
}

@Test func acceptsAllModifierNames() throws {
    let spec = try ShortcutSpec.parse("cmd+ctrl+alt+shift+k")
    #expect(spec.modifiers == [.cmd, .ctrl, .alt, .shift])
    #expect(spec.key == "k")
}

@Test func rejectsMalformedInput() {
    #expect(throws: ShortcutParseError.empty) { try ShortcutSpec.parse("   ") }
    #expect(throws: ShortcutParseError.noKey) { try ShortcutSpec.parse("cmd+ctrl") }
    #expect(throws: ShortcutParseError.multipleKeys) { try ShortcutSpec.parse("cmd+d+k") }
    #expect(throws: ShortcutParseError.unknownToken("hyper")) { try ShortcutSpec.parse("hyper+d") }
}

@Test func requiresAtLeastOneModifier() {
    // A bare letter would fire on every keystroke of that letter, everywhere.
    #expect(throws: ShortcutParseError.noModifier) { try ShortcutSpec.parse("d") }
}

@Test func flagsShortcutsThatCollideWithCommonSystemOnes() throws {
    #expect(try ShortcutSpec.parse("cmd+b").isCommonSystemShortcut)
    #expect(try ShortcutSpec.parse("cmd+c").isCommonSystemShortcut)
    #expect(!(try ShortcutSpec.parse("cmd+ctrl+d").isCommonSystemShortcut))
    #expect(!(try ShortcutSpec.parse("cmd+shift+b").isCommonSystemShortcut))
}

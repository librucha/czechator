import CzechatorCore
import Foundation
import Testing

@testable import CzechatorApp

@Test func namesTheLikelyCauseOfAFailedRegistration() {
    let message = AppErrorMessages.describe(HotKeyManager.HotKeyError.registrationFailed(-9878))
    #expect(message.contains("jiná aplikace"))
    // The OSStatus told the user nothing and looked like a crash.
    #expect(!message.contains("-9878"))
    #expect(!message.contains("registrationFailed"))
}

@Test func saysWhichKeyWasNotUnderstood() {
    let message = AppErrorMessages.describe(HotKeyManager.HotKeyError.unsupportedKey("f13"))
    #expect(message.contains("f13"))
    #expect(!message.contains("unsupportedKey"))
}

@Test func reusesTheOneAccessibilityMessage() {
    // Two places explain this; they must not drift into two wordings.
    #expect(
        AppErrorMessages.describe(DoubleTapMonitor.MonitorError.accessibilityDenied)
            == ErrorMessages.accessibilityRequired)
}

@Test func handsAnythingElseToTheCore() {
    let error = ConfigError.unknownActiveProfile("nesmysl")
    #expect(AppErrorMessages.describe(error) == ErrorMessages.describe(error))
}

@Test func neverLeaksASwiftTypeNameForAnyAppError() {
    // The whole point: no user-facing string may read like a debugger dump.
    let errors: [any Error] = [
        HotKeyManager.HotKeyError.registrationFailed(-1),
        HotKeyManager.HotKeyError.unsupportedKey("x"),
        DoubleTapMonitor.MonitorError.accessibilityDenied,
    ]
    for error in errors {
        let message = AppErrorMessages.describe(error)
        #expect(!message.contains("Error("))
        #expect(!message.contains("CzechatorApp."))
        #expect(message.first?.isUppercase == true)
    }
}

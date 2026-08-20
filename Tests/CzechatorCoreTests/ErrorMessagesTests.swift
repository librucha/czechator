import Foundation
import Testing

@testable import CzechatorCore

@Test func describesEveryPipelineError() {
    #expect(ErrorMessages.describe(PipelineError.noText) == "Ve schránce není text.")
    #expect(
        ErrorMessages.describe(PipelineError.inputTooLarge(bytes: 60_000, limit: 51_200))
            == "Vstup má 60000 B, limit je 51200 B.")
    #expect(
        ErrorMessages.describe(PipelineError.verificationFailed(failedSegments: 3))
            == "Výsledek neprošel kontrolou (3 vadné segmenty). Schránka zůstala beze změny.")
}

@Test func describesProviderFailuresWithoutLeakingPayload() {
    #expect(
        ErrorMessages.describe(PipelineError.providerFailed(.unreachable))
            == "Model neodpověděl: nepodařilo se k němu připojit.")
    #expect(
        ErrorMessages.describe(PipelineError.providerFailed(.unauthorized))
            == "Model neodpověděl: odmítl přihlašovací klíč.")
    #expect(
        ErrorMessages.describe(PipelineError.providerFailed(.http(status: 503)))
            == "Model neodpověděl: vrátil chybu HTTP 503.")
}

@Test func describesClipboardErrors() {
    #expect(
        ErrorMessages.describe(ClipboardError.unsupportedFormat("RTF"))
            == "Formát RTF zatím neumím.")
    #expect(
        ErrorMessages.describe(ClipboardError.noTextRepresentation(availableTypes: ["public.png"]))
            == "Ve schránce není text.")
}

@Test func describesSecretAndConfigErrors() {
    #expect(
        ErrorMessages.describe(SecretError.notFound("czechator-openai"))
            == "Nepodařilo se načíst klíč: czechator-openai.")
    #expect(
        ErrorMessages.describe(ConfigError.unknownActiveProfile("chybi"))
            == "Konfigurace odkazuje na profil chybi, který v ní není.")
}

@Test func declinesSegmentCountCorrectly() {
    let one = ErrorMessages.describe(PipelineError.verificationFailed(failedSegments: 1))
    let five = ErrorMessages.describe(PipelineError.verificationFailed(failedSegments: 5))
    #expect(one.contains("1 vadný segment)"))
    #expect(five.contains("5 vadných segmentů)"))
}

@Test func fallsBackToTheUnderlyingDescription() {
    struct Weird: Error {}
    #expect(!ErrorMessages.describe(Weird()).isEmpty)
}

@Test func explainsWhyAccessibilityIsNeeded() {
    let message = ErrorMessages.accessibilityRequired
    // The user has to understand what to grant and why, from the menu alone.
    #expect(message.contains("Dvojí stisk"))
    #expect(message.contains("Zpřístupnění"))
    #expect(message.contains("Accessibility"))
}

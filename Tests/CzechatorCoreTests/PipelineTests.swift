import Foundation
import Testing

@testable import CzechatorCore

/// Applies a closure to every item of the numbered list it receives.
final class FakeProvider: LLMProvider, @unchecked Sendable {
    let transform: @Sendable ([String]) -> [String]
    private(set) var callCount = 0

    init(transform: @escaping @Sendable ([String]) -> [String]) { self.transform = transform }

    func complete(_ prompt: Prompt) async throws -> String {
        callCount += 1
        let count = prompt.user.split(separator: "\n").count
        let items = try NumberedList.decode(prompt.user, expectedCount: count)
        return NumberedList.encode(transform(items))
    }
}

private let restore: @Sendable ([String]) -> [String] = { items in
    items.map {
        $0.replacingOccurrences(of: "Prilis", with: "Příliš")
            .replacingOccurrences(of: "zlutoucky", with: "žluťoučký")
            .replacingOccurrences(of: "kun", with: "kůň")
            .replacingOccurrences(of: "svete", with: "světe")
    }
}

private func pipeline(_ provider: any LLMProvider, limits: Limits = .builtIn) throws -> Pipeline {
    Pipeline(
        registry: try FormatRegistry(rules: .builtIn),
        provider: provider,
        limits: limits,
        promptOverride: nil)
}

@Test func correctsPlainText() async throws {
    let result = try await pipeline(FakeProvider(transform: restore))
        .run(ClipboardInput(text: "Prilis zlutoucky kun"))
    #expect(result.correctedText == "Příliš žluťoučký kůň")
    #expect(result.formatID == "plain")
    #expect(result.changedSegmentCount == 1)
}

@Test func correctsJSONValuesWithoutTouchingStructure() async throws {
    let text = #"{"id": "x", "popis": "Prilis zlutoucky kun"}"#
    let result = try await pipeline(FakeProvider(transform: restore)).run(
        ClipboardInput(text: text))
    #expect(result.correctedText == #"{"id": "x", "popis": "Příliš žluťoučký kůň"}"#)
    #expect(result.formatID == "json")
}

@Test func refusesOutputWhenTheModelAddsText() async {
    let chatty = FakeProvider { $0.map { $0 + " (hotovo)" } }
    await #expect(throws: PipelineError.verificationFailed(failedSegments: 1)) {
        try await pipeline(chatty).run(ClipboardInput(text: "Prilis zlutoucky kun"))
    }
}

@Test func retriesOnlyTheOffendingSegmentsOnce() async throws {
    // Fails the second item on the first attempt, succeeds on the retry.
    final class FlakyProvider: LLMProvider, @unchecked Sendable {
        var attempts = 0
        func complete(_ prompt: Prompt) async throws -> String {
            attempts += 1
            let count = prompt.user.split(separator: "\n").count
            let items = try NumberedList.decode(prompt.user, expectedCount: count)
            if attempts == 1 {
                return NumberedList.encode(
                    items.enumerated().map { $0.offset == 1 ? "spatne" : $0.element })
            }
            return NumberedList.encode(items)
        }
    }
    let provider = FlakyProvider()
    let result = try await pipeline(provider).run(ClipboardInput(text: "prvni radek\ndruhy radek"))
    #expect(result.correctedText == "prvni radek\ndruhy radek")
    #expect(provider.attempts == 2)
}

@Test func reportsProviderFailureWhenTheListNeverParses() async {
    final class Garbage: LLMProvider, @unchecked Sendable {
        func complete(_ prompt: Prompt) async throws -> String { "nesmysl bez cislovani" }
    }
    await #expect(throws: (any Error).self) {
        try await pipeline(Garbage()).run(ClipboardInput(text: "Prilis zlutoucky kun"))
    }
}

@Test func reusesCorrectionsBetweenHTMLAndPlainRepresentations() async throws {
    let provider = FakeProvider(transform: restore)
    let input = ClipboardInput(
        text: "<p>Prilis zlutoucky kun</p>",
        uti: "public.html",
        plainText: "Prilis zlutoucky kun")
    let result = try await pipeline(provider).run(input)

    #expect(result.correctedText == "<p>Příliš žluťoučký kůň</p>")
    #expect(result.correctedPlainText == "Příliš žluťoučký kůň")
    // The plain pass is served entirely from the cache.
    #expect(provider.callCount == 1)
}

@Test func rejectsEmptyInput() async {
    await #expect(throws: PipelineError.noText) {
        try await pipeline(FakeProvider(transform: restore)).run(ClipboardInput(text: "   \n  "))
    }
}

@Test func rejectsOversizedInput() async {
    let big = String(repeating: "a bcd ", count: 100)
    await #expect(throws: PipelineError.inputTooLarge(bytes: big.utf8.count, limit: 100)) {
        try await pipeline(
            FakeProvider(transform: restore),
            limits: Limits(maxInputBytes: 100, maxBatchChars: 1500)
        ).run(ClipboardInput(text: big))
    }
}

@Test func returnsInputUnchangedWhenThereIsNothingToSegment() async throws {
    let provider = FakeProvider(transform: restore)
    let result = try await pipeline(provider).run(ClipboardInput(text: "12345 -- 67"))
    #expect(result.correctedText == "12345 -- 67")
    #expect(result.segmentCount == 0)
    #expect(provider.callCount == 0)
}

@Test func unchangedSegmentsGoBackAsOriginalBytes() async throws {
    // The model returns everything untouched; the JSON escaping style must not
    // be re-derived, so the document has to come back byte-identical.
    let text = #"{"a": "lomitko \/ a unicode á"}"#
    let result = try await pipeline(FakeProvider { $0 }).run(ClipboardInput(text: text))
    #expect(result.correctedText == text)
    #expect(result.changedSegmentCount == 0)
}

@Test func splitsWorkAcrossBatchesAndMapsResultsBack() async throws {
    // Exercises the indices -> subset -> batch indirection with more than one
    // batch, which the happy path never reaches.
    let lines = (1...6).map { "radek cislo \($0) Prilis" }
    let text = lines.joined(separator: "\n")
    let provider = FakeProvider(transform: restore)
    let result = try await pipeline(
        provider, limits: Limits(maxInputBytes: 51_200, maxBatchChars: 25)
    ).run(ClipboardInput(text: text))

    #expect(
        result.correctedText
            == lines.map { $0.replacingOccurrences(of: "Prilis", with: "Příliš") }.joined(
                separator: "\n"))
    #expect(result.segmentCount == 6)
    #expect(provider.callCount > 1)
}

@Test func retryPromptContainsOnlyTheOffendingSegment() async throws {
    final class RecordingProvider: LLMProvider, @unchecked Sendable {
        var prompts: [String] = []
        func complete(_ prompt: Prompt) async throws -> String {
            prompts.append(prompt.user)
            let count = prompt.user.split(separator: "\n").count
            let items = try NumberedList.decode(prompt.user, expectedCount: count)
            if prompts.count == 1 {
                return NumberedList.encode(
                    items.enumerated().map { $0.offset == 1 ? "uplne jinak" : $0.element })
            }
            return NumberedList.encode(items)
        }
    }
    let provider = RecordingProvider()
    _ = try await pipeline(provider).run(ClipboardInput(text: "prvni radek\ndruhy radek"))

    #expect(provider.prompts.count == 2)
    #expect(provider.prompts[1] == "1. druhy radek")
}

@Test func providerFailuresAreReportedAsCategoriesWithoutPayload() async {
    final class Unauthorized: LLMProvider, @unchecked Sendable {
        func complete(_ prompt: Prompt) async throws -> String {
            throw HTTPError.status(code: 401, body: #"{"error":"invalid key sk-tajne"}"#)
        }
    }
    await #expect(throws: PipelineError.providerFailed(.unauthorized)) {
        try await pipeline(Unauthorized()).run(ClipboardInput(text: "Prilis zlutoucky kun"))
    }
    // The message must not carry the body through.
    let message = ErrorMessages.describe(PipelineError.providerFailed(.unauthorized))
    #expect(!message.contains("sk-tajne"))
}

@Test func identicalPlainFlavourIsNotChargedTwiceAgainstTheLimit() async throws {
    let text = "Prilis zlutoucky kun"
    let result = try await pipeline(
        FakeProvider(transform: restore),
        limits: Limits(maxInputBytes: text.utf8.count, maxBatchChars: 1500)
    ).run(ClipboardInput(text: text, uti: nil, plainText: text))
    #expect(result.correctedText == "Příliš žluťoučký kůň")
}

@Test func toleratesTrailingWhitespaceTheModelAddsToEveryLine() async throws {
    // qwen3 appends two spaces to each line (Markdown hard break); without
    // realignment the whole document would fail verification.
    let sloppy = FakeProvider {
        $0.map { $0.replacingOccurrences(of: "Prilis", with: "Příliš") + "  " }
    }
    let result = try await pipeline(sloppy).run(ClipboardInput(text: "Prilis zlutoucky kun"))
    #expect(result.correctedText == "Příliš zlutoucky kun")
}

@Test func edgeWhitespaceComesFromTheOriginalNotTheModel() {
    #expect(Pipeline.alignEdgeWhitespace("opraveno  ", like: "puvodni") == "opraveno")
    #expect(Pipeline.alignEdgeWhitespace("opraveno", like: "puvodni\n") == "opraveno\n")
    #expect(Pipeline.alignEdgeWhitespace("  opraveno  ", like: "\tpuvodni") == "\topraveno")
}

@Test func keepsEdgeWhitespaceThatUnescapingProduced() async throws {
    // The raw range is trimmed at source level, where "\n" is two characters,
    // so the segment text ends with a real newline only after unescaping.
    // Realignment must restore that, not the model's idea of it.
    let sloppy = FakeProvider {
        $0.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) + "   " }
    }
    let json = #"{"a": "Prilis zlutoucky kun\n"}"#
    let result = try await pipeline(sloppy).run(ClipboardInput(text: json))
    #expect(result.correctedText == json)

    let html = "<p>&nbsp;Prilis zlutoucky kun</p>"
    let htmlResult = try await pipeline(sloppy).run(ClipboardInput(text: html))
    #expect(htmlResult.correctedText == html)
}

@Test func refusesStructureThatDoesNotParse() async {
    // Silently correcting these renamed JSON keys — verified corruption.
    let jsonc = "{\n  // poznamka\n  \"nazev\": \"Prilis zlutoucky kun\"\n}"
    await #expect(throws: PipelineError.unparsableStructure) {
        try await pipeline(FakeProvider(transform: restore)).run(ClipboardInput(text: jsonc))
    }
}

@Test func forcesTheOriginalLetterCaseBackOntoTheCorrection() {
    // The model capitalizes sentence starts whatever the prompt says.
    #expect(
        Pipeline.alignCase("Proč se to muselo dodělat", like: "proc se to muselo dodelat")
            == "proč se to muselo dodělat")
    // And the mirror case: a genuinely capitalized start must stay capitalized.
    #expect(Pipeline.alignCase("příliš žluťoučký", like: "Prilis zlutoucky") == "Příliš žluťoučký")
    #expect(Pipeline.alignCase("praha a brno", like: "Praha a Brno") == "Praha a Brno")
    // A different word is left alone; the verifier deals with it.
    #expect(Pipeline.alignCase("Uplne jine", like: "proc se to") == "Uplne jine")
    // A length change disables it, same as the other normalizations.
    #expect(Pipeline.alignCase("Proč navic", like: "proc") == "Proč navic")
}

@Test func acceptsACorrectionTheModelCapitalized() async throws {
    let shouty = FakeProvider { $0.map { $0.prefix(1).uppercased() + $0.dropFirst() } }
    let result = try await pipeline(shouty).run(ClipboardInput(text: "proc se to stalo"))
    #expect(result.correctedText == "proc se to stalo")
}

@Test func letterCasePolicyDecidesWhatTheModelMayCapitalize() {
    let original = "proc se to stalo v praze"
    let shouty = "Proč se to stalo v Praze"

    // preserve: everything goes back to the original case.
    #expect(
        Pipeline.alignCase(shouty, like: original, policy: .preserve)
            == "proč se to stalo v praze")
    // segmentStart: only the first letter keeps the model's choice.
    #expect(
        Pipeline.alignCase(shouty, like: original, policy: .segmentStart)
            == "Proč se to stalo v praze")
    // model: untouched.
    #expect(Pipeline.alignCase(shouty, like: original, policy: .model) == shouty)
}

@Test func verificationFollowsTheSamePolicy() {
    let segments = [
        Segment(range: "x".startIndex..<"x".endIndex, raw: "x", text: "proc", kind: .plain)
    ]
    func failing(_ policy: LetterCasePolicy) -> [Int] {
        DiacriticVerifier.failingIndices(
            segments: segments, corrections: ["Proč"], policy: policy)
    }
    #expect(failing(.preserve) == [0])
    #expect(failing(.segmentStart).isEmpty)
    #expect(failing(.model).isEmpty)
    // A word swap is refused under every policy.
    #expect(
        !DiacriticVerifier.failingIndices(
            segments: segments, corrections: ["Jinak"], policy: .model
        ).isEmpty)
}

@Test func segmentStartPolicyAcceptsACapitalizedSentence() async throws {
    let shouty = FakeProvider { $0.map { $0.prefix(1).uppercased() + $0.dropFirst() } }
    let pipeline = Pipeline(
        registry: try FormatRegistry(rules: .builtIn), provider: shouty,
        limits: .builtIn, promptOverride: nil, letterCase: .segmentStart)
    let result = try await pipeline.run(ClipboardInput(text: "proc se to stalo"))
    #expect(result.correctedText == "Proc se to stalo")
}

private func tolerantPipeline(
    _ provider: any LLMProvider,
    corrections: CorrectionMode = .strict,
    editBudget: EditBudget = .builtIn,
    verification: Bool = true
) throws -> Pipeline {
    Pipeline(
        registry: try FormatRegistry(rules: .builtIn),
        provider: provider,
        limits: .builtIn,
        promptOverride: nil,
        letterCase: .preserve,
        corrections: corrections,
        editBudget: editBudget,
        verification: verification)
}

private let fixTypo: @Sendable ([String]) -> [String] = { items in
    items.map {
        $0.replacingOccurrences(of: "Kndeliky", with: "Knedlíky")
            .replacingOccurrences(of: "dobre", with: "dobré")
    }
}

@Test func pipelineTolerantModeAcceptsATypoFix() async throws {
    // "kndeliky" -> "knedliky" is one transposition on an eight-letter word,
    // which is exactly the default allowance.
    let result = try await tolerantPipeline(
        FakeProvider(transform: fixTypo), corrections: .minorFixes
    ).run(ClipboardInput(text: "Kndeliky jsou dobre."))
    #expect(result.correctedText == "Knedlíky jsou dobré.")
}

@Test func pipelineStrictModeRefusesTheSameTypoFix() async throws {
    // The provider is deterministic, so the retry returns the same answer and
    // the document is refused rather than written.
    await #expect(throws: PipelineError.self) {
        _ = try await tolerantPipeline(
            FakeProvider(transform: fixTypo), corrections: .strict
        ).run(ClipboardInput(text: "Kndeliky jsou dobre."))
    }
}

private let rewriteEverything: @Sendable ([String]) -> [String] = { _ in
    ["Úplně jiná věta."]
}

@Test func pipelineWithVerificationOffWritesWhateverCameBack() async throws {
    // The switch does what it says: no segment comparison, no retry. This is
    // the test that documents how much is given up.
    let result = try await tolerantPipeline(
        FakeProvider(transform: rewriteEverything), corrections: .proofread,
        verification: false
    ).run(ClipboardInput(text: "Kndeliky jsou dobre."))
    #expect(result.correctedText == "Úplně jiná věta.")
}

private let fixPreposition: @Sendable ([String]) -> [String] = { items in
    items.map { $0.replacingOccurrences(of: "v ctvrtek", with: "ve čtvrtek") }
}

@Test func pipelineKeepsANonBreakingSpaceThroughATolerantFix() async throws {
    // The regression that would otherwise be silent: the model lengthens the
    // preposition, the masked NBSP is no longer at index 1, and without the
    // alignment it would simply vanish.
    let result = try await tolerantPipeline(
        FakeProvider(transform: fixPreposition), corrections: .minorFixes,
        editBudget: EditBudget(percent: 40, minimum: 2)
    ).run(ClipboardInput(text: "v\u{00A0}ctvrtek"))
    #expect(result.correctedText == "ve\u{00A0}čtvrtek")
}

private let capitalize: @Sendable ([String]) -> [String] = { items in
    items.map { $0.replacingOccurrences(of: "posilam", with: "Posílám") }
}

@Test func pipelineTolerantModeLetsTheModelFixCapitalization() async throws {
    // alignCase forces the original case back in strict mode. A tolerant mode
    // asked the model to fix capitalization, so undoing it would defeat the
    // request — this is what proves alignCase is skipped.
    let result = try await tolerantPipeline(
        FakeProvider(transform: capitalize), corrections: .minorFixes
    ).run(ClipboardInput(text: "posilam podklady"))
    #expect(result.correctedText == "Posílám podklady")
}

private let dropTheSpace: @Sendable ([String]) -> [String] = { items in
    items.map { $0.replacingOccurrences(of: "v ctvrtek", with: "vctvrtek") }
}

@Test func pipelineRefusesACorrectionThatSwallowedAMaskedSpace() async throws {
    // Deleting the space costs one edit on a one-letter word, so the budget
    // accepts it. The only thing standing between the user and a lost
    // non-breaking space is the restoration failure being retried and, since
    // the provider is deterministic, refused.
    await #expect(throws: PipelineError.self) {
        _ = try await tolerantPipeline(
            FakeProvider(transform: dropTheSpace), corrections: .minorFixes
        ).run(ClipboardInput(text: "v\u{00A0}ctvrtek"))
    }
}

private let dropAnAccent: @Sendable ([String]) -> [String] = { items in
    items.map { $0.replacingOccurrences(of: "dobré", with: "dobr") }
}

@Test func pipelineRefusesATolerantFixThatDeletedAnEntity() async throws {
    // The é of "dobré" is written as an entity, so index 4 is protected. The
    // model deletes it: one edit on a five-letter word, which the budget waves
    // through. The only thing left to catch it is the protected index no longer
    // surviving the alignment — without that check the entity would be replayed
    // at index 4 of "dobr rano" and land in the middle of a different word.
    await #expect(throws: PipelineError.self) {
        _ = try await tolerantPipeline(
            FakeProvider(transform: dropAnAccent), corrections: .minorFixes
        ).run(ClipboardInput(text: "<p>dobr&eacute; rano</p>", uti: "public.html"))
    }
}

@Test func pipelineWithVerificationOffStillRefusesToMoveAnEntity() async throws {
    // Switching verification off gives up checking the model, not the check on
    // our own reassembly. A strict run with no verification still has to notice
    // that the entity's index did not survive, or it writes a document neither
    // the model nor the original ever contained.
    await #expect(throws: PipelineError.self) {
        _ = try await tolerantPipeline(
            FakeProvider(transform: dropAnAccent), corrections: .strict,
            verification: false
        ).run(ClipboardInput(text: "<p>dobr&eacute; rano</p>", uti: "public.html"))
    }
}

@Test func pipelineRetriesTheSegmentWhoseEntityMovedAndAcceptsTheSecondTry() async throws {
    // The protected-index check does not only refuse: it routes the segment
    // through the retry, so a model that gets it right the second time gets the
    // document written instead of turned away. The entity has to come back in
    // its original spelling, at its original place.
    final class FlakyEntityProvider: LLMProvider, @unchecked Sendable {
        var attempts = 0
        func complete(_ prompt: Prompt) async throws -> String {
            attempts += 1
            let items = try NumberedList.decode(
                prompt.user, expectedCount: prompt.user.split(separator: "\n").count)
            return NumberedList.encode(
                items.map {
                    attempts == 1
                        ? $0.replacingOccurrences(of: "dobré", with: "dobr")
                        : $0.replacingOccurrences(of: "rano", with: "ráno")
                })
        }
    }
    let provider = FlakyEntityProvider()
    let result = try await tolerantPipeline(provider, corrections: .minorFixes)
        .run(ClipboardInput(text: "<p>dobr&eacute; rano</p>", uti: "public.html"))

    #expect(result.correctedText == "<p>dobr&eacute; ráno</p>")
    #expect(provider.attempts == 2)
}

@Test func pipelineWithVerificationOffRefusesASegmentTooLongToAlign() async throws {
    // Past DiacriticVerifier.toleranceLimit there is no index map, and with
    // verification off nothing has checked the length either. Escaping the
    // entity at its recorded index would move it; the run has to stop instead.
    let filler = String(repeating: "dobre rano ", count: 220)
    #expect(filler.count > DiacriticVerifier.toleranceLimit)
    let long = FakeProvider { $0.map { $0 + " navic" } }

    await #expect(throws: PipelineError.self) {
        _ = try await tolerantPipeline(long, corrections: .strict, verification: false)
            .run(ClipboardInput(text: "<p>a &amp; \(filler)</p>", uti: "public.html"))
    }
}

@Test func pipelineWithVerificationOffStillHandlesALongSegmentWithNothingToProtect() async throws {
    // The mirror: no recorded spelling means escaping cannot relocate anything,
    // so a paragraph past the limit must still go through. Refusing it would
    // make the mode useless on exactly the long-form text it exists for.
    let filler = String(repeating: "dobre rano ", count: 220)
    let long = FakeProvider { $0.map { $0 + " navic" } }
    let result = try await tolerantPipeline(long, corrections: .strict, verification: false)
        .run(ClipboardInput(text: filler))
    #expect(result.correctedText.contains("navic"))
    #expect(result.changedSegmentCount == 1)
}

// MARK: - Personal dictionary

private func dictionaryPipeline(
    _ provider: any LLMProvider, corrections: CorrectionMode = .strict, verification: Bool = true
) throws -> Pipeline {
    Pipeline(
        registry: try FormatRegistry(rules: .builtIn),
        provider: provider,
        limits: .builtIn,
        promptOverride: nil,
        corrections: corrections,
        verification: verification,
        dictionary: PersonalDictionary(rules: [DictionaryRule(from: "docs", to: "docs")]))
}

/// The model the dictionary exists for: it puts accents into an English term.
private let accentsDocs: @Sendable ([String]) -> [String] = { items in
    items.map { $0.replacingOccurrences(of: "docs", with: "dočš") }
}

@Test func dictionaryOverridesTheModelBeforeVerification() async throws {
    let result = try await dictionaryPipeline(FakeProvider(transform: accentsDocs))
        .run(ClipboardInput(text: "otevri google docs"))
    #expect(result.correctedText == "otevri google docs")
}

@Test func dictionaryAppliesWithVerificationOff() async throws {
    let result = try await dictionaryPipeline(FakeProvider(transform: accentsDocs), verification: false)
        .run(ClipboardInput(text: "otevri google docs"))
    #expect(result.correctedText == "otevri google docs")
}

@Test func dictionaryAppliesInATolerantMode() async throws {
    let fixesTypoAndAccents = FakeProvider { $0.map { _ in "google dočš" } }
    let result = try await dictionaryPipeline(fixesTypoAndAccents, corrections: .minorFixes)
        .run(ClipboardInput(text: "gogle docs"))
    #expect(result.correctedText == "google docs")
}

@Test func dictionaryDoesNotChangeWhatVerificationRefuses() async {
    let chatty = FakeProvider { $0.map { $0 + " (hotovo)" } }
    await #expect(throws: PipelineError.verificationFailed(failedSegments: 1)) {
        try await dictionaryPipeline(chatty).run(ClipboardInput(text: "otevri google docs"))
    }
}

@Test func dictionaryResultIsWhatTheCacheServes() async throws {
    let provider = FakeProvider(transform: accentsDocs)
    let input = ClipboardInput(text: "<p>google docs</p>", uti: "public.html", plainText: "google docs")
    let result = try await dictionaryPipeline(provider).run(input)
    #expect(result.correctedText == "<p>google docs</p>")
    #expect(result.correctedPlainText == "google docs")
    #expect(provider.callCount == 1)
}

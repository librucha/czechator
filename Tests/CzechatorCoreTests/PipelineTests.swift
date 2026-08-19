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
    let result = try await pipeline(FakeProvider(transform: restore)).run(ClipboardInput(text: text))
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
                return NumberedList.encode(items.enumerated().map { $0.offset == 1 ? "spatne" : $0.element })
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

    #expect(result.correctedText == lines.map { $0.replacingOccurrences(of: "Prilis", with: "Příliš") }.joined(separator: "\n"))
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

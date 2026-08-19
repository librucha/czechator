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

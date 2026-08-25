import Testing

@testable import CzechatorCore

private func set(_ samples: [(String, String, String)]) -> QualityFixtureSet {
    QualityFixtureSet(
        name: "t",
        samples: samples.map { QualitySample(name: $0.0, input: $0.1, want: $0.2) })
}

private func pipeline(_ provider: any LLMProvider) throws -> Pipeline {
    Pipeline(
        registry: try FormatRegistry(rules: .builtIn), provider: provider,
        limits: .builtIn, promptOverride: nil)
}

@Test func qualityRunnerCountsAnExactMatch() async throws {
    let provider = FakeProvider(transform: {
        $0.map { $0.replacingOccurrences(of: "kun", with: "kůň") }
    })
    let outcome = try await QualityRunner.run(
        set: set([("a", "kun", "kůň")]),
        pipeline: pipeline(provider), mode: .strict, policy: .preserve)
    #expect(outcome.exact == 1)
    #expect(outcome.accepted == 1)
    #expect(outcome.refused == 0)
    #expect(outcome.misses.isEmpty)
}

@Test func qualityRunnerCountsAnAcceptedButWrongAnswer() async throws {
    // Accepted by the tool, not equal to the reference: the model left an
    // accent out. These two numbers are different on purpose.
    let provider = FakeProvider(transform: { $0 })
    let outcome = try await QualityRunner.run(
        set: set([("a", "kun", "kůň")]),
        pipeline: pipeline(provider), mode: .strict, policy: .preserve)
    #expect(outcome.exact == 0)
    #expect(outcome.accepted == 1)
    #expect(outcome.refused == 0)
    #expect(outcome.misses.first?.refused == false)
}

@Test func qualityRunnerCountsARefusal() async throws {
    let provider = FakeProvider(transform: { _ in ["Úplně jiná věta."] })
    let outcome = try await QualityRunner.run(
        set: set([("a", "kun", "kůň")]),
        pipeline: pipeline(provider), mode: .strict, policy: .preserve)
    #expect(outcome.refused == 1)
    #expect(outcome.accepted == 0)
    #expect(outcome.misses.first?.refused == true)
}

@Test func qualityRunnerStopsOnAProviderFailure() async throws {
    // An unreachable model means the measurement is invalid, not that the model
    // scored badly. The Python harness this replaces counted it as a failure
    // and produced a table of zeroes that read like a verdict.
    let provider = Unreachable()
    await #expect(throws: QualityError.self) {
        _ = try await QualityRunner.run(
            set: set([("a", "kun", "kůň")]),
            pipeline: pipeline(provider), mode: .strict, policy: .preserve)
    }
}

private final class Unreachable: LLMProvider, @unchecked Sendable {
    func complete(_ prompt: Prompt) async throws -> String {
        // `transport` carries a String — see HTTPClient.swift:9.
        throw HTTPError.transport("nedostupné")
    }
}

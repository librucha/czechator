import Foundation
import Testing

@testable import CzechatorCore

private func openAI(_ client: FakeHTTPClient, apiKey: String? = "tajny-klic")
    -> OpenAICompatProvider
{
    OpenAICompatProvider(
        endpoint: URL(string: "https://api.openai.com/v1")!,
        model: "gpt-4o-mini",
        temperature: 0,
        timeout: 30,
        apiKey: apiKey,
        client: client)
}

@Test func extractsFirstChoiceContent() async throws {
    let client = FakeHTTPClient(
        response: Data(#"{"choices":[{"message":{"content":"1. Příliš"}}]}"#.utf8))
    #expect(try await openAI(client).complete(Prompt(system: "s", user: "u")) == "1. Příliš")
}

@Test func sendsAuthorizationHeaderAndCorrectPath() async throws {
    let client = FakeHTTPClient(response: Data(#"{"choices":[{"message":{"content":"x"}}]}"#.utf8))
    _ = try await openAI(client).complete(Prompt(system: "s", user: "u"))

    #expect(client.lastURL?.absoluteString == "https://api.openai.com/v1/chat/completions")
    #expect(client.lastHeaders["Authorization"] == "Bearer tajny-klic")
}

@Test func omitsAuthorizationWhenNoKeyIsConfigured() async throws {
    let client = FakeHTTPClient(response: Data(#"{"choices":[{"message":{"content":"x"}}]}"#.utf8))
    _ = try await openAI(client, apiKey: nil).complete(Prompt(system: "s", user: "u"))
    #expect(client.lastHeaders["Authorization"] == nil)
}

@Test func reportsResponseWithoutChoices() async {
    let client = FakeHTTPClient(response: Data(#"{"choices":[]}"#.utf8))
    await #expect(throws: (any Error).self) {
        try await openAI(client).complete(Prompt(system: "s", user: "u"))
    }
}

@Test func environmentResolverReadsLiteralsAndVariables() throws {
    let resolver = EnvironmentSecretResolver()
    #expect(try resolver.resolve(.literal("primo")) == "primo")
    #expect(throws: SecretError.notFound("CZECHATOR_TEST_NEEXISTUJE")) {
        try resolver.resolve(.environment(name: "CZECHATOR_TEST_NEEXISTUJE"))
    }
    #expect(throws: SecretError.unsupported("keychain")) {
        try resolver.resolve(.keychain(account: "x"))
    }
}

@Test func staticResolverServesTestValues() throws {
    let resolver = StaticSecretResolver(["ucet": "hodnota"])
    #expect(try resolver.resolve(.keychain(account: "ucet")) == "hodnota")
    #expect(throws: SecretError.notFound("jiny")) {
        try resolver.resolve(.environment(name: "jiny"))
    }
}

@Test func secretRefRoundTripsThroughJSON() throws {
    let refs: [SecretRef] = [
        .keychain(account: "czechator-openai"),
        .environment(name: "OPENAI_API_KEY"),
        .literal("abc"),
    ]
    for ref in refs {
        let data = try JSONEncoder().encode(ref)
        #expect(try JSONDecoder().decode(SecretRef.self, from: data) == ref)
    }
}

@Test func secretRefRejectsUnknownSource() {
    let json = Data(#"{"source":"vymysl","name":"x"}"#.utf8)
    #expect(throws: (any Error).self) { try JSONDecoder().decode(SecretRef.self, from: json) }
}

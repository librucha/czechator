import Foundation
import Testing

@testable import CzechatorCore

/// Records the last request and replays a canned response.
final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    var response: Data
    var error: (any Error)?
    private(set) var lastURL: URL?
    private(set) var lastBody: Data?
    private(set) var lastHeaders: [String: String] = [:]

    init(response: Data) { self.response = response }

    func post(url: URL, headers: [String: String], body: Data, timeout: TimeInterval) async throws
        -> Data
    {
        lastURL = url
        lastBody = body
        lastHeaders = headers
        if let error { throw error }
        return response
    }
}

private func ollama(_ client: FakeHTTPClient) -> OllamaProvider {
    OllamaProvider(
        endpoint: URL(string: "http://localhost:11434")!,
        model: "qwen3:4b-instruct",
        temperature: 0,
        timeout: 30,
        client: client)
}

@Test func extractsMessageContent() async throws {
    let client = FakeHTTPClient(
        response: Data(#"{"message":{"role":"assistant","content":"1. Příliš"}}"#.utf8))
    let result = try await ollama(client).complete(Prompt(system: "s", user: "u"))
    #expect(result == "1. Příliš")
}

@Test func postsToChatEndpointWithStreamingDisabled() async throws {
    let client = FakeHTTPClient(response: Data(#"{"message":{"content":"x"}}"#.utf8))
    _ = try await ollama(client).complete(Prompt(system: "s", user: "u"))

    #expect(client.lastURL?.absoluteString == "http://localhost:11434/api/chat")
    let body = try JSONSerialization.jsonObject(with: client.lastBody!) as! [String: Any]
    #expect(body["model"] as? String == "qwen3:4b-instruct")
    #expect(body["stream"] as? Bool == false)
    let messages = body["messages"] as! [[String: String]]
    #expect(messages.map { $0["role"]! } == ["system", "user"])
    #expect(messages[0]["content"] == "s")
    #expect(messages[1]["content"] == "u")
    let options = body["options"] as! [String: Any]
    #expect(options["temperature"] as? Double == 0)
}

@Test func reportsMalformedResponses() async {
    let client = FakeHTTPClient(response: Data(#"{"neco":"jineho"}"#.utf8))
    await #expect(throws: (any Error).self) {
        try await ollama(client).complete(Prompt(system: "s", user: "u"))
    }
}

@Test func reportsEmptyContent() async {
    let client = FakeHTTPClient(response: Data(#"{"message":{"content":""}}"#.utf8))
    await #expect(throws: ProviderError.empty) {
        try await ollama(client).complete(Prompt(system: "s", user: "u"))
    }
}

@Test func propagatesTransportErrors() async {
    let client = FakeHTTPClient(response: Data())
    client.error = HTTPError.transport("spojeni odmitnuto")
    await #expect(throws: HTTPError.transport("spojeni odmitnuto")) {
        try await ollama(client).complete(Prompt(system: "s", user: "u"))
    }
}

@Test func appendsPathWithoutLosingABaseSubpath() async throws {
    let client = FakeHTTPClient(response: Data(#"{"message":{"content":"x"}}"#.utf8))
    let provider = OllamaProvider(
        endpoint: URL(string: "http://host:11434/proxy")!,
        model: "m", temperature: 0, timeout: 5, client: client)
    _ = try await provider.complete(Prompt(system: "s", user: "u"))
    #expect(client.lastURL?.absoluteString == "http://host:11434/proxy/api/chat")
}

import Foundation

public struct OllamaProvider: LLMProvider {

    private let endpoint: URL
    private let model: String
    private let temperature: Double
    private let timeout: TimeInterval
    private let client: any HTTPClient

    public init(
        endpoint: URL, model: String, temperature: Double,
        timeout: TimeInterval, client: any HTTPClient
    ) {
        self.endpoint = endpoint
        self.model = model
        self.temperature = temperature
        self.timeout = timeout
        self.client = client
    }

    private struct Response: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }

    public func complete(_ prompt: Prompt) async throws -> String {
        let payload: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "system", "content": prompt.system],
                ["role": "user", "content": prompt.user],
            ],
            "options": ["temperature": temperature],
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await client.post(
            url: endpoint.appendingPathComponent("api/chat"),
            headers: [:],
            body: body,
            timeout: timeout)

        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw ProviderError.malformedResponse(String(decoding: data.prefix(200), as: UTF8.self))
        }
        guard !decoded.message.content.isEmpty else { throw ProviderError.empty }
        return decoded.message.content
    }
}

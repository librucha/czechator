import Foundation

public struct OpenAICompatProvider: LLMProvider {

    private let endpoint: URL
    private let model: String
    private let temperature: Double
    private let timeout: TimeInterval
    private let apiKey: String?
    private let client: any HTTPClient

    public init(
        endpoint: URL, model: String, temperature: Double,
        timeout: TimeInterval, apiKey: String?, client: any HTTPClient
    ) {
        self.endpoint = endpoint
        self.model = model
        self.temperature = temperature
        self.timeout = timeout
        self.apiKey = apiKey
        self.client = client
    }

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let choices: [Choice]
    }

    public func complete(_ prompt: Prompt) async throws -> String {
        let payload: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "messages": [
                ["role": "system", "content": prompt.system],
                ["role": "user", "content": prompt.user],
            ],
        ]
        var headers: [String: String] = [:]
        if let apiKey { headers["Authorization"] = "Bearer \(apiKey)" }

        let data = try await client.post(
            url: endpoint.appendingPathComponent("chat/completions"),
            headers: headers,
            body: try JSONSerialization.data(withJSONObject: payload),
            timeout: timeout)

        guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
            let first = decoded.choices.first
        else {
            throw ProviderError.malformedResponse(String(decoding: data.prefix(200), as: UTF8.self))
        }
        guard !first.message.content.isEmpty else { throw ProviderError.empty }
        return first.message.content
    }
}

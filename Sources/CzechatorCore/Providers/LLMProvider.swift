public enum ProviderError: Error, Equatable {
    case malformedResponse(String)
    case empty
}

public protocol LLMProvider: Sendable {
    func complete(_ prompt: Prompt) async throws -> String
}

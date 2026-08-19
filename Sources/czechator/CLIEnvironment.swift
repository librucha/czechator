import ArgumentParser
import CzechatorCore
import Foundation

struct CLIEnvironment {
    let config: Config
    let registry: FormatRegistry

    static func load(configPath: String?, profileName: String?) throws -> CLIEnvironment {
        let url = configPath.map { URL(fileURLWithPath: $0) } ?? ConfigStore.defaultURL()
        var config = try ConfigStore(url: url).load()
        if let profileName {
            config.activeProfile = profileName
            try config.validate()
        }
        return CLIEnvironment(
            config: config, registry: try FormatRegistry(rules: config.segmentation))
    }

    /// The CLI resolves secrets from the environment — Keychain lives in the app.
    func makeProvider() throws -> any LLMProvider {
        guard let profile = config.active else {
            throw ConfigError.unknownActiveProfile(config.activeProfile)
        }
        let client = URLSessionHTTPClient()
        let key = try profile.apiKey.map { try EnvironmentSecretResolver().resolve($0) }

        switch profile.kind {
        case .ollama:
            return OllamaProvider(
                endpoint: profile.endpoint,
                model: profile.model,
                temperature: profile.temperature,
                timeout: profile.timeoutSeconds,
                client: client)
        case .openaiCompat:
            return OpenAICompatProvider(
                endpoint: profile.endpoint,
                model: profile.model,
                temperature: profile.temperature,
                timeout: profile.timeoutSeconds,
                apiKey: key,
                client: client)
        }
    }

    static func readInput(path: String) throws -> String {
        if path == "-" {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            return String(decoding: data, as: UTF8.self)
        }
        return try String(contentsOfFile: path, encoding: .utf8)
    }
}

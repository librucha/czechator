import ArgumentParser
import CzechatorCore
import Foundation

#if canImport(CzechatorKeychain)
    import CzechatorKeychain
#endif

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

    /// Resolves the same references the app does, so one configuration works
    /// from both. On macOS that includes the Keychain; elsewhere there is none,
    /// and an environment variable is the way in.
    func makeProvider() throws -> any LLMProvider {
        guard let profile = config.active else {
            throw ConfigError.unknownActiveProfile(config.activeProfile)
        }
        let client = URLSessionHTTPClient()
        let key = try profile.apiKey.map { try Self.secretResolver.resolve($0) }

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

extension CLIEnvironment {
    /// Keychain where there is one, environment where there is not.
    static var secretResolver: any SecretResolver {
        #if canImport(CzechatorKeychain)
            return KeychainSecretResolver()
        #else
            return EnvironmentSecretResolver()
        #endif
    }
}

import Foundation
import Yams

public enum ConfigError: Error, Equatable {
    case serializationFailed
    case unknownActiveProfile(String)
    case invalidEndpoint(profile: String, value: String)
}

public struct ConfigStore: Sendable {

    private let url: URL

    public init(url: URL) { self.url = url }

    public static func defaultURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("czechator")
            .appendingPathComponent("config.yaml")
    }

    /// Materializes the full defaults on first run so every rule is visible and
    /// editable without reading the source.
    public func load() throws -> Config {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            try write(node: try encodeNode(Config.builtIn))
            return .builtIn
        }
        let config = try YAMLDecoder().decode(Config.self, from: text)
        try config.validate()
        return config
    }

    /// Writes the config back while keeping any keys the tool does not know
    /// about — hand-written entries survive the settings window.
    ///
    /// Validates first: an invalid config written to disk would make every later
    /// `load` fail, and `load` only rewrites defaults when the file is *missing*,
    /// not when it is present but broken — the user would be locked out for good.
    public func save(_ config: Config) throws {
        try config.validate()
        let encoded = try encodeNode(config)
        if let existing = try? String(contentsOf: url, encoding: .utf8),
            let base = try Yams.compose(yaml: existing)
        {
            try write(node: Self.merge(into: base, from: encoded))
        } else {
            try write(node: encoded)
        }
    }

    private func encodeNode(_ config: Config) throws -> Node {
        let text = try YAMLEncoder().encode(config)
        guard let node = try Yams.compose(yaml: text) else {
            throw ConfigError.serializationFailed
        }
        return node
    }

    private func write(node: Node) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = try Yams.serialize(node: node)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Recursive mapping merge: known keys are overwritten, unknown ones kept.
    ///
    /// Sequences and scalars are replaced wholesale, so a hand-added key inside
    /// a sequence item (a note on one hotkey) does not survive. YAML comments
    /// do not survive either — Yams drops them on compose.
    static func merge(into base: Node, from new: Node) -> Node {
        guard case .mapping(let baseMapping) = base,
            case .mapping(let newMapping) = new
        else {
            return new
        }
        var result = baseMapping
        for (key, value) in newMapping {
            if let existing = result[key] {
                result[key] = merge(into: existing, from: value)
            } else {
                result[key] = value
            }
        }
        return .mapping(result)
    }
}

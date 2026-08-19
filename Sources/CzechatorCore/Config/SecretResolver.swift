import Foundation

/// A reference to a secret, never the secret itself. Config files hold these;
/// the actual value is fetched lazily, right before building the auth header,
/// so nothing that gets logged or stored in history can contain a key.
public enum SecretRef: Sendable, Equatable, Codable {
    case keychain(account: String)
    case environment(name: String)
    case literal(String)

    private enum CodingKeys: String, CodingKey {
        case source, account, name, value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .source) {
        case "keychain":
            self = .keychain(account: try container.decode(String.self, forKey: .account))
        case "env", "environment":
            self = .environment(name: try container.decode(String.self, forKey: .name))
        case "literal":
            self = .literal(try container.decode(String.self, forKey: .value))
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .source, in: container,
                debugDescription: "neznámý zdroj tajemství: \(other)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .keychain(let account):
            try container.encode("keychain", forKey: .source)
            try container.encode(account, forKey: .account)
        case .environment(let name):
            try container.encode("env", forKey: .source)
            try container.encode(name, forKey: .name)
        case .literal(let value):
            try container.encode("literal", forKey: .source)
            try container.encode(value, forKey: .value)
        }
    }
}

public enum SecretError: Error, Equatable {
    case notFound(String)
    case unsupported(String)
}

/// Implementations live outside the core: Keychain on macOS, environment
/// variables everywhere else. This is what keeps `Security.framework` out of
/// `CzechatorCore`.
public protocol SecretResolver: Sendable {
    func resolve(_ ref: SecretRef) throws -> String
}

public struct EnvironmentSecretResolver: SecretResolver {

    public init() {}

    public func resolve(_ ref: SecretRef) throws -> String {
        switch ref {
        case .literal(let value):
            return value
        case .environment(let name):
            guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
                throw SecretError.notFound(name)
            }
            return value
        case .keychain:
            throw SecretError.unsupported("keychain")
        }
    }
}

public struct StaticSecretResolver: SecretResolver {

    private let values: [String: String]

    public init(_ values: [String: String]) { self.values = values }

    public func resolve(_ ref: SecretRef) throws -> String {
        switch ref {
        case .literal(let value):
            return value
        case .environment(let name):
            guard let value = values[name] else { throw SecretError.notFound(name) }
            return value
        case .keychain(let account):
            guard let value = values[account] else { throw SecretError.notFound(account) }
            return value
        }
    }
}

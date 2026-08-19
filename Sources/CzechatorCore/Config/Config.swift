import Foundation

public enum ProfileKind: String, Sendable, Codable {
    case ollama
    case openaiCompat = "openai-compat"
}

public struct Profile: Sendable, Codable, Equatable {
    public var kind: ProfileKind
    public var endpoint: URL
    public var model: String
    public var temperature: Double
    public var timeoutSeconds: Double
    /// Never the key itself — only a reference resolved lazily. See SecretRef.
    public var apiKey: SecretRef?

    public init(
        kind: ProfileKind, endpoint: URL, model: String,
        temperature: Double, timeoutSeconds: Double, apiKey: SecretRef? = nil
    ) {
        self.kind = kind
        self.endpoint = endpoint
        self.model = model
        self.temperature = temperature
        self.timeoutSeconds = timeoutSeconds
        self.apiKey = apiKey
    }
}

public struct HotkeyBinding: Sendable, Codable, Equatable {
    public var shortcut: String
    public var source: String
    public var sink: String

    public init(shortcut: String, source: String, sink: String) {
        self.shortcut = shortcut
        self.source = source
        self.sink = sink
    }
}

public struct FeatureFlags: Sendable, Codable, Equatable {
    public var preview: Bool
    public var history: Bool
    public var historySize: Int
    /// preserve | segmentStart | model — see LetterCasePolicy.
    public var letterCase: LetterCasePolicy

    public static let builtIn = FeatureFlags(
        preview: false, history: true, historySize: 20, letterCase: .preserve)

    public init(preview: Bool, history: Bool, historySize: Int, letterCase: LetterCasePolicy) {
        self.preview = preview
        self.history = history
        self.historySize = historySize
        self.letterCase = letterCase
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = FeatureFlags.builtIn
        preview = try container.decodeIfPresent(Bool.self, forKey: .preview) ?? defaults.preview
        history = try container.decodeIfPresent(Bool.self, forKey: .history) ?? defaults.history
        historySize =
            try container.decodeIfPresent(Int.self, forKey: .historySize) ?? defaults.historySize
        letterCase =
            try container.decodeIfPresent(LetterCasePolicy.self, forKey: .letterCase)
            ?? defaults.letterCase
    }
}

public struct PromptConfig: Sendable, Codable, Equatable {
    public var override: String?

    public static let builtIn = PromptConfig(override: nil)

    public init(override: String?) { self.override = override }

    private enum CodingKeys: String, CodingKey { case override }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        override = try container.decodeIfPresent(String.self, forKey: .override)
    }

    /// Writes `override: null` rather than letting the encoder drop the key.
    /// The whole point of materializing the config is that the user can see
    /// what is there to edit, and an omitted key is invisible — the file came
    /// out as `prompt: {}`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let override {
            try container.encode(override, forKey: .override)
        } else {
            try container.encodeNil(forKey: .override)
        }
    }
}

public struct Config: Sendable, Codable, Equatable {
    public var activeProfile: String
    public var profiles: [String: Profile]
    public var hotkeys: [HotkeyBinding]
    public var limits: Limits
    public var segmentation: SegmentationRules
    public var features: FeatureFlags
    public var prompt: PromptConfig

    public static let builtIn = Config(
        activeProfile: "local",
        profiles: [
            "local": Profile(
                kind: .ollama,
                endpoint: URL(string: "http://localhost:11434")!,
                model: "qwen3:4b-instruct",
                temperature: 0,
                timeoutSeconds: 30),
            "openai": Profile(
                kind: .openaiCompat,
                endpoint: URL(string: "https://api.openai.com/v1")!,
                model: "gpt-4o-mini",
                temperature: 0,
                timeoutSeconds: 30,
                apiKey: .keychain(account: "czechator-openai")),
        ],
        hotkeys: [HotkeyBinding(shortcut: "cmd+ctrl+d", source: "clipboard", sink: "clipboard")],
        limits: .builtIn,
        segmentation: .builtIn,
        features: .builtIn,
        prompt: .builtIn
    )

    public init(
        activeProfile: String, profiles: [String: Profile], hotkeys: [HotkeyBinding],
        limits: Limits, segmentation: SegmentationRules,
        features: FeatureFlags, prompt: PromptConfig
    ) {
        self.activeProfile = activeProfile
        self.profiles = profiles
        self.hotkeys = hotkeys
        self.limits = limits
        self.segmentation = segmentation
        self.features = features
        self.prompt = prompt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Config.builtIn
        activeProfile =
            try container.decodeIfPresent(String.self, forKey: .activeProfile)
            ?? defaults.activeProfile
        profiles =
            try container.decodeIfPresent([String: Profile].self, forKey: .profiles)
            ?? defaults.profiles
        hotkeys =
            try container.decodeIfPresent([HotkeyBinding].self, forKey: .hotkeys)
            ?? defaults.hotkeys
        limits = try container.decodeIfPresent(Limits.self, forKey: .limits) ?? defaults.limits
        segmentation =
            try container.decodeIfPresent(SegmentationRules.self, forKey: .segmentation)
            ?? defaults.segmentation
        features =
            try container.decodeIfPresent(FeatureFlags.self, forKey: .features) ?? defaults.features
        prompt = try container.decodeIfPresent(PromptConfig.self, forKey: .prompt) ?? defaults.prompt
    }

    /// The profile the tool will actually use.
    public var active: Profile? { profiles[activeProfile] }

    /// Catches the mistakes a hand-edited file makes that would otherwise only
    /// surface as a confusing transport error at the first keystroke.
    public func validate() throws {
        guard profiles[activeProfile] != nil else {
            throw ConfigError.unknownActiveProfile(activeProfile)
        }
        for (name, profile) in profiles.sorted(by: { $0.key < $1.key }) {
            // "localhost:11434" parses as a URL with scheme "localhost" and no
            // host — nonsense that only fails much later, at request time.
            guard let scheme = profile.endpoint.scheme,
                scheme == "http" || scheme == "https",
                profile.endpoint.host != nil
            else {
                throw ConfigError.invalidEndpoint(
                    profile: name, value: profile.endpoint.absoluteString)
            }
        }
    }
}

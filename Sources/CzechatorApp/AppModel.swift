import AppKit
import CzechatorCore
import SwiftUI

enum RunState: Equatable {
    case idle
    case working
    case failed(String)
}

struct HistoryEntry: Identifiable, Equatable {
    let id = UUID()
    let preview: String
    let originalText: String
    let succeeded: Bool
    let detail: String?
}

@MainActor
final class AppModel: ObservableObject {

    static let shared = AppModel()

    @Published private(set) var state: RunState = .idle
    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var startupProblem: String?

    private var started = false
    private var config: Config = .builtIn
    private let store = ConfigStore(url: ConfigStore.defaultURL())
    private let hotKeys = HotKeyManager()
    private let notifications = NotificationCenterBridge()
    private let source = PasteboardSource()
    private let sink = PasteboardSink()

    private init() {}

    var iconName: String {
        switch state {
        case .idle: return "textformat.abc.dottedunderline"
        case .working: return "hourglass"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    /// Only ever reflects the current state.
    ///
    /// Reaching into the history for the newest failure looked equivalent, but
    /// it kept the "last error" line on screen through every later success —
    /// for as long as that entry stayed in the history. The detail belongs in
    /// the history list, which is where it stays readable after acknowledgement.
    var lastErrorDetail: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    func start() {
        guard !started else { return }
        started = true
        notifications.onActivate = { [weak self] in self?.acknowledgeError() }
        notifications.requestAuthorization()
        reload()
    }

    /// Re-reads the config and re-registers the hotkey. Called at launch and
    /// after the settings window saves.
    func reload() {
        do {
            config = try store.load()
            guard let binding = config.hotkeys.first else {
                startupProblem = "Konfigurace neobsahuje žádnou zkratku."
                return
            }
            let spec = try ShortcutSpec.parse(binding.shortcut)
            startupProblem =
                spec.isCommonSystemShortcut
                ? "Zkratka \(binding.shortcut) je běžná systémová zkratka "
                    + "a v ostatních aplikacích přestane fungovat."
                : nil
            try hotKeys.register(spec) { [weak self] in
                Task { @MainActor in self?.run() }
            }
        } catch {
            startupProblem = ErrorMessages.describe(error)
        }
    }

    /// The error badge never survives a single click; the detail stays readable
    /// in the history below it.
    func acknowledgeError() {
        if case .failed = state { state = .idle }
    }

    func restore(_ entry: HistoryEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.originalText, forType: .string)
    }

    func run() {
        guard state != .working else { return }
        state = .working

        Task { @MainActor in
            do {
                let input = try source.read()
                guard let profile = config.active else {
                    throw ConfigError.unknownActiveProfile(config.activeProfile)
                }
                let pipeline = Pipeline(
                    registry: try FormatRegistry(rules: config.segmentation),
                    provider: try makeProvider(profile),
                    limits: config.limits,
                    promptOverride: config.prompt.override,
                    letterCase: config.features.letterCase)

                let result = try await pipeline.run(input)
                // Only ever reached on success: a throw anywhere above leaves
                // the clipboard exactly as the user left it.
                try sink.write(result)
                state = .idle
                record(
                    HistoryEntry(
                        preview: preview(of: result.correctedText),
                        originalText: result.originalText,
                        succeeded: true,
                        detail: nil))
            } catch {
                let message = ErrorMessages.describe(error)
                state = .failed(message)
                record(
                    HistoryEntry(
                        preview: preview(of: message), originalText: "",
                        succeeded: false, detail: message))
                notifications.post(title: "Czechator", body: message)
            }
        }
    }

    private func makeProvider(_ profile: Profile) throws -> any LLMProvider {
        let client = URLSessionHTTPClient()
        let key = try profile.apiKey.map { try KeychainSecretResolver().resolve($0) }
        switch profile.kind {
        case .ollama:
            return OllamaProvider(
                endpoint: profile.endpoint, model: profile.model,
                temperature: profile.temperature,
                timeout: profile.timeoutSeconds, client: client)
        case .openaiCompat:
            return OpenAICompatProvider(
                endpoint: profile.endpoint, model: profile.model,
                temperature: profile.temperature,
                timeout: profile.timeoutSeconds, apiKey: key, client: client)
        }
    }

    // MARK: - Settings

    var profileNames: [String] { config.profiles.keys.sorted() }
    var activeProfileName: String { config.activeProfile }
    var shortcutText: String { config.hotkeys.first?.shortcut ?? "cmd+ctrl+d" }

    func endpointDescription(for profile: String) -> String? {
        config.profiles[profile].map { "\($0.kind.rawValue) · \($0.endpoint) · \($0.model)" }
    }

    func keychainAccount(for profile: String) -> String? {
        if case .keychain(let account) = config.profiles[profile]?.apiKey { return account }
        return nil
    }

    /// Writes through ConfigStore, which preserves keys the app does not know
    /// about, then re-registers the hotkey.
    func applySettings(activeProfile: String, shortcut: String) {
        var updated = config
        updated.activeProfile = activeProfile
        if updated.hotkeys.isEmpty {
            updated.hotkeys = [
                HotkeyBinding(shortcut: shortcut, source: "clipboard", sink: "clipboard")
            ]
        } else {
            updated.hotkeys[0].shortcut = shortcut
        }
        do {
            try store.save(updated)
            reload()
        } catch {
            startupProblem = ErrorMessages.describe(error)
        }
    }

    private func record(_ entry: HistoryEntry) {
        guard config.features.history else { return }
        history.insert(entry, at: 0)
        if history.count > config.features.historySize {
            history.removeLast(history.count - config.features.historySize)
        }
    }

    private func preview(of text: String) -> String {
        let single = text.replacingOccurrences(of: "\n", with: " ")
        return single.count <= 40 ? single : String(single.prefix(40)) + "…"
    }
}

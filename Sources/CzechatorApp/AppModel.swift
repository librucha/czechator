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
    /// The double-tap trigger is selected but cannot run without the permission.
    @Published private(set) var needsAccessibility = false

    private var started = false
    private var config: Config = .builtIn
    private let store: ConfigStore
    /// Injected so that the trigger rules can be tested without asking the
    /// system for a permission the test machine may or may not have granted.
    private let accessibilityGranted: @MainActor () -> Bool
    private let makeTrigger: @MainActor (TriggerPlan) -> any Trigger
    private var trigger: (any Trigger)?
    private let notifications = NotificationCenterBridge()
    private let source = PasteboardSource()
    private let sink = PasteboardSink()

    init(
        store: ConfigStore = ConfigStore(url: ConfigStore.defaultURL()),
        accessibilityGranted: @escaping @MainActor () -> Bool = {
            AccessibilityPermission.isGranted
        },
        makeTrigger: @escaping @MainActor (TriggerPlan) -> any Trigger = makeLiveTrigger
    ) {
        self.store = store
        self.accessibilityGranted = accessibilityGranted
        self.makeTrigger = makeTrigger
    }

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
        // The permission can be revoked in System Settings while the app runs.
        // Coming back to the app is the other moment worth re-checking, besides
        // opening the menu — the settings window can be open the whole time.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccessibilityState() }
        }
        notifications.requestAuthorization()
        reload()
    }

    /// Re-reads the config and re-installs the trigger. Called at launch and
    /// after the settings window saves.
    func reload() {
        do {
            config = try store.load()
            trigger?.stop()
            trigger = nil
            needsAccessibility = false

            switch config.trigger.kind {
            case .combination:
                trigger = try startCombination()
            case .doubleTap:
                trigger = try startDoubleTap()
            }
        } catch {
            startupProblem = AppErrorMessages.describe(error)
        }
    }

    private func startCombination() throws -> (any Trigger)? {
        guard let binding = config.hotkeys.first else {
            startupProblem = "Konfigurace neobsahuje žádnou zkratku."
            return nil
        }
        let spec = try ShortcutSpec.parse(binding.shortcut)
        startupProblem =
            spec.isCommonSystemShortcut
            ? "Zkratka \(binding.shortcut) je běžná systémová zkratka "
                + "a v ostatních aplikacích přestane fungovat."
            : nil
        let trigger = makeTrigger(.combination(spec))
        try trigger.start { [weak self] in self?.run() }
        return trigger
    }

    private func startDoubleTap() throws -> (any Trigger)? {
        // No silent fallback to the combination: the user chose the double tap
        // precisely so that nothing gets stolen, and quietly registering a
        // stealing shortcut would put them back in the problem they left.
        guard accessibilityGranted() else {
            needsAccessibility = true
            startupProblem = ErrorMessages.accessibilityRequired
            return nil
        }
        startupProblem = nil
        let trigger = makeTrigger(.doubleTap(config.trigger))
        try trigger.start { [weak self] in self?.run() }
        return trigger
    }

    /// Re-installs the trigger when the permission has appeared or vanished
    /// since the last check — it can be revoked in System Settings while the
    /// app runs, and opening the menu is the cheapest place to notice.
    func refreshAccessibilityState() {
        guard config.trigger.kind == .doubleTap else { return }
        if accessibilityGranted() == needsAccessibility { reload() }
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

    var triggerKind: TriggerKind { config.trigger.kind }
    var triggerModifier: ModifierKey { config.trigger.modifier }
    var isAccessibilityGranted: Bool { accessibilityGranted() }

    /// Asks for the permission and opens the pane. The system dialog only
    /// appears the first time macOS is asked; the pane is what the user needs
    /// on every later attempt, which is why both happen.
    func grantAccessibility() {
        AccessibilityPermission.request()
        AccessibilityPermission.openSystemSettings()
    }

    /// Writes through ConfigStore, which preserves keys the app does not know
    /// about, then re-installs the trigger.
    ///
    /// Everything the settings window can change goes through this one call:
    /// two separate applies would mean two disk writes and two registrations
    /// per save, with a window in between where the file is half updated.
    func applySettings(
        activeProfile: String, shortcut: String,
        triggerKind: TriggerKind, triggerModifier: ModifierKey
    ) {
        var updated = config
        updated.activeProfile = activeProfile
        if updated.hotkeys.isEmpty {
            updated.hotkeys = [
                HotkeyBinding(shortcut: shortcut, source: "clipboard", sink: "clipboard")
            ]
        } else {
            updated.hotkeys[0].shortcut = shortcut
        }
        updated.trigger.kind = triggerKind
        updated.trigger.modifier = triggerModifier
        do {
            try store.save(updated)
            reload()
        } catch {
            startupProblem = AppErrorMessages.describe(error)
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

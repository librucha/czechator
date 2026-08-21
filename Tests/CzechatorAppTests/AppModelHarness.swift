import CzechatorCore
import Foundation

@testable import CzechatorApp

/// A trigger that records what was asked of it instead of touching the system.
@MainActor
final class SpyTrigger: Trigger {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    var failToStart: (any Error)?

    func start(_ action: @escaping @MainActor () -> Void) throws {
        if let failToStart { throw failToStart }
        startCount += 1
    }

    func stop() { stopCount += 1 }
}

/// An `AppModel` wired to a throwaway config file, a permission the test owns,
/// and triggers that only take notes.
@MainActor
final class Harness {
    let url: URL
    private(set) var plans: [TriggerPlan] = []
    private(set) var triggers: [SpyTrigger] = []
    var granted = true
    var nextFailure: (any Error)?
    private(set) var permissionRequests = 0
    private(set) var settingsOpened = 0

    init(_ yaml: String) throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("czechator-\(UUID().uuidString)")
            .appendingPathComponent("config.yaml")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }

    func makeModel() -> AppModel {
        AppModel(
            store: ConfigStore(url: url),
            accessibilityGranted: { [unowned self] in self.granted },
            requestAccessibility: { [unowned self] in self.permissionRequests += 1 },
            openAccessibilitySettings: { [unowned self] in self.settingsOpened += 1 },
            makeTrigger: { [unowned self] plan in
                self.plans.append(plan)
                let spy = SpyTrigger()
                spy.failToStart = self.nextFailure
                self.triggers.append(spy)
                return spy
            })
    }

    /// A model that has already read the config, the way the app is by the time
    /// the settings window can be opened.
    func startedModel() -> AppModel {
        let model = makeModel()
        model.reload()
        return model
    }

    func fileContents() throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// Reads the file back through a fresh store, which is what the app will do
    /// on its next launch.
    func reloadedFromDisk() throws -> Config {
        try ConfigStore(url: url).load()
    }
}

let baseConfig = """
    activeProfile: local
    profiles:
      local:
        kind: ollama
        endpoint: http://localhost:11434
        model: qwen3:4b-instruct
        temperature: 0
        timeoutSeconds: 30
      openai:
        kind: openai-compat
        endpoint: https://api.openai.com/v1
        model: gpt-4o-mini
        temperature: 0
        timeoutSeconds: 30
    hotkeys:
      - shortcut: cmd+ctrl+d
        source: clipboard
        sink: clipboard
    """

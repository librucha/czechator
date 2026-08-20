import Foundation
import Testing

@testable import CzechatorCore

private func temporaryStore() -> (ConfigStore, URL) {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("czechator-test-\(UUID().uuidString)")
    let url = directory.appendingPathComponent("config.yaml")
    return (ConfigStore(url: url), url)
}

private func write(_ yaml: String, to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try yaml.write(to: url, atomically: true, encoding: .utf8)
}

@Test func writesFullDefaultsOnFirstLoad() throws {
    let (store, url) = temporaryStore()
    let config = try store.load()

    #expect(config == .builtIn)
    #expect(FileManager.default.fileExists(atPath: url.path))

    let written = try String(contentsOf: url, encoding: .utf8)
    // The segmentation block must be materialized in full so it can be edited
    // without reading the source.
    #expect(written.contains("segmentation"))
    #expect(written.contains("skipValuesForKeys"))
    #expect(written.contains("cmd+ctrl+d"))
}

@Test func fillsMissingKeysFromDefaults() throws {
    let (store, url) = temporaryStore()
    try write(
        """
        activeProfile: local
        profiles:
          local:
            kind: ollama
            endpoint: http://localhost:11434
            model: gemma3:4b
            temperature: 0
            timeoutSeconds: 30
        """, to: url)

    let config = try store.load()
    #expect(config.profiles["local"]?.model == "gemma3:4b")
    #expect(config.limits == .builtIn)
    #expect(config.segmentation == .builtIn)
    #expect(config.features == .builtIn)
}

@Test func savePreservesUnknownKeys() throws {
    let (store, url) = temporaryStore()
    _ = try store.load()

    var text = try String(contentsOf: url, encoding: .utf8)
    text += "\nmojePoznamka: neco vlastniho\n"
    try text.write(to: url, atomically: true, encoding: .utf8)

    var config = try store.load()
    config.activeProfile = "openai"
    try store.save(config)

    let saved = try String(contentsOf: url, encoding: .utf8)
    #expect(saved.contains("mojePoznamka: neco vlastniho"))
    #expect(saved.contains("activeProfile: openai"))
}

@Test func rejectsEndpointWithoutAScheme() throws {
    let (store, url) = temporaryStore()
    try write(
        """
        activeProfile: local
        profiles:
          local:
            kind: ollama
            endpoint: localhost:11434
            model: m
            temperature: 0
            timeoutSeconds: 30
        """, to: url)

    #expect(throws: ConfigError.invalidEndpoint(profile: "local", value: "localhost:11434")) {
        try store.load()
    }
}

@Test func rejectsAnActiveProfileThatDoesNotExist() throws {
    let (store, url) = temporaryStore()
    try write(
        """
        activeProfile: neexistuje
        profiles:
          local:
            kind: ollama
            endpoint: http://localhost:11434
            model: m
            temperature: 0
            timeoutSeconds: 30
        """, to: url)

    #expect(throws: ConfigError.unknownActiveProfile("neexistuje")) { try store.load() }
}

@Test func defaultsPointAtTheExpectedLocation() {
    #expect(ConfigStore.defaultURL().path.hasSuffix(".config/czechator/config.yaml"))
}

@Test func defaultProfileIsLocalOllamaWithTemperatureZero() {
    let profile = Config.builtIn.profiles["local"]
    #expect(Config.builtIn.activeProfile == "local")
    #expect(profile?.kind == .ollama)
    #expect(profile?.temperature == 0)
    #expect(Config.builtIn.hotkeys.first?.shortcut == "cmd+ctrl+d")
    #expect(Config.builtIn.hotkeys.first?.source == "clipboard")
    #expect(Config.builtIn.hotkeys.first?.sink == "clipboard")
}

@Test func saveRefusesToWriteAnInvalidConfig() throws {
    let (store, _) = temporaryStore()
    var config = try store.load()
    config.activeProfile = "neexistuje"
    #expect(throws: ConfigError.unknownActiveProfile("neexistuje")) { try store.save(config) }
}

@Test func rejectsNonHTTPSchemes() throws {
    let (store, url) = temporaryStore()
    try write(
        """
        activeProfile: local
        profiles:
          local:
            kind: ollama
            endpoint: ftp://example.com
            model: m
            temperature: 0
            timeoutSeconds: 30
        """, to: url)
    #expect(throws: ConfigError.invalidEndpoint(profile: "local", value: "ftp://example.com")) {
        try store.load()
    }
}

@Test func rejectsAnEmptyProfileMap() throws {
    let (store, url) = temporaryStore()
    try write("activeProfile: local\nprofiles: {}\n", to: url)
    #expect(throws: ConfigError.unknownActiveProfile("local")) { try store.load() }
}

@Test func clampsNonsensicalLimits() throws {
    let json = Data(#"{"maxInputBytes":0,"maxBatchChars":0}"#.utf8)
    let limits = try JSONDecoder().decode(Limits.self, from: json)
    #expect(limits.maxInputBytes >= 1)
    #expect(limits.maxBatchChars >= 1)
}

@Test func materializesThePromptOverrideKeyEvenWhenEmpty() throws {
    let (store, url) = temporaryStore()
    _ = try store.load()
    let written = try String(contentsOf: url, encoding: .utf8)
    // "prompt: {}" hides the one key the user might want to set.
    #expect(written.contains("override"))
    #expect(!written.contains("prompt: {}"))
}

@Test func upgradingAnOlderInstallKeepsTheCombinationTrigger() throws {
    // The config file is materialized on first run and from then on overrides
    // the built-in values. A config written before the trigger existed has no
    // trigger block at all, and adding one must not change how that install
    // behaves — the same materialization rule that once kept a safety default
    // from ever reaching an existing installation.
    let (store, url) = temporaryStore()
    try write(
        """
        activeProfile: local
        profiles:
          local:
            kind: ollama
            endpoint: http://localhost:11434
            model: qwen3:4b-instruct
            temperature: 0
            timeoutSeconds: 30
        hotkeys:
          - shortcut: cmd+ctrl+d
            source: clipboard
            sink: clipboard
        """, to: url)

    let loaded = try store.load()
    #expect(loaded.trigger.kind == .combination)
    #expect(loaded.trigger.modifier == .rightCommand)
    #expect(loaded.trigger.intervalMs == 300)
    #expect(loaded.trigger.maxHoldMs == 500)

    // And once anything is saved, the block becomes visible so the user can see
    // there is something to edit.
    try store.save(loaded)
    let saved = try String(contentsOf: url, encoding: .utf8)
    #expect(saved.contains("trigger:"))
    #expect(saved.contains("kind: combination"))
}

import ArgumentParser
import CzechatorCore
import Foundation

struct FixCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fix",
        abstract: "Doplní českou diakritiku a výsledek vypíše na standardní výstup."
    )

    @Argument(help: "Cesta k souboru, nebo - pro standardní vstup.")
    var path: String = "-"

    @Option(name: .long, help: "Název profilu z konfigurace.")
    var profile: String?

    @Option(name: .long, help: "Cesta ke konfiguraci.")
    var config: String?

    func run() async throws {
        let environment = try CLIEnvironment.load(configPath: config, profileName: profile)
        let text = try CLIEnvironment.readInput(path: path)

        let pipeline = Pipeline(
            registry: environment.registry,
            provider: try environment.makeProvider(),
            limits: environment.config.limits,
            promptOverride: environment.config.prompt.override)

        do {
            let result = try await pipeline.run(ClipboardInput(text: text))
            print(result.correctedText, terminator: "")
        } catch let error as PipelineError {
            // Errors go to stderr with a non-zero exit code, so a failure in a
            // shell pipeline is visible instead of silently producing no output.
            FileHandle.standardError.write(Data((ErrorMessages.describe(error) + "\n").utf8))
            throw ExitCode.failure
        }
    }
}

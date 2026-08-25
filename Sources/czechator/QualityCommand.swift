import ArgumentParser
import CzechatorCore
import Foundation

struct QualityCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "quality",
        abstract: "Změří profily a režimy oprav na sadě vzorků."
    )

    @Option(name: .long, help: "Profil z konfigurace. Lze uvést vícekrát.")
    var profile: [String] = []

    @Option(
        name: .long,
        help: "Režim oprav: strict, minor-fixes, proofread nebo all. Lze uvést vícekrát.")
    var corrections: [String] = []

    @Option(name: .long, help: "Adresář s vlastní sadou vzorků (.in/.want).")
    var fixturesDir: String?

    @Option(name: .long, help: "Přepíše model u všech měřených profilů.")
    var model: String?

    @Option(name: .long, help: "preserve, segmentStart nebo model. Působí jen v přísném režimu.")
    var letterCase: String = "preserve"

    @Option(name: .long, help: "Formát výstupu: terminal nebo md.")
    var format: String = "terminal"

    @Option(name: .long, help: "auto, always nebo never. Jen pro terminal.")
    var color: String = "auto"

    @Option(name: .long, help: "Cesta ke konfiguraci.")
    var config: String?

    @Flag(name: .long, help: "Vypíše i vzorky, které prošly.")
    var verbose = false

    func run() async throws {
        // Parsed before the sweep, like `--letter-case`: a typo in --format
        // must not be discovered only after paying for the whole measurement.
        let outputFormat = try parsedFormat()
        let environment = try CLIEnvironment.load(configPath: config, profileName: nil)
        let policy = try parsedPolicy()
        let profiles = profile.isEmpty ? [environment.config.activeProfile] : profile
        let modes = try parsedModes(environment.config, profiles: profiles)
        let sets = try fixtureSets()

        let report: QualityReport
        do {
            report = try await measure(
                environment: environment, sets: sets, profiles: profiles, modes: modes,
                policy: policy)
        } catch let error as QualityError {
            // Same shape as `fix`: the error goes to stderr with a non-zero
            // exit code, so an unreachable model reads as a failed run
            // instead of a table of zeroes that looks like a verdict on it.
            FileHandle.standardError.write(Data((ErrorMessages.describe(error) + "\n").utf8))
            throw ExitCode.failure
        }

        switch outputFormat {
        case .markdown:
            print(MarkdownFormatter.render(report), terminator: "")
        case .terminal:
            print(
                TerminalFormatter.render(report, color: colorWanted(), verbose: verbose),
                terminator: "")
        }
    }

    private enum OutputFormat {
        case terminal
        case markdown
    }

    private func parsedFormat() throws -> OutputFormat {
        switch format {
        case "md": return .markdown
        case "terminal": return .terminal
        default:
            throw ValidationError("neznámý formát: \(format) (terminal, md)")
        }
    }

    private func measure(
        environment: CLIEnvironment, sets: [QualityFixtureSet], profiles: [String],
        modes: [CorrectionMode], policy: LetterCasePolicy
    ) async throws -> QualityReport {
        var forced = false
        var results: [QualitySetResult] = []

        for set in sets {
            var cells: [QualityCell] = []
            for name in profiles {
                guard var profile = environment.config.profiles[name] else {
                    throw ValidationError("neznámý profil: \(name)")
                }
                if let model { profile.model = model }
                // Read before the sweep: `Pipeline` is told the mode and the
                // verification flag directly, so the profile itself is never
                // mutated for them.
                if !profile.verification { forced = true }
                for mode in modes {
                    let pipeline = Pipeline(
                        registry: environment.registry,
                        provider: try environment.makeProvider(for: profile),
                        limits: environment.config.limits,
                        promptOverride: environment.config.prompt.override,
                        letterCase: policy,
                        corrections: mode,
                        editBudget: profile.editBudget,
                        verification: true)

                    let outcome = try await QualityRunner.run(
                        set: set, pipeline: pipeline, mode: mode, policy: policy)

                    cells.append(
                        QualityCell(
                            profileName: name, model: profile.model, corrections: mode,
                            budget: mode.isTolerant ? profile.editBudget : nil,
                            exact: outcome.exact, accepted: outcome.accepted,
                            refused: outcome.refused, total: outcome.total,
                            misses: outcome.misses, passed: outcome.passed))
                }
            }
            results.append(
                QualitySetResult(
                    setName: set.name, sampleCount: set.samples.count, cells: cells))
        }

        return QualityReport(
            version: CzechatorCore.Czechator.version,
            measuredOn: Self.today(),
            letterCase: policy,
            invocation: invocation(profiles: profiles, modes: modes),
            verificationForced: forced,
            sets: results)
    }

    private func parsedPolicy() throws -> LetterCasePolicy {
        guard let policy = LetterCasePolicy(rawValue: letterCase) else {
            throw ValidationError(
                "neznámá hodnota --letter-case: \(letterCase) (preserve, segmentStart, model)")
        }
        return policy
    }

    /// With no `--corrections`, each profile is measured in the mode it is
    /// actually configured for: bare `czechator quality` answers "how is what I
    /// use doing", not "how is the default doing".
    private func parsedModes(_ config: Config, profiles: [String]) throws -> [CorrectionMode] {
        guard !corrections.isEmpty else {
            var out: [CorrectionMode] = []
            for name in profiles {
                let mode = config.profiles[name]?.corrections ?? .strict
                if !out.contains(mode) { out.append(mode) }
            }
            return out
        }
        guard let modes = CorrectionMode.expand(corrections) else {
            throw ValidationError(
                "neznámý režim v --corrections (strict, minor-fixes, proofread, all)")
        }
        return modes
    }

    private func fixtureSets() throws -> [QualityFixtureSet] {
        guard let fixturesDir else { return [QualityFixtures.clean, QualityFixtures.typos] }
        return [try QualityFixtures.load(directory: URL(fileURLWithPath: fixturesDir))]
    }

    private func colorWanted() -> Bool {
        switch color {
        case "always": return true
        case "never": return false
        default:
            return isatty(STDOUT_FILENO) == 1
                && ProcessInfo.processInfo
                    .environment["NO_COLOR"] == nil
        }
    }

    /// Rebuilt from the parsed options rather than from CommandLine.arguments:
    /// `--config` carries the user's home directory and must not reach a table
    /// that gets committed.
    private func invocation(profiles: [String], modes: [CorrectionMode]) -> String {
        var parts = ["czechator quality"]
        for name in profiles { parts.append("--profile \(name)") }
        for mode in modes { parts.append("--corrections \(mode.rawValue)") }
        if let model { parts.append("--model \(model)") }
        if let fixturesDir { parts.append("--fixtures-dir \(fixturesDir)") }
        if letterCase != "preserve" { parts.append("--letter-case \(letterCase)") }
        return parts.joined(separator: " ")
    }

    private static func today() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }
}

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

    @Option(
        name: .long,
        help: "preserve, segmentStart nebo model. Výchozí z konfigurace, jen v přísném režimu.")
    var letterCase: String?

    @Option(name: .long, help: "Formát výstupu: terminal nebo md.")
    var format: String = "terminal"

    @Option(name: .long, help: "auto, always nebo never. Jen pro terminal.")
    var color: String = "auto"

    @Option(name: .long, help: "Cesta ke konfiguraci.")
    var config: String?

    @Flag(name: .long, help: "Vypíše i vzorky, které prošly.")
    var verbose = false

    func run() async throws {
        // Everything that can fail for free is decided here, before the sweep.
        // A typo in --format, an unknown profile or a key that will not resolve
        // must not be discovered only after paying for half the measurement —
        // this tool has no spending guard at all.
        let outputFormat = try parsedFormat()
        let environment = try CLIEnvironment.load(configPath: config, profileName: nil)
        let policy = try parsedPolicy(environment.config)
        let names = profile.isEmpty ? [environment.config.activeProfile] : profile
        let modes = try parsedModes(environment.config, profiles: names)
        let profiles = try resolvedProfiles(environment.config, names: names)

        let report: QualityReport
        do {
            // Built once per profile, not once per cell: a fresh
            // URLSessionHTTPClient per cell was pure waste, and a Keychain
            // entry that cannot be read has to say so before the first call.
            var providers: [String: any LLMProvider] = [:]
            for entry in profiles {
                providers[entry.name] = try environment.makeProvider(for: entry.profile)
            }
            let sets = try fixtureSets()

            report = try await measure(
                environment: environment, sets: sets, profiles: profiles, modes: modes,
                providers: providers, policy: policy)
        } catch let error as QualityError {
            throw reported(error)
        } catch let error as QualityFixtureError {
            throw reported(error)
        } catch let error as SecretError {
            throw reported(error)
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

    /// Same shape as `fix`: the message goes to stderr in Czech with a non-zero
    /// exit code, so an unreachable model or an unreadable fixture directory
    /// reads as a failed run instead of a table of zeroes that looks like a
    /// verdict — and never as a raw Swift enum.
    private func reported(_ error: any Error) -> ExitCode {
        FileHandle.standardError.write(Data((ErrorMessages.describe(error) + "\n").utf8))
        return .failure
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

    /// Resolves every named profile up front, so `--profile local --profile
    /// clode` costs nothing instead of the whole of `local`.
    private func resolvedProfiles(_ config: Config, names: [String]) throws -> [QualityProfile] {
        try names.map { name in
            guard var profile = config.profiles[name] else {
                throw ValidationError("neznámý profil: \(name)")
            }
            if let model { profile.model = model }
            return QualityProfile(name: name, profile: profile)
        }
    }

    private func measure(
        environment: CLIEnvironment, sets: [QualityFixtureSet], profiles: [QualityProfile],
        modes: [CorrectionMode], providers: [String: any LLMProvider], policy: LetterCasePolicy
    ) async throws -> QualityReport {
        // Read before the sweep: `Pipeline` is told the mode and the
        // verification flag directly, so the profile itself is never mutated
        // for them.
        let forced = profiles.contains { !$0.profile.verification }
        let matrix = QualityMatrix.cells(profiles: profiles, modes: modes)
        var results: [QualitySetResult] = []

        for set in sets {
            var cells: [QualityCell] = []
            for cell in matrix {
                guard let provider = providers[cell.profileName] else {
                    // Unreachable: both are keyed by the same resolved names.
                    throw ValidationError("neznámý profil: \(cell.profileName)")
                }
                let pipeline = Pipeline(
                    registry: environment.registry,
                    provider: provider,
                    limits: environment.config.limits,
                    promptOverride: environment.config.prompt.override,
                    letterCase: policy,
                    corrections: cell.corrections,
                    editBudget: cell.profile.editBudget,
                    verification: true)

                let outcome = try await QualityRunner.run(
                    set: set, pipeline: pipeline, mode: cell.corrections, policy: policy)

                cells.append(
                    QualityCell(
                        profileName: cell.profileName, model: cell.model,
                        corrections: cell.corrections, budget: cell.budget,
                        exact: outcome.exact, accepted: outcome.accepted,
                        refused: outcome.refused, total: outcome.total,
                        misses: outcome.misses, passed: outcome.passed))
            }
            results.append(
                QualitySetResult(
                    setName: set.name, sampleCount: set.samples.count, cells: cells))
        }

        return QualityReport(
            version: CzechatorCore.Czechator.version,
            measuredOn: Self.today(),
            letterCase: policy,
            invocation: QualityMatrix.invocation(
                profiles: profiles.map(\.name), modes: modes, model: model,
                fixturesDir: fixturesDir, letterCase: policy),
            verificationForced: forced,
            sets: results)
    }

    /// Defaults to the configured policy, the way `fix` reads it: measuring a
    /// hardcoded `preserve` would report numbers about a setup the user does
    /// not run.
    private func parsedPolicy(_ config: Config) throws -> LetterCasePolicy {
        guard let letterCase else { return config.features.letterCase }
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

    private static func today() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }
}

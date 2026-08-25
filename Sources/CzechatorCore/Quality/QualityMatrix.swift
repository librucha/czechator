import Foundation

/// A profile as the sweep sees it: the configuration entry plus the name it is
/// listed under, because `Profile` itself carries no name and the table column
/// does.
public struct QualityProfile: Sendable, Equatable {
    public let name: String
    /// With `--model` already applied, if one was given.
    public let profile: Profile

    public init(name: String, profile: Profile) {
        self.name = name
        self.profile = profile
    }
}

/// One cell of the matrix, decided before a single model call is paid for.
///
/// Kept out of the command on purpose: this is the decision that shapes a
/// published table, and in the command it was testable only by running the
/// whole sweep against a model.
public struct QualityMatrixCell: Sendable, Equatable {
    public let profileName: String
    /// Kept whole rather than reduced to its identity: the sweep still needs
    /// the endpoint, the budget it charges edits against and the verification
    /// flag it reports as forced.
    public let profile: Profile
    public let corrections: CorrectionMode

    public init(profileName: String, profile: Profile, corrections: CorrectionMode) {
        self.profileName = profileName
        self.profile = profile
        self.corrections = corrections
    }

    public var model: String { profile.model }

    /// nil in strict mode, where the budget is forced to zero and means nothing.
    public var budget: EditBudget? { corrections.isTolerant ? profile.editBudget : nil }
}

public enum QualityMatrix {

    /// The cartesian product of profiles and modes, profile-major and in the
    /// order given, so the rows of a table come out in the order they were
    /// asked for.
    public static func cells(
        profiles: [QualityProfile], modes: [CorrectionMode]
    ) -> [QualityMatrixCell] {
        var out: [QualityMatrixCell] = []
        for entry in profiles {
            for mode in modes {
                out.append(
                    QualityMatrixCell(
                        profileName: entry.name, profile: entry.profile, corrections: mode))
            }
        }
        return out
    }

    /// The command that reproduces the run, rebuilt from the parsed options
    /// rather than from `CommandLine.arguments`.
    ///
    /// **No option that carries a path gets in.** `--config` is the obvious
    /// one, but `--fixtures-dir ~/Documents/moje-vzorky` holds the same user
    /// name, and this string is written into a table people commit. The
    /// fixtures directory therefore appears as its last component only — the
    /// set is named after it in the heading above anyway.
    public static func invocation(
        profiles: [String], modes: [CorrectionMode], model: String?,
        fixturesDir: String?, letterCase: LetterCasePolicy
    ) -> String {
        var parts = ["czechator quality"]
        for name in profiles { parts.append("--profile \(name)") }
        for mode in modes { parts.append("--corrections \(mode.rawValue)") }
        if let model { parts.append("--model \(model)") }
        if let fixturesDir {
            parts.append(
                "--fixtures-dir \(URL(fileURLWithPath: fixturesDir).lastPathComponent)")
        }
        if letterCase != .preserve { parts.append("--letter-case \(letterCase.rawValue)") }
        return parts.joined(separator: " ")
    }
}

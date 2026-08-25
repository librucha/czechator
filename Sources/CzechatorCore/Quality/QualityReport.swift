/// One sample that did not come out equal to its reference.
public struct QualityMiss: Sendable, Equatable {
    public let sample: String
    /// Empty when the run was refused: the pipeline threw, so there is no output.
    public let got: String
    public let want: String
    public let refused: Bool

    public init(sample: String, got: String, want: String, refused: Bool) {
        self.sample = sample
        self.got = got
        self.want = want
        self.refused = refused
    }
}

/// One profile measured in one correction mode over one fixture set.
public struct QualityCell: Sendable, Equatable {
    public let profileName: String
    public let model: String
    public let corrections: CorrectionMode
    /// nil in strict mode, where the budget is forced to zero and means nothing.
    public let budget: EditBudget?
    public let exact: Int
    public let accepted: Int
    public let refused: Int
    public let total: Int
    public let misses: [QualityMiss]
    /// Names of the samples that matched exactly. Only `--verbose` prints them,
    /// but they cannot be derived after the fact, so the run records them.
    public let passed: [String]

    public init(
        profileName: String, model: String, corrections: CorrectionMode,
        budget: EditBudget?, exact: Int, accepted: Int, refused: Int, total: Int,
        misses: [QualityMiss], passed: [String]
    ) {
        self.profileName = profileName
        self.model = model
        self.corrections = corrections
        self.budget = budget
        self.exact = exact
        self.accepted = accepted
        self.refused = refused
        self.total = total
        self.misses = misses
        self.passed = passed
    }
}

public struct QualitySetResult: Sendable, Equatable {
    public let setName: String
    public let sampleCount: Int
    public let cells: [QualityCell]

    public init(setName: String, sampleCount: Int, cells: [QualityCell]) {
        self.setName = setName
        self.sampleCount = sampleCount
        self.cells = cells
    }
}

/// A finished measurement, before anything decides how to draw it.
///
/// Separating the value from its rendering is what makes both formatters
/// testable without calling a model once.
public struct QualityReport: Sendable, Equatable {
    public let version: String
    /// Injected rather than read from the clock, so the formatters are testable.
    public let measuredOn: String
    public let letterCase: LetterCasePolicy
    /// Rebuilt from the parsed options, never from CommandLine.arguments, and
    /// never carrying `--config` — that path holds the user's home directory.
    public let invocation: String
    public let verificationForced: Bool
    public let sets: [QualitySetResult]

    public init(
        version: String, measuredOn: String, letterCase: LetterCasePolicy,
        invocation: String, verificationForced: Bool, sets: [QualitySetResult]
    ) {
        self.version = version
        self.measuredOn = measuredOn
        self.letterCase = letterCase
        self.invocation = invocation
        self.verificationForced = verificationForced
        self.sets = sets
    }
}

public struct QualityOutcome: Sendable, Equatable {
    public let exact: Int
    public let accepted: Int
    public let refused: Int
    public let total: Int
    public let misses: [QualityMiss]
    /// Names of the samples that matched exactly, for `--verbose`.
    public let passed: [String]

    public init(
        exact: Int, accepted: Int, refused: Int, total: Int,
        misses: [QualityMiss], passed: [String]
    ) {
        self.exact = exact
        self.accepted = accepted
        self.refused = refused
        self.total = total
        self.misses = misses
        self.passed = passed
    }
}

public enum QualityError: Error, Equatable {
    /// The run could not be measured, as opposed to measuring badly.
    ///
    /// An unreachable model, a 401, or a fixture the tool cannot parse all say
    /// the measurement is invalid. Counting them as failures would produce a
    /// table of zeroes that reads like a verdict on the model.
    case measurementInvalid(sample: String, reason: PipelineError)
}

public enum QualityRunner {

    public static func run(
        set: QualityFixtureSet,
        pipeline: Pipeline,
        mode: CorrectionMode,
        policy: LetterCasePolicy
    ) async throws -> QualityOutcome {
        var exact = 0
        var accepted = 0
        var refused = 0
        var misses: [QualityMiss] = []
        var passed: [String] = []

        for sample in set.samples {
            do {
                let result = try await pipeline.run(ClipboardInput(text: sample.input))
                accepted += 1
                if QualityComparison.matches(
                    got: result.correctedText, want: sample.want, mode: mode, policy: policy)
                {
                    exact += 1
                    passed.append(sample.name)
                } else {
                    misses.append(
                        QualityMiss(
                            sample: sample.name, got: result.correctedText,
                            want: sample.want, refused: false))
                }
            } catch let error as PipelineError {
                guard case .verificationFailed = error else {
                    throw QualityError.measurementInvalid(sample: sample.name, reason: error)
                }
                refused += 1
                // The pipeline threw, so there is no output to record.
                misses.append(
                    QualityMiss(
                        sample: sample.name, got: "", want: sample.want, refused: true))
            }
        }

        return QualityOutcome(
            exact: exact, accepted: accepted, refused: refused,
            total: set.samples.count, misses: misses, passed: passed)
    }
}

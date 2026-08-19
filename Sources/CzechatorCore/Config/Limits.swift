public struct Limits: Sendable, Codable, Equatable {
    public var maxInputBytes: Int
    public var maxBatchChars: Int

    public static let builtIn = Limits(maxInputBytes: 51_200, maxBatchChars: 1_500)

    public init(maxInputBytes: Int, maxBatchChars: Int) {
        self.maxInputBytes = maxInputBytes
        self.maxBatchChars = maxBatchChars
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Limits.builtIn
        maxInputBytes =
            try container.decodeIfPresent(Int.self, forKey: .maxInputBytes)
            ?? defaults.maxInputBytes
        maxBatchChars =
            try container.decodeIfPresent(Int.self, forKey: .maxBatchChars)
            ?? defaults.maxBatchChars
    }
}

import Foundation

/// One entry of the personal dictionary: wherever the model's output folds to
/// `from`, write `to`'s diacritics instead. A rule may change diacritics only —
/// the same promise the rest of the tool keeps — so `from` and `to` fold to the
/// same letters, case aside. `from == to` protects a term from accents the
/// model would add (`google docs` → `google dočš`).
public struct DictionaryRule: Sendable, Codable, Equatable {
    public var from: String
    public var to: String

    public init(from: String, to: String) {
        self.from = Self.clean(from)
        self.to = Self.clean(to)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            from: try container.decode(String.self, forKey: .from),
            to: try container.decode(String.self, forKey: .to))
    }

    private enum CodingKeys: String, CodingKey { case from, to }

    /// Pasted text often arrives decomposed (`s` + U+030C) or with a stray
    /// space at an edge; neither is part of the rule.
    private static func clean(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum DictionaryRuleProblem: Sendable, Equatable {
    case empty
    /// Plain text is segmented per line, so a rule spanning lines never matches.
    case multiline
    case differsBeyondDiacritics
}

extension DictionaryRule {
    public var problem: DictionaryRuleProblem? {
        if from.isEmpty || to.isEmpty { return .empty }
        if from.contains(where: \.isNewline) || to.contains(where: \.isNewline) { return .multiline }
        if matchKey != DiacriticFolding.fold(to).lowercased() { return .differsBeyondDiacritics }
        return nil
    }

    /// One word matches every occurrence regardless of context, which the
    /// settings window warns about.
    public var isSingleWord: Bool { !from.contains(where: \.isWhitespace) }

    /// What a match is looked up by: two rules with the same key would catch
    /// the same text, so the key is also what makes a rule a duplicate.
    public var matchKey: String { DiacriticFolding.fold(from).lowercased() }
}

public struct PersonalDictionary: Sendable, Equatable {
    public let rules: [DictionaryRule]

    public init(rules: [DictionaryRule]) { self.rules = rules }

    public static let empty = PersonalDictionary(rules: [])
}

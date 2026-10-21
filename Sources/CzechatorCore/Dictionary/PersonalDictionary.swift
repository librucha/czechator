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

/// Where a rule was written into an output, in grapheme indices of that output.
public struct DictionaryApplication: Sendable, Equatable {
    public let rule: DictionaryRule
    public let range: Range<Int>

    public init(rule: DictionaryRule, range: Range<Int>) {
        self.rule = rule
        self.range = range
    }
}

extension PersonalDictionary {

    /// Writes each matching rule's diacritics into `output`, the model's
    /// answer for the segment `source`.
    ///
    /// A match ignores diacritics and case and sits on word boundaries. It is
    /// applied only where the corresponding stretch of `source` carries no
    /// diacritics: the dictionary corrects the model, never what the user typed
    /// on purpose (`řad` stays `řad` under a `rad → rád` rule). Letter case is
    /// taken from the output, so strict mode's case alignment survives.
    public func apply(to output: String, source: String) -> (text: String, applied: [DictionaryApplication]) {
        guard !rules.isEmpty else { return (output, []) }
        var out = Array(output)
        let input = Array(source)
        let keys = out.map(Self.key)
        let toInput = Self.outputToInput(input: input, output: out)

        var candidates: [(rule: DictionaryRule, range: Range<Int>)] = []
        for rule in rules {
            let pattern = Array(rule.from).map(Self.key)
            guard !pattern.isEmpty, pattern.count <= out.count else { continue }
            for start in 0...(out.count - pattern.count) {
                let range = start..<(start + pattern.count)
                guard Self.matches(pattern, keys: keys, at: start), Self.onWordBoundaries(range, in: out),
                    Self.inputIsPlain(range, toInput: toInput, input: input)
                else { continue }
                candidates.append((rule, range))
            }
        }
        candidates.sort { ($0.range.count, -$0.range.lowerBound) > ($1.range.count, -$1.range.lowerBound) }

        var taken: [DictionaryApplication] = []
        for candidate in candidates where !taken.contains(where: { $0.range.overlaps(candidate.range) }) {
            for (offset, replacement) in Array(candidate.rule.to).enumerated() {
                let index = candidate.range.lowerBound + offset
                guard !out[index].isWhitespace else { continue }
                out[index] = Self.withCase(of: out[index], replacement)
            }
            taken.append(DictionaryApplication(rule: candidate.rule, range: candidate.range))
        }
        return (String(out), taken.sorted { $0.range.lowerBound < $1.range.lowerBound })
    }

    /// Diacritics and case folded away; any whitespace counts as a space, so a
    /// rule's space also matches the non-breaking one of an HTML document.
    private static func key(_ character: Character) -> String {
        character.isWhitespace ? " " : DiacriticFolding.fold(String(character)).lowercased()
    }

    private static func matches(_ pattern: [String], keys: [String], at start: Int) -> Bool {
        pattern.indices.allSatisfy { keys[start + $0] == pattern[$0] }
    }

    private static func onWordBoundaries(_ range: Range<Int>, in text: [Character]) -> Bool {
        func isWordCharacter(_ index: Int) -> Bool {
            text.indices.contains(index) && (text[index].isLetter || text[index].isNumber)
        }
        return !isWordCharacter(range.lowerBound - 1) && !isWordCharacter(range.upperBound)
    }

    /// Output index → input index. Identity when the model only changed
    /// diacritics; otherwise the edit alignment, inverted. Nil when there is
    /// no alignment to be had.
    private static func outputToInput(input: [Character], output: [Character]) -> [Int: Int]? {
        if input.count == output.count {
            return Dictionary(uniqueKeysWithValues: output.indices.map { ($0, $0) })
        }
        guard
            let alignment = EditAlignment.compute(
                input, output, limit: DiacriticVerifier.toleranceLimit)
        else { return nil }
        return Dictionary(alignment.map.map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Every output position of the match has an input position, and none of
    /// those carries a diacritic. Uncertainty means leaving the output alone.
    private static func inputIsPlain(_ range: Range<Int>, toInput: [Int: Int]?, input: [Character]) -> Bool {
        guard let toInput else { return false }
        return range.allSatisfy { index in
            guard let source = toInput[index] else { return false }
            let character = String(input[source])
            return DiacriticFolding.fold(character) == character
        }
    }

    /// A case mapping that changes length ("ß" → "SS") cannot replace one
    /// character; the output's own character is kept then.
    private static func withCase(of current: Character, _ replacement: Character) -> Character {
        let mapped =
            current.isUppercase
            ? String(replacement).uppercased()
            : current.isLowercase ? String(replacement).lowercased() : String(replacement)
        return mapped.count == 1 ? Character(mapped) : current
    }
}

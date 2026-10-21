import Foundation
import Testing

@testable import CzechatorCore

// MARK: - Rules

@Test func acceptsRulesThatDifferOnlyInDiacriticsAndCase() {
    #expect(DictionaryRule(from: "google docs", to: "google docs").problem == nil)
    #expect(DictionaryRule(from: "ahmadinezad", to: "Ahmadínežád").problem == nil)
}

@Test func rejectsRulesThatChangeLetters() {
    #expect(DictionaryRule(from: "teda", to: "tedy").problem == .differsBeyondDiacritics)
    #expect(DictionaryRule(from: "google docs", to: "google došč").problem == .differsBeyondDiacritics)
}

@Test func rejectsEmptyAndMultilineRules() {
    #expect(DictionaryRule(from: "  ", to: "  ").problem == .empty)
    #expect(DictionaryRule(from: "a\nb", to: "a\nb").problem == .multiline)
}

@Test func trimsEdgesButKeepsInnerSpaces() {
    #expect(DictionaryRule(from: "  google docs ", to: "google docs").from == "google docs")
}

@Test func normalizesRulesToNFC() {
    let rule = DictionaryRule(from: "s\u{030C}kola", to: "s\u{030C}kola")
    #expect(rule.from.unicodeScalars.count == 5)
    #expect(rule.from == "škola")
}

@Test func singleWordMeansNoWhitespace() {
    #expect(DictionaryRule(from: "rad", to: "rád").isSingleWord)
    #expect(!DictionaryRule(from: "chce byt", to: "chce být").isSingleWord)
}

@Test func validateRejectsAnInvalidAndADuplicateRule() {
    var config = Config.builtIn
    config.dictionary = [DictionaryRule(from: "teda", to: "tedy")]
    #expect(throws: ConfigError.invalidDictionaryRule(from: "teda", problem: .differsBeyondDiacritics)) {
        try config.validate()
    }
    config.dictionary = [DictionaryRule(from: "rad", to: "rád"), DictionaryRule(from: "Rad", to: "řad")]
    #expect(throws: ConfigError.duplicateDictionaryRule(from: "Rad")) { try config.validate() }
}

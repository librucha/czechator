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

// MARK: - Applying

private let dict = PersonalDictionary(rules: [
    DictionaryRule(from: "google docs", to: "google docs"),
    DictionaryRule(from: "docs", to: "docs"),
    DictionaryRule(from: "Ahmadinezad", to: "Ahmadínežád"),
    DictionaryRule(from: "rad", to: "rád"),
])

@Test func protectsAnEnglishTermFromAddedDiacritics() {
    #expect(
        dict.apply(to: "otevri google dočš", source: "otevri google docs").text
            == "otevri google docs")
}

@Test func correctsANameAndKeepsTheOutputsCase() {
    #expect(dict.apply(to: "AHMADINEZAD rekl", source: "AHMADINEZAD rekl").text == "AHMADÍNEŽÁD rekl")
    #expect(dict.apply(to: "ahmadinezad", source: "ahmadinezad").text == "ahmadínežád")
}

@Test func matchesOnlyWholeWords() {
    #expect(dict.apply(to: "docsy a mydocs", source: "docsy a mydocs").applied.isEmpty)
}

@Test func matchesNextToPunctuationAndSegmentEdges() {
    #expect(dict.apply(to: "(dočš), rad", source: "(docs), rad").text == "(docs), rád")
}

@Test func longerRuleWinsAndIsNotRematched() {
    let out = dict.apply(to: "google dočš", source: "google docs")
    #expect(out.applied.map(\.rule.from) == ["google docs"])
    #expect(out.applied.first?.range == 0..<11)
}

@Test func aSpaceInTheRuleMatchesANonBreakingSpace() {
    #expect(
        dict.apply(to: "google\u{00A0}dočš", source: "google\u{00A0}docs").text
            == "google\u{00A0}docs")
}

@Test func neverOverwritesDiacriticsTheUserTyped() {
    #expect(dict.apply(to: "řad", source: "řad").text == "řad")
    #expect(dict.apply(to: "Dočš", source: "Dočš").text == "Dočš")
}

@Test func tolerantOutputIsAlignedBeforeTheInputCheck() {
    // "google" has an inserted letter with no input position, so the longer
    // rule is unusable and the shorter one still applies.
    #expect(dict.apply(to: "google dočš", source: "gogle docs").text == "google docs")
    // Past DiacriticVerifier.toleranceLimit there is no alignment: leave it alone.
    let long = String(repeating: "a", count: 2_100)
    #expect(dict.apply(to: long + "  dočš", source: long + " docs").applied.isEmpty)
}

@Test func aCaseMappingThatChangesLengthDoesNotCrash() {
    // "ß".uppercased() is "SS": two characters cannot replace one.
    let german = PersonalDictionary(rules: [DictionaryRule(from: "Straße", to: "Straße")])
    #expect(german.apply(to: "STRAẞE", source: "STRAẞE").text.count == 6)
}

@Test func anEmptyDictionaryChangesNothing() {
    let out = PersonalDictionary.empty.apply(to: "google dočš", source: "google docs")
    #expect(out.text == "google dočš" && out.applied.isEmpty)
}

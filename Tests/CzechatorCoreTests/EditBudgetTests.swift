import Foundation
import Testing

@testable import CzechatorCore

@Test func budgetFloorsShortWordsToTheMinimum() {
    // 20 % of a 3-letter word floors to 0, so the minimum is what actually
    // carries short words — and Czech is full of them.
    let budget = EditBudget.builtIn
    #expect(budget.allowance(forWordOfLength: 3) == 1)
    #expect(budget.allowance(forWordOfLength: 5) == 1)
    #expect(budget.allowance(forWordOfLength: 8) == 1)
    #expect(budget.allowance(forWordOfLength: 10) == 2)
    #expect(budget.allowance(forWordOfLength: 20) == 4)
}

@Test func budgetDefaultsAreTightNotGenerous() {
    #expect(EditBudget.builtIn.percent == 20)
    #expect(EditBudget.builtIn.minimum == 1)
}

@Test func budgetClampsValuesFromTheFile() throws {
    let tooLarge = try JSONDecoder().decode(
        EditBudget.self, from: Data(#"{"percent":500,"minimum":99}"#.utf8))
    #expect(tooLarge.percent == 100)
    #expect(tooLarge.minimum == 5)

    let negative = try JSONDecoder().decode(
        EditBudget.self, from: Data(#"{"percent":-1,"minimum":-1}"#.utf8))
    #expect(negative.percent == 0)
    #expect(negative.minimum == 0)
}

@Test func budgetFillsMissingKeysFromDefaults() throws {
    let partial = try JSONDecoder().decode(EditBudget.self, from: Data(#"{"percent":40}"#.utf8))
    #expect(partial.percent == 40)
    #expect(partial.minimum == 1)
}

@Test func budgetClampsValuesConstructedInCode() {
    // `didSet` does not fire during initialisation, so the memberwise init has
    // to clamp on its own — this is the test that proves it does.
    let budget = EditBudget(percent: 500, minimum: 99)
    #expect(budget.percent == 100)
    #expect(budget.minimum == 5)
}

@Test func budgetClampsOnEveryWrite() {
    // The settings window binds straight to these, and a range enforced in one
    // place only is a range that holds until someone finds the other way in.
    var budget = EditBudget.builtIn
    budget.percent = 500
    budget.minimum = -3
    #expect(budget.percent == 100)
    #expect(budget.minimum == 0)
}

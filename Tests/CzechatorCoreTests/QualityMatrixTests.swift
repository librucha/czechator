import Foundation
import Testing

@testable import CzechatorCore

private func testProfile(
    name: String, model: String = "qwen3:4b-instruct",
    budget: EditBudget = EditBudget(percent: 35, minimum: 2)
) -> QualityProfile {
    QualityProfile(
        name: name,
        profile: Profile(
            kind: .ollama,
            endpoint: URL(string: "https://ai.interni.firma.cz/v1")!,
            model: model,
            temperature: 0,
            timeoutSeconds: 30,
            editBudget: budget))
}

@Test func qualityMatrixBudgetIsNilExactlyInStrictMode() {
    let budget = EditBudget(percent: 35, minimum: 2)
    let cells = QualityMatrix.cells(
        profiles: [testProfile(name: "local", budget: budget)],
        modes: CorrectionMode.allCases)

    for cell in cells {
        // The budget is forced to zero in strict mode, so a number there would
        // be a published claim about a limit that never applied.
        #expect(cell.budget == (cell.corrections == .strict ? nil : budget))
    }
}

@Test func qualityMatrixExpandsAllCorrectionsIntoThreeCells() {
    let modes = CorrectionMode.expand(["all"])
    let cells = QualityMatrix.cells(profiles: [testProfile(name: "local")], modes: modes ?? [])

    #expect(cells.count == 3)
    #expect(cells.map(\.corrections) == [.strict, .minorFixes, .proofread])
}

@Test func qualityMatrixCrossesTwoProfilesWithTwoModes() {
    let cells = QualityMatrix.cells(
        profiles: [testProfile(name: "local"), testProfile(name: "claude", model: "sonnet")],
        modes: [.strict, .proofread])

    #expect(cells.count == 4)
    // Profile-major, in the order asked for: the table rows keep that order.
    #expect(cells.map(\.profileName) == ["local", "local", "claude", "claude"])
    #expect(cells.map(\.corrections) == [.strict, .proofread, .strict, .proofread])
    #expect(cells.map(\.model) == ["qwen3:4b-instruct", "qwen3:4b-instruct", "sonnet", "sonnet"])
}

@Test func qualityMatrixInvocationCarriesNoPath() {
    let invocation = QualityMatrix.invocation(
        profiles: ["local"], modes: [.proofread], model: nil,
        fixturesDir: "/Users/nekdo/Documents/moje-vzorky", letterCase: .preserve)

    // This string ends up in a committed table: no `--config`, and no option
    // carrying a path that holds the user's home directory.
    #expect(!invocation.contains("--config"))
    #expect(!invocation.contains("/Users/nekdo"))
    #expect(!invocation.contains("/"))
    #expect(invocation.contains("--fixtures-dir moje-vzorky"))
}

@Test func qualityMatrixInvocationKeepsTheFixturesDirBasenameWithATrailingSlash() {
    let invocation = QualityMatrix.invocation(
        profiles: ["local"], modes: [.strict], model: "gemma3:4b",
        fixturesDir: "/Users/nekdo/moje-vzorky/", letterCase: .segmentStart)

    #expect(
        invocation == "czechator quality --profile local --corrections strict "
            + "--model gemma3:4b --fixtures-dir moje-vzorky --letter-case segmentStart")
}

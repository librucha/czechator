import Testing

@testable import CzechatorCore

@Test func wordBudgetAcceptsTheKnownSmallFixes() {
    let budget = EditBudget.builtIn
    #expect(
        WordBudget.withinBudget(
            original: "kdy zjsem sel", correction: "když jsem šel", budget: budget))
    #expect(WordBudget.withinBudget(original: "kndeliky", correction: "knedlíky", budget: budget))
    #expect(WordBudget.withinBudget(original: "bil", correction: "byl", budget: budget))
    #expect(
        WordBudget.withinBudget(
            original: "myslim ze ano", correction: "myslím, že ano", budget: budget))
}

@Test func wordBudgetRefusesAReplacedWord() {
    // The failure this whole project exists for: gemma3 turned "v úterý" into
    // "ve středu" and moved a meeting. "utery" -> "stredu" is far outside the
    // allowance for a five-letter word.
    #expect(
        !WordBudget.withinBudget(
            original: "schuzka se kona v utery",
            correction: "schůzka se koná ve středu",
            budget: .builtIn))
}

@Test func wordBudgetIgnoresCaseAndRepeatedSpaces() {
    // Neither of these spends any budget: normalisation makes them equal
    // before the alignment is ever computed.
    #expect(
        WordBudget.withinBudget(
            original: "posilam  vam podklady", correction: "Posílám vám podklady",
            budget: .builtIn))
}

@Test func wordBudgetNormalizationDoesNotGlueWordsTogether() {
    // Stripping whitespace instead of collapsing it would make these two
    // equal, and a model that swallowed a space would pass unnoticed. The
    // budget is what covers a moved space — not the normalisation.
    #expect(WordBudget.normalize("ahoj svete") != WordBudget.normalize("ahojsvete"))
}

@Test func wordBudgetChargesAMovedSpaceToTheWordBeforeIt() {
    // With a budget of zero the transposition in "kdy zjsem" has nowhere to go.
    #expect(
        !WordBudget.withinBudget(
            original: "kdy zjsem", correction: "kdyz jsem",
            budget: EditBudget(percent: 0, minimum: 0)))
}

@Test func wordBudgetRefusesWhenTheSegmentIsTooLongToAlign() {
    let long = String(repeating: "a", count: 2_001)
    #expect(!WordBudget.withinBudget(original: long, correction: long + "b", budget: .builtIn))
}

@Test func wordBudgetAcceptsAnIdenticalPair() {
    #expect(WordBudget.withinBudget(original: "ahoj", correction: "ahoj", budget: .builtIn))
    #expect(WordBudget.withinBudget(original: "", correction: "", budget: .builtIn))
}

@Test func wordBudgetNamesTheWordThatOverspent() {
    let over = WordBudget.overspentWords(
        original: "schuzka se kona v utery",
        correction: "schůzka se koná ve středu",
        budget: .builtIn)
    #expect(over.contains { $0.word == "utery" })
    #expect(over.first { $0.word == "utery" }?.allowance == 1)
}

@Test func wordBudgetRefusesTextAddedToAWhitespaceOnlySegment() {
    // No words means no allowance to charge the edits against, so the budget
    // has nothing to say — and silence must not read as approval.
    #expect(!WordBudget.withinBudget(original: "   ", correction: "ahoj", budget: .builtIn))
    #expect(WordBudget.withinBudget(original: "   ", correction: "  ", budget: .builtIn))
}

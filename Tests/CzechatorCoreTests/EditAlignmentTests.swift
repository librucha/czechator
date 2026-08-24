import Testing

@testable import CzechatorCore

@Test func alignmentCountsATranspositionAsOneEdit() {
    // Two swapped letters are the commonest typo there is. Plain Levenshtein
    // scores it 2, which would put it outside a budget of 1 — this single
    // expectation is the whole reason the metric is Damerau.
    #expect(EditAlignment.compute(Array("kndeliky"), Array("knedliky"))?.distance == 1)
}

@Test func alignmentScoresTheKnownExamples() {
    #expect(EditAlignment.compute(Array("bil"), Array("byl"))?.distance == 1)
    #expect(EditAlignment.compute(Array("kdy zjsem"), Array("kdyz jsem"))?.distance == 1)
    #expect(EditAlignment.compute(Array("myslim ze"), Array("myslim, ze"))?.distance == 1)
}

@Test func alignmentMapsEveryIndexWhenNothingChanged() {
    let alignment = EditAlignment.compute(Array("ahoj"), Array("ahoj"))
    #expect(alignment?.distance == 0)
    #expect(alignment?.map == [0: 0, 1: 1, 2: 2, 3: 3])
    #expect(alignment?.editPositions.isEmpty == true)
}

@Test func alignmentShiftsIndicesAfterAnInsertion() {
    // "ab" -> "axb": the 'b' moved from index 1 to index 2. This is exactly
    // what a non-breaking space needs in order to survive a typo fix.
    let alignment = EditAlignment.compute(Array("ab"), Array("axb"))
    #expect(alignment?.map[0] == 0)
    #expect(alignment?.map[1] == 2)
}

@Test func alignmentOmitsADeletedIndex() {
    // "axb" -> "ab": the 'x' at index 1 has nowhere to go, and a caller
    // holding a protected position there must reject the segment.
    let alignment = EditAlignment.compute(Array("axb"), Array("ab"))
    #expect(alignment?.map[1] == nil)
    #expect(alignment?.map[2] == 1)
}

@Test func alignmentAttributesAnInsertionToTheGraphemeItFollows() {
    // The comma is inserted after the 'm' of "myslim", so the cost lands on
    // that word rather than on the next one.
    #expect(EditAlignment.compute(Array("myslim ze"), Array("myslim, ze"))?.editPositions == [5])
}

@Test func alignmentAttributesATranspositionToItsFirstGrapheme() {
    #expect(EditAlignment.compute(Array("kdy zjsem"), Array("kdyz jsem"))?.editPositions == [3])
}

@Test func alignmentRefusesOversizedInput() {
    // O(n*m) is not worth running on a paragraph this size; callers fall back
    // to a strict comparison.
    let long = Array(String(repeating: "a", count: 2_001))
    #expect(EditAlignment.compute(long, long) == nil)
}

@Test func alignmentHandlesEmptySides() {
    #expect(EditAlignment.compute([], [])?.distance == 0)
    #expect(EditAlignment.compute(Array("abc"), [])?.distance == 3)
    #expect(EditAlignment.compute([], Array("abc"))?.distance == 3)
}

import Testing

@testable import CzechatorCore

@Test func alignedRestoreKeepsANonBreakingSpaceAcrossALengthChange() {
    // "v\u{00A0}utery" masked to "v utery"; the model fixes the typo and adds a
    // letter, so the NBSP is no longer at index 1. Without the alignment it
    // would be silently dropped — which is exactly what used to happen.
    let mask = FragileWhitespace.mask("v\u{00A0}utery")
    #expect(mask.masked == "v utery")

    let corrected = "ve utery"
    let alignment = EditAlignment.compute(Array(mask.masked), Array(corrected))
    let restored = mask.restore(into: corrected, alignment: alignment)
    #expect(restored == "ve\u{00A0}utery")
}

@Test func alignedRestoreRefusesWhenTheMaskedSlotWasDeleted() {
    let mask = FragileWhitespace.mask("a\u{00A0}b")
    let corrected = "ab"
    let alignment = EditAlignment.compute(Array(mask.masked), Array(corrected))
    #expect(mask.restore(into: corrected, alignment: alignment) == nil)
}

@Test func alignedRestoreWithoutAnAlignmentKeepsTheStrictPath() {
    let mask = FragileWhitespace.mask("v\u{00A0}utery")
    #expect(mask.restore(into: "v útery", alignment: nil) == "v\u{00A0}útery")
    // A length change with no alignment is a rejection, not a silent drop.
    #expect(mask.restore(into: "ve utery", alignment: nil) == nil)
}

@Test func alignedEscapeKeepsAnEntityAcrossALengthChange() {
    // "a &amp; b" -> unescaped "a & b". The model inserts a letter before the
    // ampersand, so the entity must move with it.
    let style = MarkupEntityStyle.detect(in: "a &amp; b", table: MarkupEntities.htmlTable)
    let alignment = EditAlignment.compute(Array("a & b"), Array("ax & b"))
    #expect(MarkupEntities.escape("ax & b", style: style, alignment: alignment) == "ax &amp; b")
}

@Test func alignedEscapeRefusesWhenTheEntitySlotWasDeleted() {
    let style = MarkupEntityStyle.detect(in: "a &amp; b", table: MarkupEntities.htmlTable)
    let alignment = EditAlignment.compute(Array("a & b"), Array("a  b"))
    #expect(MarkupEntities.escape("a  b", style: style, alignment: alignment) == nil)
}

@Test func alignedJSONEscapeKeepsAnEscapeAcrossALengthChange() {
    let style = JSONEscapeStyle.detect(in: #"a\nb"#)
    let alignment = EditAlignment.compute(Array("a\nb"), Array("ax\nb"))
    #expect(JSONEscaping.escape("ax\nb", style: style, alignment: alignment) == #"ax\nb"#)
}

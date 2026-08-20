import Foundation
import Testing

@testable import CzechatorCore

private let baseOptions = MarkupScanOptions(
    skipElements: [],
    skipComments: true,
    skipProcessingInstructions: true,
    skipCDATA: false,
    includeAttributeValues: false,
    voidElements: []
)

private func texts(_ input: String, _ options: MarkupScanOptions = baseOptions) -> [String] {
    MarkupScanner.scan(input, options: options).map { String(input[$0.range]) }
}

@Test func extractsTextNodesOnly() {
    #expect(texts("<p>ahoj svete</p>") == ["ahoj svete"])
}

@Test func neverReturnsTagsOrAttributes() {
    let input = #"<div class="velky" id="x">obsah</div>"#
    #expect(texts(input) == ["obsah"])
}

@Test func tracksElementPath() {
    let input = "<a><b>hluboko</b></a>"
    let nodes = MarkupScanner.scan(input, options: baseOptions)
    #expect(nodes.count == 1)
    #expect(nodes[0].elementPath == ["a", "b"])
}

@Test func skipsConfiguredElements() {
    var options = baseOptions
    options.skipElements = ["script", "style"]
    let input = "<p>viditelne</p><script>var x = 'skryte';</script>"
    #expect(texts(input, options) == ["viditelne"])
}

@Test func skipsCommentsAndProcessingInstructions() {
    let input = "<?xml version=\"1.0\"?><!-- poznamka --><r>obsah</r>"
    #expect(texts(input) == ["obsah"])
}

@Test func includesCDATAWhenNotSkipped() {
    #expect(texts("<r><![CDATA[uvnitr cdata]]></r>") == ["uvnitr cdata"])
}

@Test func skipsCDATAWhenConfigured() {
    var options = baseOptions
    options.skipCDATA = true
    #expect(texts("<r><![CDATA[uvnitr cdata]]></r>", options).isEmpty)
}

@Test func handlesSelfClosingAndVoidElements() {
    var options = baseOptions
    options.voidElements = MarkupScanOptions.htmlVoidElements
    let input = "<p>pred<br>po</p><img src=\"a.png\"/><p>dalsi</p>"
    let nodes = MarkupScanner.scan(input, options: options)
    #expect(nodes.map { String(input[$0.range]) } == ["pred", "po", "dalsi"])
    #expect(nodes.allSatisfy { $0.elementPath == ["p"] })
}

@Test func returnsAttributeValuesWhenRequested() {
    var options = baseOptions
    options.includeAttributeValues = true
    let input = #"<img alt="popis obrazku">"#
    let nodes = MarkupScanner.scan(input, options: options)
    #expect(nodes.map { String(input[$0.range]) } == ["popis obrazku"])
    #expect(nodes[0].isAttributeValue)
}

@Test func returnsCommentBodyWhenCommentsAreNotSkipped() {
    var options = baseOptions
    options.skipComments = false
    #expect(
        texts("<r><!-- poznamka v textu -->obsah</r>", options)
            == [" poznamka v textu ", "obsah"])
}

@Test func returnsProcessingInstructionBodyWhenNotSkipped() {
    var options = baseOptions
    options.skipProcessingInstructions = false
    #expect(
        texts("<?nejaka instrukce?><r>obsah</r>", options)
            == ["nejaka instrukce", "obsah"])
}

@Test func keepsWholeBodyOfUnterminatedCDATA() {
    // Subtracting the terminator's length would eat the last three characters.
    #expect(texts("<r><![CDATA[abcdef") == ["abcdef"])
}

@Test func keepsWholeBodyOfUnterminatedComment() {
    var options = baseOptions
    options.skipComments = false
    #expect(texts("<r><!-- abcdef", options) == [" abcdef"])
}

@Test func skipsWholeSubtreeOfSkippedElement() {
    var options = baseOptions
    options.skipElements = ["script"]
    #expect(texts("<p>viditelne</p><script><b>skryte</b></script>", options) == ["viditelne"])
}

@Test func doctypeIsNeverReturnedAsText() {
    #expect(texts("<!DOCTYPE html><p>obsah</p>") == ["obsah"])
}

@Test func detectsMarkupHeuristically() {
    #expect(MarkupScanner.looksLikeMarkup("<p>ahoj</p>"))
    #expect(MarkupScanner.looksLikeMarkup("<?xml version=\"1.0\"?><r/>"))
    #expect(!MarkupScanner.looksLikeMarkup("2 < 3 a 5 > 4"))
    #expect(!MarkupScanner.looksLikeMarkup("obycejny text"))
}

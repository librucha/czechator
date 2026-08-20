import Foundation
import Testing

@testable import CzechatorCore

private func htmlHandler() throws -> HTMLHandler { try HTMLHandler(rules: .builtIn) }

@Test func skipsScriptStyleAndCode() throws {
    let text =
        "<p>viditelne</p><script>var a='x';</script><style>p{color:red}</style><code>let x</code>"
    #expect(try htmlHandler().segments(in: text).map(\.text) == ["viditelne"])
}

@Test func handlesVoidElementsWithoutBreakingTheStack() throws {
    let text = "<p>pred<br>po</p><p>dalsi</p>"
    #expect(try htmlHandler().segments(in: text).map(\.text) == ["pred", "po", "dalsi"])
}

@Test func unescapesHTMLEntitiesForTheModel() throws {
    let text = "<p>ahoj&nbsp;svete&hellip;</p>"
    #expect(try htmlHandler().segments(in: text).map(\.text) == ["ahoj\u{00A0}svete…"])
}

@Test func htmlSpliceWithRawReproducesOriginalExactly() throws {
    let text = """
        <div class="a"><p>prvni &amp; text</p><br><ul><li>polozka</li></ul>
        <script>var x = 1;</script><p>posledni&nbsp;text</p></div>
        """
    let segments = try htmlHandler().segments(in: text)
    let rebuilt = try Reassembler.splice(
        text, segments: segments, replacements: segments.map(\.raw))
    #expect(rebuilt == text)
}

@Test func correctingTextLeavesTagsAndAttributesUntouched() throws {
    let text = #"<p class="velky">prilis zlutoucky kun</p>"#
    let handler = try htmlHandler()
    let segments = try handler.segments(in: text)
    let rebuilt = try Reassembler.splice(
        text, segments: segments,
        replacements: segments.map { handler.escape("příliš žluťoučký kůň", like: $0) })
    #expect(rebuilt == #"<p class="velky">příliš žluťoučký kůň</p>"#)
}

@Test func htmlConfidenceFavoursDeclaredHTML() {
    #expect(
        HTMLHandler.confidence(for: ClipboardInput(text: "<p>x</p>", uti: "public.html")) == 1.0)
    #expect(HTMLHandler.confidence(for: ClipboardInput(text: "<div>x</div>")) == 0.75)
    #expect(HTMLHandler.confidence(for: ClipboardInput(text: "<r><a>x</a></r>")) == 0)
    #expect(HTMLHandler.id == "html")
}

@Test func htmlWinsForFragmentsWithoutTheObviousMarkers() {
    #expect(HTMLHandler.confidence(for: ClipboardInput(text: "<h1>nadpis</h1>")) == 0.75)
    #expect(HTMLHandler.confidence(for: ClipboardInput(text: "<em>text</em>")) == 0.75)
    #expect(HTMLHandler.confidence(for: ClipboardInput(text: "<img src=\"x\">")) == 0.75)
    #expect(
        HTMLHandler.confidence(for: ClipboardInput(text: "<script>var x = 1;</script>")) == 0.75)
    #expect(HTMLHandler.confidence(for: ClipboardInput(text: "<!DOCTYPE html><foo/>")) == 0.95)
}

@Test func proseMentioningATagIsNotMistakenForHTML() {
    let prose = "Pouzij znacku <br pro zalomeni v HTML dokumentu, jinak to nefunguje."
    #expect(HTMLHandler.confidence(for: ClipboardInput(text: prose)) == 0)
}

@Test func genericXMLDoesNotGetStolenByHTML() {
    #expect(HTMLHandler.confidence(for: ClipboardInput(text: "<r><a>x</a></r>")) == 0)
    #expect(HTMLHandler.confidence(for: ClipboardInput(text: "<kniha><b>x</b></kniha>")) == 0)
}

import Foundation
import Testing

@testable import CzechatorCore

private func xmlHandler() throws -> XMLHandler { try XMLHandler(rules: .builtIn) }

@Test func unescapesNamedAndNumericEntities() {
    let input = "a &lt; b &amp; c &#160;konec"[...]
    #expect(
        MarkupEntities.unescape(input, table: MarkupEntities.xmlTable)
            == "a < b & c \u{00A0}konec")
}

@Test func escapeReproducesTheSourceSpelling() {
    let raw = "a &lt; b &amp; c &#160;konec"
    let style = MarkupEntityStyle.detect(in: raw, table: MarkupEntities.xmlTable)
    let round = MarkupEntities.escape(
        MarkupEntities.unescape(raw[...], table: MarkupEntities.xmlTable), style: style)
    #expect(round == raw)
}

@Test func escapeLeavesUnEscapedCharactersAlone() {
    let style = MarkupEntityStyle.detect(in: "bez entit", table: MarkupEntities.xmlTable)
    #expect(MarkupEntities.escape("a > b", style: style) == "a > b")
}

@Test func unescapeLeavesUnknownEntitiesUntouched() {
    let input = "sleva 50 &procent; a &; prazdna"[...]
    #expect(
        MarkupEntities.unescape(input, table: MarkupEntities.xmlTable)
            == "sleva 50 &procent; a &; prazdna")
}

@Test func segmentsOnlyTextNodes() throws {
    let text =
        "<?xml version=\"1.0\"?><r><a id=\"x\">prvni text</a><!-- pozn --><b>druhy text</b></r>"
    #expect(try xmlHandler().segments(in: text).map(\.text) == ["prvni text", "druhy text"])
}

@Test func xmlSpliceWithRawReproducesOriginalExactly() throws {
    let text = """
        <?xml version="1.0" encoding="UTF-8"?>
        <root>
          <polozka id="1">prvni text s &amp; entitou</polozka>
          <!-- komentar -->
          <polozka id="2"><![CDATA[cdata text]]></polozka>
          <prazdna/>
        </root>
        """
    let segments = try xmlHandler().segments(in: text)
    let rebuilt = try Reassembler.splice(
        text, segments: segments, replacements: segments.map(\.raw))
    #expect(rebuilt == text)
}

@Test func correctingTextLeavesMarkupUntouched() throws {
    let text = "<r><a>prilis zlutoucky kun</a></r>"
    let handler = try xmlHandler()
    let segments = try handler.segments(in: text)
    let rebuilt = try Reassembler.splice(
        text, segments: segments,
        replacements: segments.map { handler.escape("příliš žluťoučký kůň", like: $0) })
    #expect(rebuilt == "<r><a>příliš žluťoučký kůň</a></r>")
}

@Test func xmlConfidenceFavoursDeclaredXML() {
    #expect(XMLHandler.confidence(for: ClipboardInput(text: "<?xml version=\"1.0\"?><r/>")) == 0.95)
    #expect(XMLHandler.confidence(for: ClipboardInput(text: "<r><a>x</a></r>")) == 0.6)
    #expect(XMLHandler.confidence(for: ClipboardInput(text: "2 < 3")) == 0)
    #expect(XMLHandler.id == "xml")
}

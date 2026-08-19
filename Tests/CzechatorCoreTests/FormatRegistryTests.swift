import Foundation
import Testing

@testable import CzechatorCore

private func registry() throws -> FormatRegistry { try FormatRegistry(rules: .builtIn) }

@Test func picksJSONForParsableJSON() throws {
    #expect(try registry().select(ClipboardInput(text: #"{"a": "b"}"#)).id == "json")
}

@Test func picksHTMLForDeclaredHTMLUTI() throws {
    let input = ClipboardInput(text: "<p>x</p>", uti: "public.html", plainText: "x")
    #expect(try registry().select(input).id == "html")
}

@Test func picksXMLForDeclaredXMLDocument() throws {
    #expect(
        try registry().select(ClipboardInput(text: "<?xml version=\"1.0\"?><r>x</r>")).id == "xml")
}

@Test func fallsBackToPlainText() throws {
    #expect(try registry().select(ClipboardInput(text: "obycejny text")).id == "plain")
}

@Test func fallsBackToPlainTextForInvalidJSON() throws {
    #expect(try registry().select(ClipboardInput(text: #"{"a": undefined}"#)).id == "plain")
}

@Test func exposesHandlersByIdentifier() throws {
    let registry = try registry()
    #expect(registry.availableIDs == ["json", "html", "xml", "plain"])
    #expect(registry.handler(id: "json") != nil)
    #expect(registry.handler(id: "neexistuje") == nil)
}

@Test func flagsStructureThatNoHandlerCouldParse() throws {
    let registry = try registry()
    // JSONC, trailing comma, NDJSON and a truncated fragment all fall to the
    // plain handler, where their keys would be corrected as if they were prose.
    let structured = [
        "{\n  // poznamka\n  \"nazev\": \"Prilis kun\"\n}",
        #"{"prijmeni": "Novak", "mesto": "Ceske Budejovice", }"#,
        #"{"a": 1}"# + "\n" + #"{"b": 2}"#,
        #"{"nazev": "Prilis kun"#,
    ]
    for text in structured {
        #expect(
            registry.looksStructuredButUnclaimed(ClipboardInput(text: text)),
            "nezachyceno: \(text)")
    }
}

@Test func doesNotFlagOrdinaryProseOrValidStructure() throws {
    let registry = try registry()
    #expect(!registry.looksStructuredButUnclaimed(ClipboardInput(text: "obycejny text")))
    #expect(!registry.looksStructuredButUnclaimed(ClipboardInput(text: #"{"a": "b"}"#)))
    #expect(!registry.looksStructuredButUnclaimed(ClipboardInput(text: "<p>ahoj</p>")))
    #expect(
        !registry.looksStructuredButUnclaimed(
            ClipboardInput(text: "<?xml version=\"1.0\"?><r>x</r>")))
}

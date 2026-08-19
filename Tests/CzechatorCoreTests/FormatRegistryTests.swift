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

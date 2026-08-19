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

@Test func flagsStructureWhoseBraceIsNotFirst() throws {
    // A leading comment pushes the brace off the front; the earlier
    // first-character check missed exactly this and renamed the keys.
    let jsonc = "// konfigurace aplikace\n{\n  \"slozka_projektu\": \"data\"\n}"
    #expect(try registry().looksStructuredButUnclaimed(ClipboardInput(text: jsonc)))
}

@Test func doesNotRefuseProseThatMerelyStartsWithABracket() throws {
    let registry = try registry()
    let prose = [
        "[Klikni sem](https://priklad.cz) pro vice informaci.",
        "[1] Novak, Jan. Ceske dejiny v kostce. Praha, 2020.",
        "<3 mam te rad, moje mila.",
        "{{jmeno}}, vitejte v aplikaci.",
        "{ x | x > 0 } je mnozina kladnych cisel.",
    ]
    for text in prose {
        #expect(
            !registry.looksStructuredButUnclaimed(ClipboardInput(text: text)),
            "zbytecne odmitnuto: \(text)")
    }
}

@Test func refusesConfigFormatsItCannotParse() throws {
    let registry = try registry()
    let configs = [
        "# konfigurace\nslozka_projektu = \"Ulozeni dat\"\nprijmeni = \"Novak\"",
        "[Obecne]\nnazev = Aplikace\n[Sit_pripojeni]\nport = 8080",
        "[[polozky]]\nnazev = \"Prvni\"",
        "seznam:\n  - jmeno: Petr\n  - jmeno: Jana",
        "\"muj klic\" = \"hodnota\"\n\"dalsi nazev\" = \"jina\"",
        "nazev.aplikace: Ulozeni\nuzivatelske.jmeno: petr",
    ]
    for text in configs {
        #expect(registry.looksStructuredButUnclaimed(ClipboardInput(text: text)),
                "neodmitnuto: \(text)")
    }
}

@Test func doesNotRefuseProseWithLabelsOrColons() throws {
    let registry = try registry()
    let prose = [
        "Poznamka: schuzka je v pondeli.",
        "Datum: dvanacteho ledna. Misto: velka zasedacka.",
        "Kniha \"Osud\": recenze vysla vcera v novinach.",
        "Sraz je v 10:30 pred budovou.",
        "Vysledek zapasu byl 3:1 pro domaci.",
        "Petr: Ahoj, jak se mas?\nJana: Dobre, dekuji.",
        "[Klikni sem](https://priklad.cz) pro vice informaci.",
        "[1] Novak, Jan. Ceske dejiny v kostce. Praha, 2020.",
    ]
    for text in prose {
        #expect(!registry.looksStructuredButUnclaimed(ClipboardInput(text: text)),
                "zbytecne odmitnuto: \(text)")
    }
}

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
        // Values ending in a full stop: the shape of the key decides, not the
        // punctuation of the value.
        "nazev = Ulozeni dat.\nmesto = Praha.",
        "popis.aplikace = Sprava dokumentu.\nnazev.aplikace = Ulozeni",
        // A single line must be protected too.
        "nazev = \"Ulozeni dat\"",
        "# poznamka ke konfiguraci\nnazev = Ulozeni",
        // Nested YAML, where the parent line carries no value.
        "server:\n  nazev: hlavni\n  popis: Produkcni server.",
        "aplikace:\n  databaze:\n    nazev: hlavni\n    popis: Ulozeni dat.",
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
        "Datum: dvanacteho ledna\nMisto: velka zasedacka",
        "Kniha \"Osud\": recenze vysla vcera v novinach.",
        "Sraz je v 10:30 pred budovou.",
        "Vysledek zapasu byl 3:1 pro domaci.",
        "Petr: Ahoj, jak se mas?\nJana: Dobre, dekuji.",
        "[Klikni sem](https://priklad.cz) pro vice informaci.",
        "[1] Novak, Jan. Ceske dejiny v kostce. Praha, 2020.",
        // Capitalized labels are how Czech writes an address or a note.
        "Jmeno: Petr Novak\nUlice: Kratka 5\nMesto: Praha",
        "Datum: 12. ledna\nCas: 10:00\nMisto: zasedacka\nTema: rozpocet",
        "TODO: dokoncit zpravu\nTODO: poslat mail Jane",
        "Kontakt:\nTelefon: 123 456 789\nMesto: Praha",
    ]
    for text in prose {
        #expect(!registry.looksStructuredButUnclaimed(ClipboardInput(text: text)),
                "zbytecne odmitnuto: \(text)")
    }
}

@Test func refusesAYamlBlockWhoseKeyAppearsOnce() throws {
    let registry = try registry()
    let blocks = [
        "# seznam mest\nmesta:\n  - Praha\n  - Plzen",
        "prihlaseni:\n  - Petr\n  - Jana",
        "popis:\n  Aplikace slouzi ke sprave dokumentu",
    ]
    for text in blocks {
        #expect(registry.looksStructuredButUnclaimed(ClipboardInput(text: text)),
                "neodmitnuto: \(text)")
    }
}

@Test func doesNotRefuseSentencesWithEqualsOrAbbreviations() throws {
    let registry = try registry()
    let prose = [
        "Dobry den,\nposilam vam shrnuti jednani. Rozpocet = 500 tisic korun.\nS pozdravem",
        "Rovnice x = 5 nema reseni v prirozenych cislech.",
        "Vzorec pro obsah je S = a * b.",
        "pozn.: uvedene ceny jsou bez DPH",
        "c.j.: 123/2020",
        "v1.2: oprava chyb v exportu",
        "obr.1: schema zapojeni",
    ]
    for text in prose {
        #expect(!registry.looksStructuredButUnclaimed(ClipboardInput(text: text)),
                "zbytecne odmitnuto: \(text)")
    }
}

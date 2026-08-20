import Foundation
import Testing

@testable import CzechatorCore

@Test func foldsAllCzechLowercaseDiacritics() {
    #expect(
        DiacriticFolding.fold("příliš žluťoučký kůň úpěl ďábelské ódy")
            == "prilis zlutoucky kun upel dabelske ody")
}

@Test func foldsUppercaseDiacritics() {
    #expect(
        DiacriticFolding.fold("ČERVENÝ ŘEDKVIČKA ŽÍŽALA ÚŽASNÝ")
            == "CERVENY REDKVICKA ZIZALA UZASNY")
}

@Test func leavesNonCzechCharactersUntouched() {
    let input = "Grüße, señor — 42% {\"a\": 1}\n\ttab"
    #expect(DiacriticFolding.fold(input) == input)
}

@Test func handlesDecomposedInput() {
    // "s" followed by COMBINING CARON must fold like the precomposed "š"
    #expect(DiacriticFolding.fold("prili\u{0073}\u{030C}") == "prilis")
}

@Test func isIdentityOnTextWithoutDiacritics() {
    #expect(DiacriticFolding.fold("Prilis zlutoucky kun") == "Prilis zlutoucky kun")
}

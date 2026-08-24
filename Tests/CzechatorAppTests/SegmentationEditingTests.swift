import CzechatorCore
import Foundation
import Testing

@testable import CzechatorApp

private func loadedForm(_ mutate: (inout Config) -> Void = { _ in }) -> SettingsFormState {
    var config = Config.builtIn
    mutate(&config)
    var form = SettingsFormState()
    form.load(from: config)
    return form
}

// MARK: - Lists as text

@Test func everyListArrivesAsOneItemPerLine() {
    let form = loadedForm {
        $0.segmentation.common.skipPatterns = ["https?://\\S+", "\\S+@\\S+"]
        $0.segmentation.html.skipElements = ["script", "style"]
    }
    #expect(form.listText[.commonSkipPatterns] == "https?://\\S+\n\\S+@\\S+")
    #expect(form.listText[.htmlSkipElements] == "script\nstyle")
    for list in SettingsFormState.PatternList.allCases {
        #expect(form.listText[list] != nil, "\(list) has no text")
    }
}

@Test func blankLinesAndStrayWhitespaceDoNotBecomeEntries() {
    // An empty list must stay empty rather than becoming [""], which as a
    // regex matches everything and would skip the whole document.
    #expect(SettingsFormState.items(from: "") == [])
    #expect(SettingsFormState.items(from: "\n\n  \n") == [])
    #expect(SettingsFormState.items(from: "  script  \n\n style \n") == ["script", "style"])
}

@Test func aBlankLineBeingTypedSurvivesInTheField() {
    // The text is kept as typed. Folding it back through the array on every
    // keystroke would delete the empty line under the cursor.
    var form = loadedForm()
    form.listText[.htmlSkipElements] = "script\n\nstyle"
    #expect(form.listText[.htmlSkipElements] == "script\n\nstyle")
    #expect(form.resolvedConfig.segmentation.html.skipElements == ["script", "style"])
}

@Test func editingAListReachesTheConfigurationThatGetsSaved() {
    var form = loadedForm()
    form.listText[.jsonSkipValuesForKeys] = "id\nuuid\nslug"
    form.listText[.plainSkipPatterns] = "`[^`]+`"

    let resolved = form.resolvedConfig
    #expect(resolved.segmentation.json.skipValuesForKeys == ["id", "uuid", "slug"])
    #expect(resolved.segmentation.plain.skipPatterns == ["`[^`]+`"])
    // And nothing else moved.
    #expect(resolved.segmentation.common.minLength == Config.builtIn.segmentation.common.minLength)
    #expect(resolved.activeProfile == Config.builtIn.activeProfile)
}

@Test func theOtherSegmentationFieldsAreEditedDirectly() {
    var form = loadedForm()
    form.config.segmentation.common.minLength = 4
    form.config.segmentation.common.requireLetters = false
    form.config.segmentation.xml.skipCDATA = true

    let resolved = form.resolvedConfig
    #expect(resolved.segmentation.common.minLength == 4)
    #expect(resolved.segmentation.common.requireLetters == false)
    #expect(resolved.segmentation.xml.skipCDATA)
}

// MARK: - Patterns that will not compile

@Test func aBrokenPatternBlocksSavingAndSaysWhich() {
    // It would otherwise be written to the file and fail at the next
    // correction, far from the window that accepted it.
    var form = loadedForm()
    form.listText[.commonSkipPatterns] = "https?://\\S+\n[unclosed"

    let problem = form.patternProblem
    #expect(problem != nil)
    #expect(problem?.contains("[unclosed") == true)
    #expect(form.canSave == false)
}

@Test func aBrokenPatternInThePlainListIsCaughtToo() {
    var form = loadedForm()
    form.listText[.plainSkipPatterns] = "*"
    #expect(form.patternProblem != nil)
    #expect(form.canSave == false)
}

@Test func soundPatternsSaveWithoutComplaint() {
    var form = loadedForm()
    form.listText[.commonSkipPatterns] = "https?://\\S+\n\\S+@\\S+\\.\\S+"
    form.listText[.plainSkipPatterns] = "`[^`]+`\n^```[\\s\\S]*?^```"
    #expect(form.patternProblem == nil)
    #expect(form.canSave)
}

@Test func listsThatAreNotPatternsAreNotCompiled() {
    // Element and key names are matched literally, so a bracket in one is a
    // name with a bracket, not a broken pattern.
    var form = loadedForm()
    form.listText[.htmlSkipElements] = "[unclosed"
    form.listText[.jsonSkipValuesForKeys] = "*"
    #expect(form.patternProblem == nil)
    #expect(form.canSave)
}

@Test func patternsAreCheckedTheWayTheyWillBeUsed() {
    // The tool compiles them with anchorsMatchLines; a pattern accepted here
    // has to be one SegmentBuilder can build.
    var form = loadedForm()
    form.listText[.commonSkipPatterns] = "^```[\\s\\S]*?^```"
    #expect(form.patternProblem == nil)
    #expect(throws: Never.self) {
        try SegmentBuilder(
            common: form.resolvedConfig.segmentation.common,
            extraSkipPatterns: form.resolvedConfig.segmentation.plain.skipPatterns)
    }
}

@Test func reopeningTheWindowReloadsTheListsFromDisk() {
    var form = loadedForm()
    form.listText[.htmlSkipElements] = "nesmysl"
    form.load(from: .builtIn)
    #expect(
        form.listText[.htmlSkipElements]
            == SettingsFormState.text(from: Config.builtIn.segmentation.html.skipElements))
}

import Testing

@testable import CzechatorCore

@Test func promptDiffersForEveryMode() {
    let systems = CorrectionMode.allCases.map { PromptBuilder.system(for: $0) }
    #expect(Set(systems).count == CorrectionMode.allCases.count)
}

@Test func promptStrictStillForbidsFixingSpelling() {
    #expect(PromptBuilder.system(for: .strict).contains("mechanical transformer"))
    #expect(PromptBuilder.system(for: .strict) == PromptBuilder.defaultSystem)
}

@Test func promptTolerantModesAskForTheFixes() {
    // Loosening the verifier without loosening the prompt gains nothing: the
    // model would still refuse to fix anything and only more junk would pass.
    #expect(PromptBuilder.system(for: .minorFixes).contains("typing mistake"))
    #expect(PromptBuilder.system(for: .proofread).contains("proofreader"))
}

@Test func promptEveryModeForbidsSynonymsAndTranslation() {
    for mode in CorrectionMode.allCases {
        let system = PromptBuilder.system(for: mode)
        #expect(system.lowercased().contains("synonym") || system.contains("different word"))
        #expect(system.lowercased().contains("translat"))
    }
}

@Test func promptOverrideWinsOverEveryMode() {
    let prompt = PromptBuilder.build(items: ["ahoj"], mode: .proofread, systemOverride: "vlastní")
    #expect(prompt.system == "vlastní")
}

@Test func promptSystemIsStableAcrossCalls() {
    // Ollama caches the prefill for a stable prefix; a system message that
    // varies between calls throws that away on every batch.
    #expect(PromptBuilder.system(for: .minorFixes) == PromptBuilder.system(for: .minorFixes))
}

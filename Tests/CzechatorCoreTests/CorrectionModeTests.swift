import Foundation
import Testing

@testable import CzechatorCore

@Test func correctionOnlyStrictProvesNothingElseChanged() {
    #expect(!CorrectionMode.strict.isTolerant)
    #expect(CorrectionMode.minorFixes.isTolerant)
    #expect(CorrectionMode.proofread.isTolerant)
}

@Test func correctionModeRoundTripsThroughJSON() throws {
    for mode in CorrectionMode.allCases {
        let data = try JSONEncoder().encode(mode)
        #expect(try JSONDecoder().decode(CorrectionMode.self, from: data) == mode)
    }
}

@Test func correctionProfileWithoutTheNewKeysStaysStrict() throws {
    // The config file is materialized on first run, so every existing
    // installation has a profile block written before these keys existed.
    // Adding non-optional fields without a hand-written decoder would stop
    // every one of them from loading at all.
    let json = Data(
        #"""
        {"kind":"ollama","endpoint":"http://localhost:11434",
         "model":"qwen3:4b-instruct","temperature":0,"timeoutSeconds":30}
        """#.utf8)
    let profile = try JSONDecoder().decode(Profile.self, from: json)
    #expect(profile.corrections == .strict)
    #expect(profile.editBudget == EditBudget.builtIn)
    #expect(profile.verification)
}

@Test func correctionProfileReadsTheNewKeysWhenPresent() throws {
    let json = Data(
        #"""
        {"kind":"ollama","endpoint":"http://localhost:11434",
         "model":"qwen3:4b-instruct","temperature":0,"timeoutSeconds":30,
         "corrections":"minor-fixes","editBudget":{"percent":30,"minimum":2},
         "verification":false}
        """#.utf8)
    let profile = try JSONDecoder().decode(Profile.self, from: json)
    #expect(profile.corrections == .minorFixes)
    #expect(profile.editBudget.percent == 30)
    #expect(profile.editBudget.minimum == 2)
    #expect(!profile.verification)
}

@Test func correctionBuiltInProfilesAreAllStrict() {
    // A local 4b model in proofreading mode rewrites words silently. The
    // shipped defaults must not put anyone there without asking.
    for (_, profile) in Config.builtIn.profiles {
        #expect(profile.corrections == .strict)
        #expect(profile.verification)
    }
}

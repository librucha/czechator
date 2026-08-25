import Foundation
import Testing

@testable import CzechatorCore

/// The repository root, derived from this file rather than from the working
/// directory: a test run's cwd is not guaranteed by SwiftPM.
private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // Tests/CzechatorCoreTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // repository root

private func onDisk(_ directory: String) throws -> QualityFixtureSet {
    try QualityFixtures.load(
        directory: repositoryRoot.appendingPathComponent("Fixtures/\(directory)"))
}

@Test func qualityFixturesEmbeddedCleanSetMatchesTheFilesOnDisk() throws {
    // Whoever edits a fixture and forgets `make fixtures` gets a red test here
    // rather than a wrong number in a published table.
    let disk = try onDisk("quality")
    #expect(QualityFixtures.clean.samples == disk.samples)
}

@Test func qualityFixturesEmbeddedTyposSetMatchesTheFilesOnDisk() throws {
    let disk = try onDisk("typos")
    #expect(QualityFixtures.typos.samples == disk.samples)
}

@Test func qualityFixturesKeepCRLFExactly() throws {
    // One sample is CRLF on purpose. Any newline translation on the way into
    // the generated file would turn it into a permanent miss.
    let crlf = QualityFixtures.clean.samples.first { $0.name == "13-crlf" }
    #expect(crlf?.input.contains("\r\n") == true)
    #expect(crlf?.want.contains("\r\n") == true)
}

@Test func qualityFixturesLoadReadsAPairPerSample() throws {
    let set = try onDisk("typos")
    #expect(set.name == "typos")
    #expect(set.samples.count == 12)
    #expect(set.samples.map(\.name) == set.samples.map(\.name).sorted())
}

/// A directory that exists only for the duration of one test, with the files
/// it is given written into it.
private func temporaryFixtures(
    _ files: [String: String], _ body: (URL) throws -> Void
) throws {
    let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("czechator-fixtures-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    for (name, contents) in files {
        try contents.write(
            to: temporary.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    try body(temporary)
}

@Test func qualityFixturesLoadRefusesAnInputWithNoReference() throws {
    try temporaryFixtures(["lonely.in": "ahoj"]) { directory in
        #expect(throws: QualityFixtureError.missingReference(sample: "lonely")) {
            _ = try QualityFixtures.load(directory: directory)
        }
    }
}

@Test func qualityFixturesLoadRefusesAReferenceWithNoInput() throws {
    // A renamed `.in` leaves its `.want` behind. Skipping it would shrink the
    // denominator of a published fraction without admitting anything.
    try temporaryFixtures(
        ["01-ok.in": "ahoj", "01-ok.want": "ahoj", "07-carka.want": "ahoj, světe"]
    ) { directory in
        #expect(throws: QualityFixtureError.missingInput(sample: "07-carka")) {
            _ = try QualityFixtures.load(directory: directory)
        }
    }
}

@Test func qualityFixturesLoadRefusesADirectoryWithNoPair() throws {
    // Otherwise the run prints a table of zeroes and exits successfully — the
    // one outcome the command exists to prevent.
    try temporaryFixtures(["README.md": "# nic tu není"]) { directory in
        #expect(throws: QualityFixtureError.emptySet(path: directory.path)) {
            _ = try QualityFixtures.load(directory: directory)
        }
    }
}

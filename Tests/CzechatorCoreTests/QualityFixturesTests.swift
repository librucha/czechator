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

@Test func qualityFixturesLoadRefusesAnInputWithNoReference() throws {
    let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("czechator-fixtures-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    try "ahoj".write(
        to: temporary.appendingPathComponent("lonely.in"), atomically: true, encoding: .utf8)

    #expect(throws: QualityFixtureError.self) {
        _ = try QualityFixtures.load(directory: temporary)
    }
}

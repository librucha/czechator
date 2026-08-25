import Foundation

public struct QualitySample: Sendable, Equatable {
    public let name: String
    public let input: String
    public let want: String

    public init(name: String, input: String, want: String) {
        self.name = name
        self.input = input
        self.want = want
    }
}

public struct QualityFixtureSet: Sendable, Equatable {
    public let name: String
    public let samples: [QualitySample]

    public init(name: String, samples: [QualitySample]) {
        self.name = name
        self.samples = samples
    }
}

public enum QualityFixtureError: Error, Equatable {
    case missingReference(sample: String)
    case unreadableDirectory(path: String)
}

public enum QualityFixtures {

    /// Reads a `<name>.in` / `<name>.want` directory, sorted by name so a table
    /// lists its samples in the same order every run.
    public static func load(directory: URL) throws -> QualityFixtureSet {
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)
        } catch {
            throw QualityFixtureError.unreadableDirectory(path: directory.path)
        }

        var samples: [QualitySample] = []
        for input in entries.filter({ $0.pathExtension == "in" }).sorted(by: {
            $0.lastPathComponent < $1.lastPathComponent
        }) {
            let name = input.deletingPathExtension().lastPathComponent
            let reference = input.deletingPathExtension().appendingPathExtension("want")
            guard let wantData = FileManager.default.contents(atPath: reference.path),
                let inputData = FileManager.default.contents(atPath: input.path)
            else {
                throw QualityFixtureError.missingReference(sample: name)
            }
            samples.append(
                QualitySample(
                    name: name,
                    input: String(decoding: inputData, as: UTF8.self),
                    want: String(decoding: wantData, as: UTF8.self)))
        }
        return QualityFixtureSet(
            name: directory.lastPathComponent, samples: samples)
    }
}

import ArgumentParser
import CzechatorCore

struct SegmentsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "segments",
        abstract: "Vypíše segmenty, které by šly modelu. Model se nevolá."
    )

    @Argument(help: "Cesta k souboru, nebo - pro standardní vstup.")
    var path: String = "-"

    @Option(name: .long, help: "Vynutí formát: json, xml, html, plain.")
    var format: String?

    @Option(name: .long, help: "Cesta ke konfiguraci.")
    var config: String?

    @Flag(name: .long, help: "Vypíše i vyloučené spany a aktivní pravidla.")
    var showSkipped = false

    func run() throws {
        let environment = try CLIEnvironment.load(configPath: config, profileName: nil)
        let text = try CLIEnvironment.readInput(path: path)
        let input = ClipboardInput(text: text)

        let formatID: String
        let handler: any FormatHandler
        if let format {
            guard let forced = environment.registry.handler(id: format) else {
                throw ValidationError(
                    "neznámý formát: \(format) (dostupné: "
                        + environment.registry.availableIDs.joined(separator: ", ") + ")")
            }
            formatID = format
            handler = forced
        } else {
            let selected = environment.registry.select(input)
            formatID = selected.id
            handler = selected.handler
        }

        print("formát: \(formatID)")
        let segments = try handler.segments(in: text)
        print("segmentů: \(segments.count)")
        for (index, segment) in segments.enumerated() {
            let offset = text.distance(from: text.startIndex, to: segment.range.lowerBound)
            let length = text.distance(from: segment.range.lowerBound, to: segment.range.upperBound)
            print("\(index + 1). [\(offset)+\(length)] \(segment.kind.rawValue): \(segment.text)")
        }

        guard showSkipped else { return }

        print("\nvyloučené spany:")
        let spans = try SegmentationDebug.excludedSpans(
            in: text, rules: environment.config.segmentation, formatID: formatID)
        if spans.isEmpty { print("  (žádné)") }
        for span in spans {
            print("  [\(span.offset)] \(span.text)   <- \(span.pattern)")
        }

        print("\naktivní pravidla:")
        for line in SegmentationDebug.activeRuleSummary(
            rules: environment.config.segmentation, formatID: formatID)
        {
            print("  \(line)")
        }
    }
}

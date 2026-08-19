import ArgumentParser
import CzechatorCore

@main
struct Czechator: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "czechator",
        abstract: "Doplní do textu českou diakritiku, aniž by sáhla na strukturu.",
        version: CzechatorCore.Czechator.version,
        // No defaultSubcommand on purpose: with one, ArgumentParser routes
        // bare arguments into it, so `czechator --version` ended up at `fix`,
        // which does not know the option.
        subcommands: [FixCommand.self, SegmentsCommand.self]
    )
}

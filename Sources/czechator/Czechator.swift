import ArgumentParser

@main
struct Czechator: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "czechator",
        abstract: "Doplní do textu českou diakritiku, aniž by sáhla na strukturu.",
        subcommands: [FixCommand.self, SegmentsCommand.self],
        defaultSubcommand: FixCommand.self
    )
}

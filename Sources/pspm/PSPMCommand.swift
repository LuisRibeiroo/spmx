import ArgumentParser
import Foundation

@main
struct PSPMCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pspm",
        abstract: "Performant Swift Package Manager — global APFS CoW store and transparent shims for Swift & Flutter.",
        version: "0.1.0",
        subcommands: [
            DerivedDataPathCommand.self,
            HydrateCommand.self,
            InstallCommand.self,
            HarvestCommand.self,
            HooksCommand.self,
            SetupCommand.self,
            UninstallCommand.self
        ]
    )
}

import ArgumentParser
import Foundation
import PSPMCore

@main
enum PSPMEntrypoint {
    static func main() {
        let argv0 = CommandLine.arguments.first ?? "pspm"
        let role = ShimRole.detect(argv0: argv0)

        if role == .pspm {
            PSPMCommand.main()
            return
        }

        let env = ProcessInfo.processInfo.environment
        let verboseEnabled = env["PSPM_VERBOSE"] == "1" || env["PSPM_VERBOSE"]?.lowercased() == "true"
        let stderrStyle = TerminalStyle.stderr
        let verboseLogger: (@Sendable (String) -> Void)?
        if verboseEnabled {
            verboseLogger = { message in
                let formatted = stderrStyle.gray("[pspm:\(role.rawValue)] \(message)")
                FileHandle.standardError.write(Data("\(formatted)\n".utf8))
            }
        } else {
            verboseLogger = nil
        }

        do {
            let dispatcher = ShimDispatcher(verboseLogger: verboseLogger)
            let outcome = try dispatcher.dispatch(
                role: role,
                arguments: Array(CommandLine.arguments.dropFirst()),
                workingDirectory: FileManager.default.currentDirectoryPath,
                environment: env
            )
            Foundation.exit(outcome.exitCode)
        } catch {
            let formatted = stderrStyle.stepError("pspm (\(role.rawValue) shim)", detail: error.localizedDescription)
            FileHandle.standardError.write(Data("\(formatted)\n".utf8))
            Foundation.exit(1)
        }
    }
}

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
            MigrateCommand.self,
            StoreCommand.self,
            StatusCommand.self,
            DoctorCommand.self,
            HooksCommand.self,
            SetupCommand.self,
            UninstallCommand.self
        ]
    )
}

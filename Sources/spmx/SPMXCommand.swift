import ArgumentParser
import Darwin
import Foundation
import SPMXCore

@main
enum SPMXEntrypoint {
    static func main() {
        let argv0 = CommandLine.arguments.first ?? "spmx"
        let role = ShimRole.detect(argv0: argv0)

        if role == .spmx {
            let args = Array(CommandLine.arguments.dropFirst())
            do {
                var command = try SPMXCommand.parseAsRoot(args)
                try command.run()
                if shouldOfferInteractiveAutoPrune(arguments: args) {
                    _ = try? StoreManager().runInteractiveAutoPruneIfDue()
                }
                Foundation.exit(0)
            } catch {
                SPMXCommand.exit(withError: error)
            }
        }

        let env = ProcessInfo.processInfo.environment
        let verboseEnabled = env["SPMX_VERBOSE"] == "1" || env["SPMX_VERBOSE"]?.lowercased() == "true"
        let stderrStyle = TerminalStyle.stderr
        let verboseLogger: (@Sendable (String) -> Void)?
        if verboseEnabled {
            verboseLogger = { message in
                let formatted = stderrStyle.gray("[spmx:\(role.rawValue)] \(message)")
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
            let formatted = stderrStyle.stepError("spmx (\(role.rawValue) shim)", detail: error.localizedDescription)
            FileHandle.standardError.write(Data("\(formatted)\n".utf8))
            Foundation.exit(1)
        }
    }
}

struct SPMXCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "spmx",
        abstract: "Performant Swift Package Manager — global APFS CoW store and transparent shims for Swift & Flutter.",
        version: "0.2.4",
        subcommands: [
            DerivedDataPathCommand.self,
            HydrateCommand.self,
            InstallCommand.self,
            HarvestCommand.self,
            LinkCommand.self,
            UnlinkCommand.self,
            MigrateCommand.self,
            StoreCommand.self,
            PruneCommand.self,
            StatusCommand.self,
            DoctorCommand.self,
            HooksCommand.self,
            SetupCommand.self,
            UpgradeCommand.self,
            UninstallCommand.self
        ]
    )
}

func shouldOfferInteractiveAutoPrune(
    arguments: [String],
    isInteractiveTTY: Bool = (isatty(STDIN_FILENO) != 0 && isatty(STDOUT_FILENO) != 0)
) -> Bool {
    guard isInteractiveTTY else { return false }
    let nonFlagArgs = arguments.filter { !$0.hasPrefix("-") }
    guard let firstCommand = nonFlagArgs.first?.lowercased() else { return false }

    // Skip when running prune itself, uninstall, or raw path-output commands
    if firstCommand == "prune" || firstCommand == "uninstall" || firstCommand == "derived-data-path" {
        return false
    }
    if firstCommand == "store" {
        let sub = nonFlagArgs.dropFirst().first?.lowercased()
        if sub == "prune" || sub == "path" {
            return false
        }
    }

    let suppressedFlags: Set<String> = ["--json", "-q", "--quiet", "-h", "--help", "--version"]
    if arguments.contains(where: { suppressedFlags.contains($0.lowercased()) }) {
        return false
    }

    return true
}

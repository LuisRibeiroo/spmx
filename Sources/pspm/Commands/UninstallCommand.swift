import ArgumentParser
import Foundation
import PSPMCore

struct UninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove pspm shims, binary, and shell profile PATH configuration."
    )

    @Flag(
        name: .long,
        help: "Also delete cached packages in ~/.pspm/store and ~/.pspm/compilation-cache."
    )
    var purge: Bool = false

    @Flag(
        name: [.short, .long],
        help: "Skip interactive confirmation prompt."
    )
    var yes: Bool = false

    func run() throws {
        if !yes {
            let prompt: String
            if purge {
                prompt = "Remove pspm shims, binary, shell RC entries, and purge ~/.pspm/store & ~/.pspm/compilation-cache? [y/N]: "
            } else {
                prompt = "Remove pspm shims, binary, and shell RC entries (keeping ~/.pspm/store)? [y/N]: "
            }
            FileHandle.standardOutput.write(Data(prompt.utf8))

            let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            guard answer == "y" || answer == "yes" else {
                print("Uninstall aborted.")
                return
            }
        }

        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let result = try SetupManager.uninstall(
            purge: purge,
            homeDirectory: homeDirectory
        )

        print("pspm uninstalled:")
        print("  Shims removed:   \(result.removedShimsDirectory ? "yes" : "not found")")
        print("  Binary removed:  \(result.removedBinary ? "yes" : "not found")")
        if result.cleanedShellRCs.isEmpty {
            print("  Shell RCs:       no pspm entries found")
        } else {
            let paths = result.cleanedShellRCs.map(\.path).joined(separator: ", ")
            print("  Shell RCs:       cleaned \(paths)")
        }
        if purge {
            print("  Store purged:    \(result.purgedStore ? "yes" : "not found")")
            print("  Cache purged:    \(result.purgedCompilationCache ? "yes" : "not found")")
        } else {
            let storePath = homeDirectory.appendingPathComponent(".pspm/store").path
            print("  Store preserved: \(storePath) (pass --purge to delete)")
        }
    }
}

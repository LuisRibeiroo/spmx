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
        let style = TerminalStyle.stdout

        if !yes {
            let prompt: String
            if purge {
                prompt = "\(style.warningIcon) \(style.warningText("Remove pspm shims, binary, shell RC entries, and purge ~/.pspm/store & ~/.pspm/compilation-cache?")) \(style.gray("[y/N]: "))"
            } else {
                prompt = "\(style.warningIcon) \(style.bold("Remove pspm shims, binary, and shell RC entries")) \(style.gray("(keeping ~/.pspm/store)? [y/N]: "))"
            }
            FileHandle.standardOutput.write(Data(prompt.utf8))

            let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            guard answer == "y" || answer == "yes" else {
                print(style.tip("Uninstall aborted."))
                return
            }
        }

        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let result = try SetupManager.uninstall(
            purge: purge,
            homeDirectory: homeDirectory
        )

        print(style.heading("pspm uninstall"))
        print("")
        if result.removedShimsDirectory {
            print(style.stepSuccess("Shims removed", detail: style.gray("~/.pspm/shims")))
        } else {
            print(style.stepSkipped("Shims", detail: "not found"))
        }

        if result.removedBinary {
            print(style.stepSuccess("Binary removed", detail: style.gray("~/.pspm/bin/pspm")))
        } else {
            print(style.stepSkipped("Binary", detail: "not found"))
        }

        if result.cleanedShellRCs.isEmpty {
            print(style.stepSkipped("Shell RCs", detail: "no pspm entries found"))
        } else {
            let paths = result.cleanedShellRCs.map(\.path).joined(separator: ", ")
            print(style.stepSuccess("Shell RCs cleaned", detail: style.gray(paths)))
        }

        if purge {
            print(result.purgedStore
                ? style.stepSuccess("Store purged", detail: style.gray("~/.pspm/store"))
                : style.stepSkipped("Store", detail: "not found"))
            print(result.purgedCompilationCache
                ? style.stepSuccess("Compilation cache purged", detail: style.gray("~/.pspm/compilation-cache"))
                : style.stepSkipped("Compilation cache", detail: "not found"))
        } else {
            let storePath = homeDirectory.appendingPathComponent(".pspm/store").path
            print("")
            print("  \(style.tip("›")) \(style.tip("Store preserved at")) \(style.tipItalic(storePath)) \(style.tip("(pass --purge to delete)"))")
        }
    }
}

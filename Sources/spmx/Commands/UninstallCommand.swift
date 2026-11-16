import ArgumentParser
import Foundation
import SPMXCore

struct UninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove spmx shims, binary, and shell profile PATH configuration."
    )

    @Flag(
        name: .long,
        help: "Also delete cached packages in ~/.spmx/store and ~/.spmx/compilation-cache."
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
                prompt = "\(style.warningIcon) \(style.warningText("Remove spmx shims, binary, shell RC entries, and purge ~/.spmx/store & ~/.spmx/compilation-cache?")) \(style.gray("[y/N]: "))"
            } else {
                prompt = "\(style.warningIcon) \(style.bold("Remove spmx shims, binary, and shell RC entries")) \(style.gray("(keeping ~/.spmx/store)? [y/N]: "))"
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

        print(style.heading("spmx uninstall"))
        print("")
        if result.removedShimsDirectory {
            print(style.stepSuccess("Shims removed", detail: style.gray("~/.spmx/shims")))
        } else {
            print(style.stepSkipped("Shims", detail: "not found"))
        }

        if result.removedBinary {
            print(style.stepSuccess("Binary removed", detail: style.gray("~/.spmx/bin/spmx")))
        } else {
            print(style.stepSkipped("Binary", detail: "not found"))
        }

        if result.cleanedShellRCs.isEmpty {
            print(style.stepSkipped("Shell RCs", detail: "no spmx entries found"))
        } else {
            let paths = result.cleanedShellRCs.map(\.path).joined(separator: ", ")
            print(style.stepSuccess("Shell RCs cleaned", detail: style.gray(paths)))
        }

        if purge {
            print(result.purgedStore
                ? style.stepSuccess("Store purged", detail: style.gray("~/.spmx/store"))
                : style.stepSkipped("Store", detail: "not found"))
            print(result.purgedCompilationCache
                ? style.stepSuccess("Compilation cache purged", detail: style.gray("~/.spmx/compilation-cache"))
                : style.stepSkipped("Compilation cache", detail: "not found"))
        } else {
            let storePath = homeDirectory.appendingPathComponent(".spmx/store").path
            print("")
            print("  \(style.tip("›")) \(style.tip("Store preserved at")) \(style.tipItalic(storePath)) \(style.tip("(pass --purge to delete)"))")
        }
    }
}

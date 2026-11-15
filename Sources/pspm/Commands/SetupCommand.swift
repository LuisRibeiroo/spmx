import ArgumentParser
import Foundation
import PSPMCore

struct SetupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Initialize ~/.pspm directories, create PATH shims, and configure shell profile."
    )

    @Flag(
        name: .long,
        help: "Do not modify shell profile files (~/.zshrc, ~/.bashrc, ~/.config/fish/config.fish)."
    )
    var noModifyPath: Bool = false

    func run() throws {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let binaryURL = resolveExecutableURL(homeDirectory: homeDirectory)
        let shell = ProcessInfo.processInfo.environment["SHELL"]

        let result = try SetupManager.setup(
            noModifyPath: noModifyPath,
            binaryPath: binaryURL,
            homeDirectory: homeDirectory,
            shell: shell
        )

        print(result.summaryBanner())
    }

    private func resolveExecutableURL(homeDirectory: URL) -> URL {
        let fileManager = FileManager.default
        let defaultInstallURL = homeDirectory
            .appendingPathComponent(".pspm")
            .appendingPathComponent("bin")
            .appendingPathComponent("pspm")

        if let arg0 = CommandLine.arguments.first, !arg0.isEmpty {
            if arg0.contains("/") {
                let candidate: URL
                if arg0.hasPrefix("/") {
                    candidate = URL(fileURLWithPath: arg0).standardized
                } else {
                    candidate = URL(fileURLWithPath: fileManager.currentDirectoryPath)
                        .appendingPathComponent(arg0)
                        .standardized
                }
                if fileManager.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            } else if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
                let shimsPath = homeDirectory.appendingPathComponent(".pspm/shims").standardized.path
                for entry in pathEnv.split(separator: ":") {
                    let dir = String(entry)
                    if URL(fileURLWithPath: dir).standardized.path == shimsPath {
                        continue
                    }
                    let candidate = URL(fileURLWithPath: dir).appendingPathComponent(arg0)
                    if fileManager.isExecutableFile(atPath: candidate.path) {
                        return candidate
                    }
                }
            }
        }

        if let bundleExecutable = Bundle.main.executableURL,
           fileManager.isExecutableFile(atPath: bundleExecutable.path) {
            return bundleExecutable
        }

        return defaultInstallURL
    }
}

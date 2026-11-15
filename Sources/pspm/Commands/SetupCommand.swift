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
        let style = TerminalStyle.stdout

        print(style.heading("pspm setup"))

        let result = try SetupManager.setup(
            noModifyPath: noModifyPath,
            binaryPath: binaryURL,
            homeDirectory: homeDirectory,
            shell: shell,
            stepObserver: { event in
                switch event {
                case .running(let step, let detail):
                    if style.isEnabled {
                        let suffix = detail.map { " \(style.gray("(\($0))"))" } ?? ""
                        let line = "\(style.stepRunning(step))\(suffix)"
                        FileHandle.standardOutput.write(Data("\r\u{1B}[2K\(line)".utf8))
                        fflush(Darwin.stdout)
                    }
                case .completed(let step, let detail):
                    let detailText = detail.map { style.cyan($0) }
                    let line = style.stepSuccess(step, detail: detailText)
                    if style.isEnabled {
                        FileHandle.standardOutput.write(Data("\r\u{1B}[2K\(line)\n".utf8))
                    } else {
                        print(line)
                    }
                case .skipped(let step, let detail):
                    let line = style.stepSkipped(step, detail: detail)
                    if style.isEnabled {
                        FileHandle.standardOutput.write(Data("\r\u{1B}[2K\(line)\n".utf8))
                    } else {
                        print(line)
                    }
                }
            }
        )

        print("")
        print("  \(style.gray("Binary:"))            \(style.blue(result.binaryPath.path))")
        if let localBinSymlink = result.localBinSymlink {
            print("  \(style.gray("PATH link:"))         \(style.blue(localBinSymlink.path))")
        }
        print("  \(style.gray("Store:"))             \(style.blue(result.storeDirectory.path))")
        print("  \(style.gray("Compilation Cache:")) \(style.blue(result.compilationCacheDirectory.path))")
        print("  \(style.gray("Shims:"))             \(style.blue(result.shimsDirectory.path))")
        print("")
        print(style.successText("pspm is ready!") + " " + style.gray("Existing and new Flutter, Xcode, and SwiftPM builds now use the global cache."))
        print("")
        print(result.tipsSection(style: style))
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

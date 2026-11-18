import ArgumentParser
import Darwin
import Foundation
import SPMXCore

struct UpgradeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "upgrade",
        abstract: "Check for a newer spmx release and update the local installation."
    )

    @Flag(
        name: .long,
        help: "Only check whether a newer release is available without installing."
    )
    var check: Bool = false

    @Flag(
        name: [.short, .long],
        help: "Reinstall even if already on the latest version."
    )
    var force: Bool = false

    @Option(
        name: .long,
        help: "Specific release version or tag to install (e.g. 0.2.2 or v0.2.2)."
    )
    var version: String?

    @Flag(
        name: .long,
        help: "Do not modify shell profile files (~/.zshrc, ~/.bashrc, ~/.config/fish/config.fish)."
    )
    var noModifyPath: Bool = false

    @Flag(
        name: .long,
        help: "Output machine-readable JSON."
    )
    var json: Bool = false

    func run() throws {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let currentExecutableURL = resolveCurrentExecutableURL(homeDirectory: homeDirectory)
        let startedAt = Date()
        let style = TerminalStyle.stdout
        let manager = UpgradeManager(homeDirectory: homeDirectory)

        if !json {
            let modeBadge = check ? " \(style.gray("[check]"))" : ""
            print("\(style.heading("spmx upgrade"))\(modeBadge)")
            print("")
        }

        let options = UpgradeOptions(
            checkOnly: check,
            force: force,
            targetVersion: version,
            noModifyPath: noModifyPath,
            currentVersion: SPMXCommand.configuration.version,
            currentExecutableURL: currentExecutableURL
        )

        let result = try manager.upgrade(options: options) { event in
            guard !json else { return }
            switch event {
            case .running(let step, let detail):
                if style.isEnabled {
                    let suffix = detail.map { " \(style.gray("(\($0))"))" } ?? ""
                    let line = "\(style.stepRunning(step))\(suffix)"
                    fputs("\r\u{1B}[2K\(line)", Darwin.stdout)
                    fflush(Darwin.stdout)
                }
            case .completed(let step, let detail):
                let detailText = detail.map { style.gray($0) }
                let line = style.stepSuccess(step, detail: detailText)
                if style.isEnabled {
                    fputs("\r\u{1B}[2K\(line)\n", Darwin.stdout)
                    fflush(Darwin.stdout)
                } else {
                    print(line)
                }
            case .skipped(let step, let detail):
                let line = style.stepSkipped(step, detail: detail)
                if style.isEnabled {
                    fputs("\r\u{1B}[2K\(line)\n", Darwin.stdout)
                    fflush(Darwin.stdout)
                } else {
                    print(line)
                }
            }
        }

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(result)
            if let text = String(data: data, encoding: .utf8) {
                print(text)
            }
            return
        }

        print("")
        if result.checkOnly {
            if result.upToDate {
                print("  \(style.successIcon) \(style.bold("spmx is up to date")) \(style.gray("(v\(result.currentVersion))"))")
            } else {
                print("  \(style.warningIcon) \(style.yellow(style.bold("Update available:"))) \(style.gray("v\(result.currentVersion)")) -> \(style.green(style.bold("v\(result.targetVersion)")))")
                print("  \(style.tip("›")) \(style.tip("Run")) \(style.tipCommand("`spmx upgrade`")) \(style.tip("to install v\(result.targetVersion)."))")
            }
            return
        }

        if result.upgraded {
            if let binaryPath = result.binaryPath {
                print("  \(style.gray("Binary:"))   \(binaryPath)")
            }
            print("")
            print("\(style.doneIn(seconds: Date().timeIntervalSince(startedAt))) \(style.gray("·")) \(style.successText("Upgraded spmx v\(result.currentVersion) -> v\(result.targetVersion)!"))")
        } else {
            print("  \(style.successIcon) \(style.bold("spmx v\(result.currentVersion) is already the latest version."))")
        }
    }

    private func resolveCurrentExecutableURL(homeDirectory: URL) -> URL? {
        let fileManager = FileManager.default
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
                let shimsPath = homeDirectory.appendingPathComponent(".spmx/shims").standardized.path
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
        return nil
    }
}

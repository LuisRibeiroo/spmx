import ArgumentParser
import Foundation
import SPMXCore

struct UnlinkCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unlink",
        abstract: "Unlink a project from the global store so shims and hooks pass through to its local cache."
    )

    @Argument(help: "Path to the project directory to unlink (defaults to current directory).")
    var path: String = "."

    @Option(
        name: .long,
        help: "Optional reason recorded in ~/.spmx/store/index.json."
    )
    var reason: String?

    @Flag(
        name: .long,
        help: "Output machine-readable JSON."
    )
    var json: Bool = false

    func run() throws {
        let fileManager = FileManager.default
        let canonicalInput = DerivedDataPathCalculator.canonicalizePath(
            path,
            currentDirectory: fileManager.currentDirectoryPath
        )

        let projectRoot: String
        if let detected = try? ProjectDetector.detect(in: canonicalInput, fileManager: fileManager) {
            projectRoot = detected.rootPath
        } else {
            projectRoot = canonicalInput
        }

        let store = GlobalStore()
        let record = try store.excludeProject(at: projectRoot, reason: reason)

        if json {
            let payload = UnlinkJSONOutput(
                unlinked: true,
                projectPath: record.path,
                excludedAt: record.excludedAt,
                reason: record.reason
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(payload)
            if let text = String(data: data, encoding: .utf8) {
                print(text)
            }
            return
        }

        let style = TerminalStyle.stdout
        print("\(style.heading("spmx unlink"))")
        print("  \(style.successIcon) Unlinked \(style.path(record.path)) from global store.")
        print("  \(style.gray("›")) Local SourcePackages/.build remains intact; shims will pass through directly.")
        print("  \(style.tip("›")) \(style.tip("Re-link anytime with: spmx link \(record.path)"))")
    }
}

private struct UnlinkJSONOutput: Encodable {
    let unlinked: Bool
    let projectPath: String
    let excludedAt: Date
    let reason: String?
}

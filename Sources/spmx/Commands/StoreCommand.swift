import ArgumentParser
import Foundation
import SPMXCore

struct StoreCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "store",
        abstract: "Inspect and manage the global spmx store and compilation cache.",
        subcommands: [
            Path.self,
            List.self,
            Status.self,
            Prune.self
        ],
        defaultSubcommand: Status.self
    )

    struct Path: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "path",
            abstract: "Print the absolute path to the global spmx store."
        )

        func run() throws {
            print(StoreManager().storePath())
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List cached packages grouped by identity and semantic version, with linked projects."
        )

        @Flag(name: .long, help: "Output machine-readable JSON.")
        var json: Bool = false

        func run() throws {
            let report = try StoreManager().list()
            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(report)
                if let text = String(data: data, encoding: .utf8) {
                    print(text)
                }
                return
            }

            let style = TerminalStyle.stdout
            let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
            print(style.heading("spmx store list"))
            print(style.scopeLine(report.storePath))
            print("")

            if report.packages.isEmpty {
                print("  \(style.gray("No cached packages in store yet."))")
                return
            }

            for slice in report.packages {
                let versionPart = slice.version ?? slice.branch ?? "untagged"
                let shortRev = slice.revision.isEmpty ? "unknown" : String(slice.revision.prefix(8))
                let sizeText = StoreCommand.formatBytes(slice.sizeBytes)
                let projCount = slice.linkedProjects.count
                let projSuffix = projCount == 1 ? "1 project" : "\(projCount) projects"
                print("  \(style.primaryBold(slice.identity)) \(style.green("@ \(versionPart)")) \(style.gray("(rev \(shortRev))"))  \(style.bold(sizeText))  \(style.gray("· \(projSuffix)"))")
                for projectPath in slice.linkedProjects {
                    let shortPath = projectPath.hasPrefix(homePath + "/")
                        ? "~/" + projectPath.dropFirst(homePath.count + 1)
                        : projectPath
                    print("    \(style.gray("›")) \(style.gray(shortPath))")
                }
            }

            print("")
            print("  \(style.gray("Packages:"))      \(style.primaryBold("\(report.packages.count)")) \(style.gray("(\(StoreCommand.formatBytes(report.totalCheckoutsSizeBytes)))"))")
            if report.repositoriesCount > 0 {
                print("  \(style.gray("Repositories:"))  \(style.primaryBold("\(report.repositoriesCount)")) \(style.gray("(\(StoreCommand.formatBytes(report.repositoriesSizeBytes)))"))")
            }
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show cached packages, toolchain-grouped prebuilts, compilation cache size, and per-project/global CoW savings."
        )

        @Flag(name: .long, help: "Output machine-readable JSON.")
        var json: Bool = false

        func run() throws {
            let report = try StoreManager().status()
            if json {
                let payload = StoreStatusJSONOutput(
                    storePath: report.storePath,
                    checkoutsCount: report.checkoutsCount,
                    checkoutsSizeBytes: report.checkoutsSizeBytes,
                    repositoriesCount: report.repositoriesCount,
                    repositoriesSizeBytes: report.repositoriesSizeBytes,
                    artifactsCount: report.artifactsCount,
                    artifactsSizeBytes: report.artifactsSizeBytes,
                    prebuiltsCount: report.prebuiltsCount,
                    prebuiltsSizeBytes: report.prebuiltsSizeBytes,
                    logicalStoreSizeBytes: report.logicalStoreSizeBytes,
                    compilationCachePath: report.compilationCachePath,
                    compilationCacheSizeBytes: report.compilationCacheSizeBytes,
                    activeProjectsCount: report.activeProjectsCount,
                    missingProjectsCount: report.missingProjectsCount,
                    excludedProjects: report.excludedProjects,
                    projectSavings: report.projectSavings,
                    totalMachineSavedBytes: report.totalMachineSavedBytes,
                    estimatedCoWSavingsBytes: report.estimatedCoWSavingsBytes
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(payload)
                if let text = String(data: data, encoding: .utf8) {
                    print(text)
                }
                return
            }

            let style = TerminalStyle.stdout
            let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
            print(style.heading("spmx store"))
            print(style.scopeLine(report.storePath))
            print("")

            print(style.section("Entries:"))
            print("  \(style.gray("Checkouts:"))          \(style.primaryBold("\(report.checkoutsCount)")) \(style.gray("(\(formatBytes(report.checkoutsSizeBytes)))"))")
            print("  \(style.gray("Repositories:"))       \(style.primaryBold("\(report.repositoriesCount)")) \(style.gray("(\(formatBytes(report.repositoriesSizeBytes)))"))")
            print("  \(style.gray("Artifacts:"))          \(style.primaryBold("\(report.artifactsCount)")) \(style.gray("(\(formatBytes(report.artifactsSizeBytes)))"))")
            print("  \(style.gray("Prebuilts:"))          \(style.primaryBold("\(report.prebuiltsCount)")) \(style.gray("(\(formatBytes(report.prebuiltsSizeBytes)))"))")

            for group in report.prebuiltsByToolchain {
                var toolchainLabel = group.toolchainHash
                if let swift = group.swiftVersion {
                    let shortSwift = swift.split(separator: "\n").first.map(String.init) ?? swift
                    if let xcode = group.xcodeVersion?.split(separator: "\n").first {
                        toolchainLabel += " [\(xcode) | \(shortSwift)]"
                    } else {
                        toolchainLabel += " [\(shortSwift)]"
                    }
                }
                print("    \(style.gray("›")) \(style.italic(style.gray(toolchainLabel))): \(group.count) prebuilt(s) \(style.gray("(\(formatBytes(group.sizeBytes)))"))")
            }

            if !report.projectSavings.isEmpty {
                print("")
                print(style.section("Linked projects:"))
                for proj in report.projectSavings {
                    let shortPath = proj.projectPath.hasPrefix(homePath + "/")
                        ? "~/" + proj.projectPath.dropFirst(homePath.count + 1)
                        : proj.projectPath
                    print("  \(style.gray("›")) \(style.path(shortPath))  \(style.gray("\(proj.sharedPackagesCount) pkg(s)"))  \(style.green(formatBytes(proj.projectSavedBytes)))")
                }
            }

            print("")
            print(style.section("Summary:"))
            print("  \(style.gray("Logical size:"))       \(style.bold(formatBytes(report.logicalStoreSizeBytes)))")
            print("  \(style.gray("Compilation cache:"))  \(report.compilationCachePath) \(style.gray("(\(formatBytes(report.compilationCacheSizeBytes)))"))")
            let missingSuffix = report.missingProjectsCount > 0
                ? style.yellow("\(report.missingProjectsCount) missing")
                : style.gray("0 missing")
            let unlinkedSuffix = report.excludedProjects.isEmpty
                ? ""
                : style.gray(", \(report.excludedProjects.count) unlinked")
            print("  \(style.gray("Projects:"))           \(style.primaryBold("\(report.totalRegisteredProjectsCount)")) \(style.gray("total")) (\(style.green("\(report.activeProjectsCount) active")), \(missingSuffix)\(unlinkedSuffix))")
            print("  \(style.gray("Total estimated disk saved across machine:")) \(style.green(style.bold(formatBytes(report.totalMachineSavedBytes))))")
        }
    }

    struct Prune: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "prune",
            abstract: "Remove stale projects, unreferenced store entries, and old compilation cache files, or configure automatic prune reminders.",
            subcommands: [
                PruneAutoCommand.self
            ]
        )

        @Flag(
            name: .long,
            help: "Preview what would be removed without deleting anything."
        )
        var dryRun: Bool = false

        @Option(
            name: .long,
            help: "Only remove unreferenced entries and cache files older than this many days."
        )
        var olderThan: Int = 30

        @Option(
            name: .long,
            help: "Configure the automatic prune reminder interval in days (default: 30; 0 disables)."
        )
        var autoEvery: Int?

        @Flag(
            name: .long,
            help: "Enable automatic prune reminders on explicit spmx commands."
        )
        var enableAuto: Bool = false

        @Flag(
            name: .long,
            help: "Disable automatic prune reminders."
        )
        var disableAuto: Bool = false

        @Flag(
            name: .long,
            help: "Show current automatic prune configuration and last prune timestamp without pruning."
        )
        var status: Bool = false

        @Flag(
            name: .long,
            help: "Output machine-readable JSON."
        )
        var json: Bool = false

        func validate() throws {
            try PruneRunner.validate(
                olderThan: olderThan,
                autoEvery: autoEvery,
                enableAuto: enableAuto,
                disableAuto: disableAuto
            )
        }

        func run() throws {
            try PruneRunner.execute(
                commandName: "spmx store prune",
                dryRun: dryRun,
                olderThan: olderThan,
                autoEvery: autoEvery,
                enableAuto: enableAuto,
                disableAuto: disableAuto,
                statusOnly: status,
                json: json
            )
        }
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))))
    }
}

private struct StoreStatusJSONOutput: Encodable {
    let storePath: String
    let checkoutsCount: Int
    let checkoutsSizeBytes: UInt64
    let repositoriesCount: Int
    let repositoriesSizeBytes: UInt64
    let artifactsCount: Int
    let artifactsSizeBytes: UInt64
    let prebuiltsCount: Int
    let prebuiltsSizeBytes: UInt64
    let logicalStoreSizeBytes: UInt64
    let compilationCachePath: String
    let compilationCacheSizeBytes: UInt64
    let activeProjectsCount: Int
    let missingProjectsCount: Int
    let excludedProjects: [String]
    let projectSavings: [ProjectSavingsSummary]
    let totalMachineSavedBytes: UInt64
    let estimatedCoWSavingsBytes: UInt64
}

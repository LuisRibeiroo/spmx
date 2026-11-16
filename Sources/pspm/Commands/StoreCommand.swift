import ArgumentParser
import Foundation
import PSPMCore

struct StoreCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "store",
        abstract: "Inspect and manage the global pspm store and compilation cache.",
        subcommands: [
            Path.self,
            Status.self,
            Prune.self
        ],
        defaultSubcommand: Status.self
    )

    struct Path: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "path",
            abstract: "Print the absolute path to the global pspm store."
        )

        func run() throws {
            print(StoreManager().storePath())
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show cached packages, toolchain-grouped prebuilts, compilation cache size, and CoW savings."
        )

        func run() throws {
            let style = TerminalStyle.stdout
            let report = try StoreManager().status()
            print(style.heading("pspm store"))
            print(style.scopeLine(report.storePath))
            print("")

            print(style.section("Entries:"))
            print("  \(style.gray("Checkouts:"))          \(style.primaryBold("\(report.checkoutsCount)")) \(style.gray("(\(formatBytes(report.checkoutsSizeBytes)))"))")
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

            print("")
            print(style.section("Summary:"))
            print("  \(style.gray("Logical size:"))       \(style.bold(formatBytes(report.logicalStoreSizeBytes)))")
            print("  \(style.gray("Compilation cache:"))  \(report.compilationCachePath) \(style.gray("(\(formatBytes(report.compilationCacheSizeBytes)))"))")
            let missingSuffix = report.missingProjectsCount > 0
                ? style.yellow("\(report.missingProjectsCount) missing")
                : style.gray("0 missing")
            print("  \(style.gray("Projects:"))           \(style.primaryBold("\(report.totalRegisteredProjectsCount)")) \(style.gray("total")) (\(style.green("\(report.activeProjectsCount) active")), \(missingSuffix))")
            print("  \(style.gray("Est. CoW savings:"))   \(style.green(style.bold(formatBytes(report.estimatedCoWSavingsBytes))))")
        }
    }

    struct Prune: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "prune",
            abstract: "Remove stale projects, unreferenced store entries, and old compilation cache files."
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

        func validate() throws {
            if olderThan < 0 {
                throw ValidationError("--older-than must be zero or greater.")
            }
        }

        func run() throws {
            let startedAt = Date()
            let style = TerminalStyle.stdout
            let report = try StoreManager().prune(
                options: PruneOptions(dryRun: dryRun, olderThanDays: olderThan)
            )
            let prefix = report.dryRun ? "\(style.dryRunBadge()) " : ""
            print("\(prefix)\(style.heading("pspm store prune")) \(style.gray("(older than \(olderThan) day(s))"))")
            print("")
            print("  \(style.gray("Missing projects removed:"))   \(style.primaryBold("\(report.removedMissingProjects.count)"))")
            for path in report.removedMissingProjects {
                print("    \(style.removeIcon) \(style.gray(path))")
            }
            print("  \(style.gray("Unreferenced checkouts:"))     \(style.primaryBold("\(report.removedCheckouts.count)"))")
            for path in report.removedCheckouts {
                print("    \(style.removeIcon) \(style.gray(path))")
            }
            print("  \(style.gray("Unreferenced artifacts:"))     \(style.primaryBold("\(report.removedArtifacts.count)"))")
            for path in report.removedArtifacts {
                print("    \(style.removeIcon) \(style.gray(path))")
            }
            print("  \(style.gray("Unreferenced prebuilts:"))     \(style.primaryBold("\(report.removedPrebuilts.count)"))")
            for path in report.removedPrebuilts {
                print("    \(style.removeIcon) \(style.gray(path))")
            }
            print("  \(style.gray("Compilation cache entries:"))  \(style.primaryBold("\(report.removedCompilationCacheEntries.count)"))")
            for path in report.removedCompilationCacheEntries {
                print("    \(style.removeIcon) \(style.gray(path))")
            }
            print("")
            let verb = report.dryRun ? "Would reclaim" : "Reclaimed"
            print("  \(style.bold("\(verb):")) \(style.green(style.bold(formatBytes(report.reclaimedBytes))))")
            print(style.doneIn(seconds: Date().timeIntervalSince(startedAt)))
        }
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))))
    }
}

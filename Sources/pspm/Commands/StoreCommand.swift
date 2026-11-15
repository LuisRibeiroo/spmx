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
            print(style.heading("Global Store Status"))
            print("  \(style.dim("Store path:"))         \(style.path(report.storePath))")
            print("  \(style.dim("Checkouts:"))          \(style.bold("\(report.checkoutsCount)")) \(style.dim("(\(formatBytes(report.checkoutsSizeBytes)))"))")
            print("  \(style.dim("Artifacts:"))          \(style.bold("\(report.artifactsCount)")) \(style.dim("(\(formatBytes(report.artifactsSizeBytes)))"))")
            print("  \(style.dim("Prebuilts:"))          \(style.bold("\(report.prebuiltsCount)")) \(style.dim("(\(formatBytes(report.prebuiltsSizeBytes)))"))")

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
                print("    \(style.gray("-")) \(style.italic(style.gray(toolchainLabel))): \(group.count) prebuilt(s) \(style.dim("(\(formatBytes(group.sizeBytes)))"))")
            }

            print("  \(style.dim("Logical store size:")) \(style.bold(formatBytes(report.logicalStoreSizeBytes)))")
            print("  \(style.dim("Compilation cache:"))  \(style.path(report.compilationCachePath)) \(style.dim("(\(formatBytes(report.compilationCacheSizeBytes)))"))")
            let missingSuffix = report.missingProjectsCount > 0
                ? style.yellow("\(report.missingProjectsCount) missing on disk")
                : style.gray("0 missing on disk")
            print("  \(style.dim("Registered projects:")) \(style.bold("\(report.totalRegisteredProjectsCount)")) total (\(style.green("\(report.activeProjectsCount) active")), \(missingSuffix))")
            print("  \(style.dim("Est. CoW savings:"))   \(style.green(style.bold(formatBytes(report.estimatedCoWSavingsBytes))))")
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
            let style = TerminalStyle.stdout
            let report = try StoreManager().prune(
                options: PruneOptions(dryRun: dryRun, olderThanDays: olderThan)
            )
            let prefix = report.dryRun ? "\(style.yellow(style.bold("[dry-run]"))) " : ""
            print("\(prefix)\(style.heading("Prune summary")) \(style.dim("(older than \(olderThan) day(s))")):")
            print("  \(style.dim("Missing projects removed:"))   \(style.bold("\(report.removedMissingProjects.count)"))")
            for path in report.removedMissingProjects {
                print("    \(style.gray("-")) \(style.path(path))")
            }
            print("  \(style.dim("Unreferenced checkouts:"))     \(style.bold("\(report.removedCheckouts.count)"))")
            for path in report.removedCheckouts {
                print("    \(style.gray("-")) \(style.path(path))")
            }
            print("  \(style.dim("Unreferenced artifacts:"))     \(style.bold("\(report.removedArtifacts.count)"))")
            for path in report.removedArtifacts {
                print("    \(style.gray("-")) \(style.path(path))")
            }
            print("  \(style.dim("Unreferenced prebuilts:"))     \(style.bold("\(report.removedPrebuilts.count)"))")
            for path in report.removedPrebuilts {
                print("    \(style.gray("-")) \(style.path(path))")
            }
            print("  \(style.dim("Compilation cache entries:"))  \(style.bold("\(report.removedCompilationCacheEntries.count)"))")
            for path in report.removedCompilationCacheEntries {
                print("    \(style.gray("-")) \(style.path(path))")
            }
            let verb = report.dryRun ? "Would reclaim" : "Reclaimed"
            print("  \(style.bold("\(verb):")) \(style.green(style.bold(formatBytes(report.reclaimedBytes))))")
        }
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))))
    }
}

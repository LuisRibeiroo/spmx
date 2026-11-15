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
            let report = try StoreManager().status()
            print("Global Store Status")
            print("  Store path:         \(report.storePath)")
            print("  Checkouts:          \(report.checkoutsCount) (\(formatBytes(report.checkoutsSizeBytes)))")
            print("  Artifacts:          \(report.artifactsCount) (\(formatBytes(report.artifactsSizeBytes)))")
            print("  Prebuilts:          \(report.prebuiltsCount) (\(formatBytes(report.prebuiltsSizeBytes)))")

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
                print("    - \(toolchainLabel): \(group.count) prebuilt(s) (\(formatBytes(group.sizeBytes)))")
            }

            print("  Logical store size: \(formatBytes(report.logicalStoreSizeBytes))")
            print("  Compilation cache:  \(report.compilationCachePath) (\(formatBytes(report.compilationCacheSizeBytes)))")
            print("  Registered projects:\(report.totalRegisteredProjectsCount) total (\(report.activeProjectsCount) active, \(report.missingProjectsCount) missing on disk)")
            print("  Est. CoW savings:   \(formatBytes(report.estimatedCoWSavingsBytes))")
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
            let report = try StoreManager().prune(
                options: PruneOptions(dryRun: dryRun, olderThanDays: olderThan)
            )
            let prefix = report.dryRun ? "[dry-run] " : ""
            print("\(prefix)Prune summary (older than \(olderThan) day(s)):")
            print("  Missing projects removed:   \(report.removedMissingProjects.count)")
            for path in report.removedMissingProjects {
                print("    - \(path)")
            }
            print("  Unreferenced checkouts:     \(report.removedCheckouts.count)")
            for path in report.removedCheckouts {
                print("    - \(path)")
            }
            print("  Unreferenced artifacts:     \(report.removedArtifacts.count)")
            for path in report.removedArtifacts {
                print("    - \(path)")
            }
            print("  Unreferenced prebuilts:     \(report.removedPrebuilts.count)")
            for path in report.removedPrebuilts {
                print("    - \(path)")
            }
            print("  Compilation cache entries:  \(report.removedCompilationCacheEntries.count)")
            for path in report.removedCompilationCacheEntries {
                print("    - \(path)")
            }
            let verb = report.dryRun ? "Would reclaim" : "Reclaimed"
            print("  \(verb): \(formatBytes(report.reclaimedBytes))")
        }
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))))
    }
}

import ArgumentParser
import Darwin
import Foundation
import PSPMCore

struct MigrateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migrate",
        abstract: "Scan directories or worktrees for existing projects and migrate their SwiftPM caches to the global store."
    )

    @Argument(help: "Directory to scan for Flutter, Xcode, and SwiftPM projects (defaults to current directory).")
    var path: String?

    @Flag(
        name: [.long, .customLong("all")],
        help: "Scan the home directory (~) for existing projects and Git worktrees."
    )
    var home: Bool = false

    @Flag(
        name: .long,
        help: "Preview discovered projects and estimated space savings without modifying files."
    )
    var dryRun: Bool = false

    @Flag(
        name: [.long, .customLong("reclaim")],
        help: "Replace clean SourcePackages/.build entries with APFS Copy-on-Write clones from the store after harvesting."
    )
    var deduplicate: Bool = false

    @Flag(
        name: .long,
        help: "Install repo-local pspm post-checkout hooks in discovered Git repositories."
    )
    var installHooks: Bool = false

    @Option(
        name: .long,
        help: "Maximum directory traversal depth."
    )
    var maxDepth: Int = 6

    @Option(
        name: .long,
        help: "Exclude directory names, path substrings, or glob patterns (repeatable)."
    )
    var exclude: [String] = []

    @Flag(name: .shortAndLong, help: "Print verbose details for each scanned path.")
    var verbose: Bool = false

    @Flag(name: .shortAndLong, help: "Suppress normal output.")
    var quiet: Bool = false

    func run() throws {
        let style = TerminalStyle.stdout
        let fileManager = FileManager.default

        let searchRoots: [String]
        if let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchRoots = [path]
        } else if home {
            searchRoots = [fileManager.homeDirectoryForCurrentUser.path]
        } else {
            searchRoots = [fileManager.currentDirectoryPath]
        }

        let verboseLogger: (@Sendable (String) -> Void)?
        if verbose && !quiet {
            verboseLogger = { message in print(style.gray("[verbose] \(message)")) }
        } else {
            verboseLogger = nil
        }

        if !quiet {
            let modeBadge = dryRun ? " \(style.yellow(style.bold("[dry-run]")))" : ""
            print("\(style.heading("pspm migrate"))\(modeBadge)")
        }

        let manager = MigrationManager()
        let options = MigrationOptions(
            searchRoots: searchRoots,
            dryRun: dryRun,
            deduplicate: deduplicate,
            maxDepth: maxDepth,
            excludePatterns: exclude,
            includeGitWorktreeDiscovery: true,
            installRepoHooks: installHooks,
            verboseLogger: verboseLogger
        )

        let isQuiet = quiet
        let isDryRun = dryRun
        let isDedup = deduplicate

        let report = try manager.migrate(options: options) { event in
            guard !isQuiet else { return }
            switch event {
            case .scanning(let root):
                if style.isEnabled {
                    let line = style.stepRunning("Scanning \(style.path(root))...")
                    FileHandle.standardOutput.write(Data("\r\u{1B}[2K\(line)".utf8))
                    fflush(Darwin.stdout)
                } else {
                    print(style.stepRunning("Scanning \(root)..."))
                }
            case .discovered:
                break
            case .processing(let projectRoot, let type):
                if style.isEnabled {
                    let line = style.stepRunning("Inspecting \(type.rawValue) at \(style.path(projectRoot))...")
                    FileHandle.standardOutput.write(Data("\r\u{1B}[2K\(line)".utf8))
                    fflush(Darwin.stdout)
                }
            case .completed(let outcome):
                if style.isEnabled {
                    FileHandle.standardOutput.write(Data("\r\u{1B}[2K".utf8))
                }
                Self.printOutcome(outcome, dryRun: isDryRun, deduplicate: isDedup, style: style)
            }
        }

        guard !quiet else { return }

        if style.isEnabled {
            FileHandle.standardOutput.write(Data("\r\u{1B}[2K".utf8))
        }

        print("")
        printSummary(report, style: style)
    }

    private static func printOutcome(
        _ outcome: MigratedProjectOutcome,
        dryRun: Bool,
        deduplicate: Bool,
        style: TerminalStyle
    ) {
        let label = "[\(outcome.project.type.rawValue)] \(style.path(outcome.project.rootPath))"

        if let reason = outcome.skippedReason {
            print(style.stepWarning(label, detail: style.gray("(\(reason))")))
            return
        }

        let sizeText = formatBytes(outcome.existingCacheBytes)
        if !outcome.hasExistingCache && !outcome.recordedFlutterResolved && !outcome.installedRepoHook {
            print(style.stepSkipped(label, detail: "no existing SourcePackages/.build cache"))
            return
        }

        var parts: [String] = []
        if outcome.hasExistingCache {
            if dryRun {
                parts.append("cache: \(sizeText)")
            } else {
                parts.append("harvested \(outcome.totalHarvestedItemsCount) item(s) (\(sizeText))")
            }
        }
        if deduplicate && !dryRun && outcome.totalDeduplicatedItemsCount > 0 {
            parts.append("deduplicated \(outcome.totalDeduplicatedItemsCount) via CoW (\(formatBytes(outcome.estimatedReclaimedBytes)))")
        }
        if outcome.skippedLocallyModifiedCount > 0 {
            parts.append("\(outcome.skippedLocallyModifiedCount) dirty skipped")
        }
        if outcome.recordedFlutterResolved {
            parts.append("Flutter Package.resolved cached")
        }
        if outcome.installedRepoHook {
            parts.append("hook enabled")
        }

        print(style.stepSuccess(label, detail: style.gray("(\(parts.joined(separator: ", ")))")))
    }

    private func printSummary(_ report: MigrationReport, style: TerminalStyle) {
        let prefix = report.dryRun ? "\(style.yellow(style.bold("[dry-run]"))) " : ""
        print("\(prefix)\(style.heading("Migration Summary"))")
        print("  \(style.dim("Projects found:"))        \(style.bold("\(report.discoveredCount)")) \(style.dim("(\(report.projectsWithExistingCacheCount) with existing cache)"))")
        print("  \(style.dim("Existing cache size:"))   \(style.bold(formatBytes(report.totalExistingCacheBytes)))")

        if !report.dryRun {
            print("  \(style.dim("Items harvested:"))       \(style.bold("\(report.totalHarvestedItemsCount)"))")
        }

        if report.deduplicate {
            let label = report.dryRun ? "Est. reclaimable CoW:  " : "Deduplicated via CoW:  "
            print("  \(style.dim(label))\(style.green(style.bold(Self.formatBytes(report.totalEstimatedReclaimedBytes))))")
        }

        print("")
        var tips: [String] = []
        if report.dryRun && report.projectsWithExistingCacheCount > 0 {
            let dedupFlag = report.deduplicate ? " --deduplicate" : ""
            let scopeArg = home ? " --home" : (path.map { " \($0)" } ?? "")
            tips.append(style.formatInlineCode(
                "Run `pspm migrate\(scopeArg)\(dedupFlag)` without `--dry-run` to apply migration.",
                baseCodes: ["90"],
                codeCodes: ["90", "1"]
            ))
        } else if !report.deduplicate && report.totalExistingCacheBytes > 0 {
            let scopeArg = home ? " --home" : (path.map { " \($0)" } ?? "")
            tips.append(style.formatInlineCode(
                "Re-run with `pspm migrate\(scopeArg) --deduplicate` to replace duplicated caches with APFS CoW clones and reclaim disk space.",
                baseCodes: ["90"],
                codeCodes: ["90", "1"]
            ))
        }
        if !report.dryRun && report.migratedCount > 0 {
            tips.append(style.formatInlineCode(
                "Inspect global store savings anytime with `pspm store status`.",
                baseCodes: ["90"],
                codeCodes: ["90", "1"]
            ))
        }

        if !tips.isEmpty {
            print(style.tipItalic("Tips:"))
            for tip in tips {
                print("  \(style.tip("›")) \(tip)")
            }
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        Self.formatBytes(bytes)
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(clamping: bytes))
    }
}

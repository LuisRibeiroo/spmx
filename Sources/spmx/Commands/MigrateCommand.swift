import ArgumentParser
import Darwin
import Foundation
import SPMXCore

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
        name: [.long, .customLong("execute"), .customLong("no-dry-run")],
        help: "Apply the migration (harvest into store and deduplicate via APFS CoW). Defaults to dry-run preview."
    )
    var apply: Bool = false

    @Flag(
        name: .long,
        help: "Preview discovered projects and estimated space savings without modifying files (default)."
    )
    var dryRun: Bool = false

    @Flag(
        inversion: .prefixedNo,
        exclusivity: .exclusive,
        help: "Replace clean SourcePackages/.build entries with APFS Copy-on-Write clones after harvesting (enabled by default; pass --no-deduplicate to harvest only)."
    )
    var deduplicate: Bool = true

    @Flag(
        name: .long,
        help: "Only harvest packages into the global store without deduplicating existing project caches."
    )
    var harvestOnly: Bool = false

    @Flag(
        name: .long,
        help: "Install repo-local spmx post-checkout hooks in discovered Git repositories."
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

    @Option(
        name: .long,
        help: "Inactivity timeout in seconds for each external subcommand (defaults to 30s; 0 disables; resets on output or completion)."
    )
    var timeout: Double?

    @Flag(name: .shortAndLong, help: "Print verbose details for each scanned path.")
    var verbose: Bool = false

    @Flag(name: .shortAndLong, help: "Suppress normal output.")
    var quiet: Bool = false

    func validate() throws {
        if let timeout, timeout < 0 {
            throw ValidationError("--timeout must be >= 0.")
        }
    }

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

        let spinner = TerminalSpinner(style: style)
        defer { spinner.stop() }

        let verboseLogger: (@Sendable (String) -> Void)?
        if verbose && !quiet {
            verboseLogger = { message in
                spinner.suspendForOutput {
                    print(style.gray("[verbose] \(message)"))
                }
            }
        } else {
            verboseLogger = nil
        }

        let isDryRun = dryRun || !apply
        let isDedup = deduplicate && !harvestOnly
        let isQuiet = quiet
        let resolvedTimeout = CommandExecutor.resolveDefaultTimeout(override: timeout)
        let startedAt = Date()

        let canonicalScopeRoots = searchRoots.map {
            DerivedDataPathCalculator.canonicalizePath($0, currentDirectory: fileManager.currentDirectoryPath)
        }
        let homePath = fileManager.homeDirectoryForCurrentUser.standardizedFileURL.resolvingSymlinksInPath().path

        if !isQuiet {
            let modeBadge = isDryRun ? " \(style.dryRunBadge())" : ""
            print("\(style.heading("spmx migrate"))\(modeBadge)")
            print(style.scopeLine(canonicalScopeRoots.joined(separator: ", ")))
            print("")
            let sectionTitle = isDryRun ? "Inspecting projects:" : "Migrating projects:"
            print(style.section(sectionTitle))
        }

        let manager = MigrationManager()
        let options = MigrationOptions(
            searchRoots: searchRoots,
            dryRun: isDryRun,
            deduplicate: isDedup,
            maxDepth: maxDepth,
            excludePatterns: exclude,
            includeGitWorktreeDiscovery: true,
            installRepoHooks: installHooks,
            commandTimeout: resolvedTimeout,
            verboseLogger: verboseLogger
        )

        let report = try manager.migrate(options: options) { event in
            guard !isQuiet else { return }
            switch event {
            case .scanning:
                spinner.start(message: "", detail: "scanning worktrees & projects")
            case .discovered:
                break
            case .processing(let projectRoot, let type):
                let displayTarget = Self.displayPath(projectRoot, relativeTo: canonicalScopeRoots, homePath: homePath)
                spinner.update(message: "\(displayTarget) [\(type.rawValue)]", detail: "checking")
            case .stage(_, _, let detail):
                spinner.update(detail: detail)
            case .completed(let outcome):
                spinner.finishItem {
                    Self.printOutcome(
                        outcome,
                        relativeTo: canonicalScopeRoots,
                        homePath: homePath,
                        dryRun: isDryRun,
                        deduplicate: isDedup,
                        style: style
                    )
                }
            }
        }

        spinner.stop()
        guard !quiet else { return }

        print("")
        printSummary(report, duration: Date().timeIntervalSince(startedAt), style: style)
    }

    private static func displayPath(
        _ rawPath: String,
        relativeTo scopeRoots: [String],
        homePath: String
    ) -> String {
        let standardized = URL(fileURLWithPath: rawPath).standardizedFileURL.resolvingSymlinksInPath().path
        for root in scopeRoots {
            let resolvedRoot = URL(fileURLWithPath: root).standardizedFileURL.resolvingSymlinksInPath().path
            if standardized == resolvedRoot {
                return scopeRoots.count == 1 ? "." : URL(fileURLWithPath: standardized).lastPathComponent
            }
            let prefix = resolvedRoot == "/" ? "/" : resolvedRoot + "/"
            if standardized.hasPrefix(prefix) {
                return String(standardized.dropFirst(prefix.count))
            }
        }
        if standardized == homePath {
            return "~"
        }
        if standardized.hasPrefix(homePath + "/") {
            return "~/" + standardized.dropFirst(homePath.count + 1)
        }
        return rawPath
    }

    private static func printOutcome(
        _ outcome: MigratedProjectOutcome,
        relativeTo scopeRoots: [String],
        homePath: String,
        dryRun: Bool,
        deduplicate: Bool,
        style: TerminalStyle
    ) {
        let displayTarget = Self.displayPath(outcome.project.rootPath, relativeTo: scopeRoots, homePath: homePath)
        let typeTag = style.gray("[\(outcome.project.type.rawValue)]")
        let label = "\(style.path(displayTarget)) \(typeTag)"

        if let reason = outcome.skippedReason {
            print(style.stepWarning(label, detail: style.gray("(\(reason))")))
            return
        }

        let sizeText = formatBytes(outcome.existingCacheBytes)
        if !outcome.hasExistingCache && !outcome.recordedFlutterResolved && !outcome.installedRepoHook {
            print(style.stepSkipped("\(displayTarget) [\(outcome.project.type.rawValue)]", detail: "no cache"))
            return
        }

        var parts: [String] = []
        if outcome.hasExistingCache {
            if dryRun {
                parts.append(style.primary(sizeText))
            } else {
                parts.append("\(style.primary(sizeText)) \(style.gray("(harvested \(outcome.totalHarvestedItemsCount)"))")
            }
        }
        if deduplicate && !dryRun && outcome.totalDeduplicatedItemsCount > 0 {
            let prefix = outcome.hasExistingCache ? "" : "("
            parts.append("\(prefix)\(style.gray("CoW \(outcome.totalDeduplicatedItemsCount) · \(formatBytes(outcome.estimatedReclaimedBytes)))"))")
        } else if outcome.hasExistingCache && !dryRun {
            parts[parts.count - 1] += style.gray(")")
        }
        if outcome.skippedLocallyModifiedCount > 0 {
            parts.append(style.yellow("\(outcome.skippedLocallyModifiedCount) dirty skipped"))
        }
        if outcome.recordedFlutterResolved {
            parts.append(style.gray("Flutter Package.resolved cached"))
        }
        if outcome.installedRepoHook {
            parts.append(style.gray("hook enabled"))
        }

        print("  \(style.addIcon) \(label)  \(parts.joined(separator: style.gray(", ")))")
    }

    private func printSummary(_ report: MigrationReport, duration: TimeInterval, style: TerminalStyle) {
        let prefix = report.dryRun ? "\(style.dryRunBadge()) " : ""
        print("\(prefix)\(style.section("Summary:"))")
        print("  \(style.gray("Projects:"))       \(style.primaryBold("\(report.discoveredCount)")) \(style.gray("scanned,")) \(style.primaryBold("\(report.projectsWithExistingCacheCount)")) \(style.gray("with cache"))")
        print("  \(style.gray("Cache size:"))     \(style.bold(formatBytes(report.totalExistingCacheBytes)))")

        if !report.dryRun {
            print("  \(style.gray("Harvested:"))      \(style.primaryBold("\(report.totalHarvestedItemsCount)")) \(style.gray("item(s)"))")
        }

        if report.deduplicate {
            let label = report.dryRun ? "Reclaimable:    " : "Reclaimed:      "
            print("  \(style.gray(label))\(style.green(style.bold(Self.formatBytes(report.totalEstimatedReclaimedBytes)))) \(style.gray("(via APFS CoW)"))")
        }

        print("")
        print(style.doneIn(seconds: duration))

        var tips: [String] = []
        if report.dryRun && report.projectsWithExistingCacheCount > 0 {
            let modeSuffix = report.deduplicate ? "" : " --no-deduplicate"
            let scopeArg = home ? " --home" : (path.map { " \($0)" } ?? "")
            tips.append(style.formatInlineCode(
                "Run `spmx migrate\(scopeArg) --apply\(modeSuffix)` to apply migration.",
                baseCodes: ["90"],
                codeCodes: ["90", "1"]
            ))
        } else if !report.deduplicate && report.totalExistingCacheBytes > 0 {
            let scopeArg = home ? " --home" : (path.map { " \($0)" } ?? "")
            tips.append(style.formatInlineCode(
                "Re-run with `spmx migrate\(scopeArg) --apply --deduplicate` to replace duplicated caches with APFS CoW clones and reclaim disk space.",
                baseCodes: ["90"],
                codeCodes: ["90", "1"]
            ))
        }
        if !report.dryRun && report.migratedCount > 0 {
            tips.append(style.formatInlineCode(
                "Inspect global store savings anytime with `spmx store status`.",
                baseCodes: ["90"],
                codeCodes: ["90", "1"]
            ))
        }

        if !tips.isEmpty {
            print("")
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

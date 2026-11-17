import ArgumentParser
import Foundation
import SPMXCore

struct LinkCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "link",
        abstract: "Link a project or scan the machine to harvest and deduplicate SwiftPM caches into the global store."
    )

    @Argument(help: "Project or directory path to link and scan (defaults to entire machine under ~).")
    var path: String?

    @Flag(
        name: [.short, .long],
        help: "Skip the interactive confirmation prompt and proceed immediately."
    )
    var yes: Bool = false

    @Flag(
        name: .long,
        help: "Preview discovered projects and estimated space savings without modifying files."
    )
    var dryRun: Bool = false

    @Flag(
        inversion: .prefixedNo,
        exclusivity: .exclusive,
        help: "Replace clean SourcePackages/.build entries with APFS Copy-on-Write clones after harvesting (enabled by default)."
    )
    var deduplicate: Bool = true

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
        help: "Inactivity timeout in seconds for each external subcommand (defaults to 30s; 0 disables)."
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
        try LinkRunner.execute(
            path: path,
            dryRun: dryRun,
            yes: yes,
            deduplicate: deduplicate,
            installHooks: installHooks,
            maxDepth: maxDepth,
            exclude: exclude,
            timeout: timeout,
            verbose: verbose,
            quiet: quiet,
            commandName: "spmx link"
        )
    }
}

enum LinkRunner {
    static func execute(
        path: String?,
        dryRun: Bool,
        yes: Bool,
        deduplicate: Bool,
        installHooks: Bool,
        maxDepth: Int,
        exclude: [String],
        timeout: Double?,
        verbose: Bool,
        quiet: Bool,
        commandName: String
    ) throws {
        let style = TerminalStyle.stdout
        let fileManager = FileManager.default

        let searchRoots: [String]
        let isDirectProjectTarget: Bool
        if let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let canonical = DerivedDataPathCalculator.canonicalizePath(path, currentDirectory: fileManager.currentDirectoryPath)
            searchRoots = [canonical]
            isDirectProjectTarget = (try? ProjectDetector.detect(in: canonical, fileManager: fileManager)) != nil
        } else {
            searchRoots = [fileManager.homeDirectoryForCurrentUser.path]
            isDirectProjectTarget = false
        }

        let resolvedTimeout = CommandExecutor.resolveDefaultTimeout(override: timeout)
        let startedAt = Date()
        let canonicalScopeRoots = searchRoots.map {
            DerivedDataPathCalculator.canonicalizePath($0, currentDirectory: fileManager.currentDirectoryPath)
        }
        let homePath = fileManager.homeDirectoryForCurrentUser.standardizedFileURL.resolvingSymlinksInPath().path

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

        if !quiet {
            let modeBadge = dryRun ? " \(style.dryRunBadge())" : ""
            print("\(style.heading(commandName))\(modeBadge)")
            print(style.scopeLine(canonicalScopeRoots.joined(separator: ", ")))
            print("")
            print(style.section("Scanning projects:"))
        }

        let manager = MigrationManager()
        let previewOptions = MigrationOptions(
            searchRoots: searchRoots,
            dryRun: true,
            deduplicate: deduplicate,
            maxDepth: maxDepth,
            excludePatterns: exclude,
            includeGitWorktreeDiscovery: true,
            installRepoHooks: installHooks,
            includeExcluded: isDirectProjectTarget,
            commandTimeout: resolvedTimeout,
            verboseLogger: verboseLogger
        )

        let previewReport = try manager.migrate(options: previewOptions) { event in
            guard !quiet else { return }
            switch event {
            case .scanning:
                spinner.start(message: "", detail: "scanning projects & DerivedData")
            case .discovered:
                break
            case .processing(let projectRoot, let type):
                let displayTarget = displayPath(projectRoot, relativeTo: canonicalScopeRoots, homePath: homePath)
                spinner.update(message: "\(displayTarget) [\(type.rawValue)]", detail: "measuring")
            case .stage(_, _, let detail):
                spinner.update(detail: detail)
            case .completed(let outcome):
                spinner.finishItem {
                    printOutcome(
                        outcome,
                        relativeTo: canonicalScopeRoots,
                        homePath: homePath,
                        dryRun: true,
                        deduplicate: deduplicate,
                        style: style
                    )
                }
            }
        }
        spinner.stop()

        if !quiet {
            print("")
            printPlanSummary(previewReport, style: style)
        }

        if dryRun || previewReport.discoveredCount == 0 {
            if !quiet {
                print("")
                print(style.doneIn(seconds: Date().timeIntervalSince(startedAt)))
            }
            return
        }

        if !yes {
            let count = previewReport.discoveredCount
            let noun = count == 1 ? "project" : "projects"
            print("")
            print("Proceed with linking and deduplicating \(count) \(noun)? [y/N] ", terminator: "")
            fflush(stdout)
            let answer = (readLine() ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard answer == "y" || answer == "yes" else {
                if !quiet {
                    print(style.gray("Aborted. No files were modified."))
                }
                return
            }
        }

        if !quiet {
            print("")
            print(style.section("Linking and deduplicating:"))
        }

        let applyOptions = MigrationOptions(
            searchRoots: searchRoots,
            dryRun: false,
            deduplicate: deduplicate,
            maxDepth: maxDepth,
            excludePatterns: exclude,
            includeGitWorktreeDiscovery: true,
            installRepoHooks: installHooks,
            includeExcluded: isDirectProjectTarget,
            commandTimeout: resolvedTimeout,
            verboseLogger: verboseLogger
        )

        let applyReport = try manager.migrate(options: applyOptions) { event in
            guard !quiet else { return }
            switch event {
            case .scanning:
                spinner.start(message: "", detail: "linking projects")
            case .discovered:
                break
            case .processing(let projectRoot, let type):
                let displayTarget = displayPath(projectRoot, relativeTo: canonicalScopeRoots, homePath: homePath)
                spinner.update(message: "\(displayTarget) [\(type.rawValue)]", detail: "harvesting & cloning")
            case .stage(_, _, let detail):
                spinner.update(detail: detail)
            case .completed(let outcome):
                spinner.finishItem {
                    printOutcome(
                        outcome,
                        relativeTo: canonicalScopeRoots,
                        homePath: homePath,
                        dryRun: false,
                        deduplicate: deduplicate,
                        style: style
                    )
                }
            }
        }
        spinner.stop()

        if !quiet {
            print("")
            printAppliedSummary(applyReport, duration: Date().timeIntervalSince(startedAt), style: style)
        }
    }

    static func displayPath(
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
        let displayTarget = displayPath(outcome.project.rootPath, relativeTo: scopeRoots, homePath: homePath)
        let typeTag = style.gray("[\(outcome.project.type.rawValue)]")
        let label = "\(style.path(displayTarget)) \(typeTag)"

        if let reason = outcome.skippedReason {
            print(style.stepWarning(label, detail: style.gray("(\(reason))")))
            return
        }

        let sizeText = formatBytes(outcome.existingCacheBytes)
        if !outcome.hasExistingCache && !outcome.recordedFlutterResolved && !outcome.installedRepoHook {
            print(style.stepSkipped("\(displayTarget) [\(outcome.project.type.rawValue)]", detail: "no local cache"))
            return
        }

        var parts: [String] = []
        if outcome.hasExistingCache {
            if dryRun {
                parts.append("\(style.primary(sizeText)) \(style.gray("(est. saved: \(formatBytes(outcome.estimatedReclaimedBytes)))"))")
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

        print("  \(style.addIcon) \(label)  \(parts.joined(separator: style.gray(", ")))")
    }

    private static func printPlanSummary(_ report: MigrationReport, style: TerminalStyle) {
        print(style.section("Plan:"))
        print("  \(style.gray("Projects found:"))    \(style.primaryBold("\(report.discoveredCount)")) \(style.gray("(\(report.projectsWithExistingCacheCount) with local cache)"))")
        print("  \(style.gray("Local cache size:"))  \(style.bold(formatBytes(report.totalExistingCacheBytes)))")
        if report.deduplicate {
            print("  \(style.gray("Est. disk saved:"))   \(style.green(style.bold(formatBytes(report.totalEstimatedReclaimedBytes)))) \(style.gray("(via APFS CoW)"))")
        }
    }

    private static func printAppliedSummary(_ report: MigrationReport, duration: TimeInterval, style: TerminalStyle) {
        print(style.section("Summary:"))
        print("  \(style.gray("Projects linked:"))   \(style.primaryBold("\(report.discoveredCount)"))")
        print("  \(style.gray("Harvested:"))         \(style.primaryBold("\(report.totalHarvestedItemsCount)")) \(style.gray("item(s)"))")
        if report.deduplicate {
            print("  \(style.gray("Reclaimed:"))         \(style.green(style.bold(formatBytes(report.totalEstimatedReclaimedBytes)))) \(style.gray("(via APFS CoW)"))")
        }
        print("")
        print(style.doneIn(seconds: duration))
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(clamping: bytes))
    }
}

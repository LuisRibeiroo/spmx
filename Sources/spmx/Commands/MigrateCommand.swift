import ArgumentParser
import Darwin
import Foundation
import SPMXCore

struct MigrateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migrate",
        abstract: "Scan directories or worktrees for existing projects and migrate their SwiftPM caches to the global store."
    )

    @Argument(help: "Directory to scan for Flutter, Xcode, and SwiftPM projects (defaults to entire machine under ~).")
    var path: String?

    @Flag(
        name: [.long, .customLong("all")],
        help: "Scan the home directory (~) for existing projects and Git worktrees."
    )
    var home: Bool = false

    @Flag(
        name: [.short, .long],
        help: "Skip the interactive confirmation prompt and apply migration immediately."
    )
    var yes: Bool = false

    @Flag(
        name: [.long, .customLong("execute"), .customLong("no-dry-run")],
        help: "Apply the migration (harvest into store and deduplicate via APFS CoW) without prompting."
    )
    var apply: Bool = false

    @Flag(
        name: .long,
        help: "Preview discovered projects and estimated space savings without modifying files."
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
        let effectivePath: String?
        if let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            effectivePath = path
        } else {
            effectivePath = nil
        }

        try LinkRunner.execute(
            path: effectivePath,
            dryRun: dryRun,
            yes: yes || apply,
            deduplicate: deduplicate && !harvestOnly,
            installHooks: installHooks,
            maxDepth: maxDepth,
            exclude: exclude,
            timeout: timeout,
            verbose: verbose,
            quiet: quiet,
            commandName: "spmx migrate"
        )
    }
}

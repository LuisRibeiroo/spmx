import ArgumentParser
import Foundation
import SPMXCore

struct PruneCommand: ParsableCommand {
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
        help: "Enable automatic prune reminders on explicit spmx commands (defaults to every 30 days)."
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
            commandName: "spmx prune",
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

struct PruneAutoCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "auto",
        abstract: "Enable, disable, or configure the interval for automatic store prune reminders.",
        subcommands: [
            Enable.self,
            Disable.self,
            Status.self
        ],
        defaultSubcommand: Status.self
    )

    struct Enable: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "enable",
            abstract: "Enable periodic prune reminders on explicit spmx commands (default: every 30 days)."
        )

        @Option(
            name: [.long, .customLong("every")],
            help: "Reminder interval in days (default: 30)."
        )
        var days: Int = StoreIndex.AutoPruneConfig.defaultIntervalDays

        @Flag(
            name: .long,
            help: "Output machine-readable JSON."
        )
        var json: Bool = false

        func validate() throws {
            if days < 1 {
                throw ValidationError("--days must be 1 or greater (use `spmx prune auto disable` to turn off reminders).")
            }
        }

        func run() throws {
            try PruneRunner.execute(
                commandName: "spmx prune auto",
                dryRun: false,
                olderThan: 30,
                autoEvery: days,
                enableAuto: true,
                disableAuto: false,
                statusOnly: true,
                json: json
            )
        }
    }

    struct Disable: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "disable",
            abstract: "Disable periodic prune reminders."
        )

        @Flag(
            name: .long,
            help: "Output machine-readable JSON."
        )
        var json: Bool = false

        func run() throws {
            try PruneRunner.execute(
                commandName: "spmx prune auto",
                dryRun: false,
                olderThan: 30,
                autoEvery: nil,
                enableAuto: false,
                disableAuto: true,
                statusOnly: true,
                json: json
            )
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show current automatic prune configuration and last prune timestamp."
        )

        @Flag(
            name: .long,
            help: "Output machine-readable JSON."
        )
        var json: Bool = false

        func run() throws {
            try PruneRunner.execute(
                commandName: "spmx prune auto",
                dryRun: false,
                olderThan: 30,
                autoEvery: nil,
                enableAuto: false,
                disableAuto: false,
                statusOnly: true,
                json: json
            )
        }
    }
}

enum PruneRunner {
    static func validate(
        olderThan: Int,
        autoEvery: Int?,
        enableAuto: Bool,
        disableAuto: Bool
    ) throws {
        if olderThan < 0 {
            throw ValidationError("--older-than must be zero or greater.")
        }
        if let autoEvery, autoEvery < 0 {
            throw ValidationError("--auto-every must be zero or greater.")
        }
        if enableAuto && disableAuto {
            throw ValidationError("Cannot pass both --enable-auto and --disable-auto.")
        }
    }

    static func execute(
        commandName: String,
        dryRun: Bool,
        olderThan: Int,
        autoEvery: Int?,
        enableAuto: Bool,
        disableAuto: Bool,
        statusOnly: Bool,
        json: Bool
    ) throws {
        let store = GlobalStore()
        let manager = StoreManager(store: store)
        let style = TerminalStyle.stdout

        let isConfigMutation = autoEvery != nil || enableAuto || disableAuto
        if isConfigMutation {
            let newEnabled: Bool?
            if disableAuto || autoEvery == 0 {
                newEnabled = false
            } else if enableAuto || (autoEvery ?? 0) > 0 {
                newEnabled = true
            } else {
                newEnabled = nil
            }
            let effectiveInterval = autoEvery ?? (enableAuto ? StoreIndex.AutoPruneConfig.defaultIntervalDays : nil)
            _ = try store.configureAutoPrune(
                enabled: newEnabled,
                intervalDays: effectiveInterval
            )
        }

        if statusOnly || isConfigMutation {
            let evaluation = try manager.evaluateAutoPrune()
            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(evaluation)
                if let text = String(data: data, encoding: .utf8) {
                    print(text)
                }
                return
            }

            printAutoPruneStatus(evaluation, heading: commandName, style: style)
            return
        }

        let startedAt = Date()
        let report = try manager.prune(
            options: PruneOptions(dryRun: dryRun, olderThanDays: olderThan)
        )

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            if let text = String(data: data, encoding: .utf8) {
                print(text)
            }
            return
        }

        let prefix = report.dryRun ? "\(style.dryRunBadge()) " : ""
        print("\(prefix)\(style.heading(commandName)) \(style.gray("(older than \(olderThan) day(s))"))")
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

        if let evaluation = try? manager.evaluateAutoPrune() {
            print("")
            print(style.tipItalic("Tips:"))
            if evaluation.enabled {
                print("  \(style.tip("›")) \(style.tip("Auto-prune reminders are active (every \(evaluation.intervalDays) day(s))."))")
                print("    \(style.tip("Change interval:")) \(style.tipCommand("`spmx prune auto enable --days <n>`")) \(style.tip("· Disable:")) \(style.tipCommand("`spmx prune auto disable`"))")
            } else {
                print("  \(style.tip("›")) \(style.tip("Auto-Prune (disabled by default): remind to clean unused packages every 30 days:"))")
                print("      \(style.tipCommand("`spmx prune auto enable`")) \(style.tip("(or customize with `--days <n>`)"))")
            }
        }
    }

    private static func printAutoPruneStatus(
        _ evaluation: AutoPruneEvaluation,
        heading: String,
        style: TerminalStyle
    ) {
        print(style.heading(heading))
        print("")
        let stateBadge = evaluation.enabled
            ? style.green(style.bold("enabled"))
            : style.yellow(style.bold("disabled"))
        print("  \(style.gray("Auto-prune reminder:")) \(stateBadge) \(style.gray("(every \(evaluation.intervalDays) day(s))"))")
        if let lastPrunedAt = evaluation.lastPrunedAt {
            let formatter = ISO8601DateFormatter()
            let daysText = evaluation.daysSinceLastPrune.map { " (\($0) day(s) ago)" } ?? ""
            print("  \(style.gray("Last pruned at:"))      \(formatter.string(from: lastPrunedAt))\(style.gray(daysText))")
        } else {
            print("  \(style.gray("Last pruned at:"))      \(style.gray("never"))")
        }
        if evaluation.isDue {
            print("  \(style.warningIcon) \(style.yellow("Prune is due — run `spmx prune` to clean unreferenced entries."))")
        }
        print("")
        print(style.tipItalic("Tips:"))
        if evaluation.enabled {
            print("  \(style.tip("›")) \(style.tip("Change interval:")) \(style.tipCommand("`spmx prune auto enable --days <n>`"))")
            print("  \(style.tip("›")) \(style.tip("Disable reminders:")) \(style.tipCommand("`spmx prune auto disable`"))")
        } else {
            print("  \(style.tip("›")) \(style.tip("Enable reminders (default 30 days):")) \(style.tipCommand("`spmx prune auto enable`"))")
            print("  \(style.tip("›")) \(style.tip("Custom interval:")) \(style.tipCommand("`spmx prune auto enable --days 15`"))")
        }
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))))
    }
}

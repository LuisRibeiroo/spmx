import ArgumentParser
import Foundation
import PSPMCore

struct HydrateArguments: ParsableArguments {
    @Argument(
        help: "Path to a project directory, .xcworkspace, .xcodeproj, or Package.swift (defaults to current directory)."
    )
    var path: String = "."

    @Option(
        name: .long,
        help: "Explicit path to a .xcodeproj, Package.swift, or project directory."
    )
    var project: String?

    @Option(
        name: .long,
        help: "Explicit path to a .xcworkspace."
    )
    var workspace: String?

    @Option(
        name: .long,
        help: "Override the target SourcePackages (or .build) directory path."
    )
    var sourcePackages: String?

    @Flag(
        name: .long,
        help: "Overwrite existing checkouts, artifacts, and prebuilts even if already present or modified."
    )
    var force: Bool = false

    @Option(
        name: .long,
        help: "Inactivity timeout in seconds for each external subcommand (defaults to 30s; 0 disables; resets on output or completion)."
    )
    var timeout: Double?

    @Flag(
        name: [.short, .long],
        help: "Suppress standard output."
    )
    var quiet: Bool = false

    @Flag(
        name: [.short, .long],
        help: "Print detailed hydration diagnostics."
    )
    var verbose: Bool = false

    func validate() throws {
        if project != nil && workspace != nil {
            throw ValidationError("Cannot specify both --project and --workspace.")
        }
        if let timeout, timeout < 0 {
            throw ValidationError("--timeout must be >= 0.")
        }
        if quiet && verbose {
            throw ValidationError("Cannot specify both --quiet and --verbose.")
        }
    }
}

struct HydrateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hydrate",
        abstract: "Populate SourcePackages (or .build) from the global pspm store using APFS CoW clones."
    )

    @OptionGroup
    var arguments: HydrateArguments

    func run() throws {
        try Self.execute(with: arguments)
    }

    static func execute(with arguments: HydrateArguments) throws {
        var detected = try ProjectDetector.detect(
            in: arguments.path,
            projectPath: arguments.project,
            workspacePath: arguments.workspace
        )

        let startedAt = Date()
        let style = TerminalStyle.stdout
        let spinner = TerminalSpinner(style: style)
        defer { spinner.stop() }

        let verboseLogger: (@Sendable (String) -> Void)?
        if arguments.verbose && !arguments.quiet {
            verboseLogger = { message in
                spinner.suspendForOutput {
                    print(style.gray("[verbose] \(message)"))
                }
            }
        } else {
            verboseLogger = nil
        }

        let resolvedTimeout = CommandExecutor.resolveDefaultTimeout(override: arguments.timeout)
        let cloner = APFSCloner(verboseLogger: verboseLogger)
        let store = GlobalStore(cloner: cloner)

        if !arguments.quiet {
            print("\(style.heading("pspm hydrate")) \(style.gray("[\(detected.type.rawValue)]"))")
            print(style.scopeLine(detected.rootPath))
            if style.isEnabled {
                let shortName = URL(fileURLWithPath: detected.rootPath).lastPathComponent
                spinner.start(message: "\(shortName) [\(detected.type.rawValue)]", detail: "preparing")
            }
        }

        if detected.type == .flutter {
            let flutterIntegrator = FlutterSPMIntegrator(
                store: store,
                commandRunner: ProcessFlutterCommandRunner(timeout: resolvedTimeout)
            )
            if flutterIntegrator.isFlutterSPMProject(detected) {
                if !arguments.quiet && style.isEnabled {
                    spinner.update(detail: "preparing Flutter Package.resolved")
                }
                let flutterResult = try flutterIntegrator.prepareForHydration(project: detected)
                detected = flutterResult.project
            }
        }

        let engine = PackageSyncEngine(store: store)
        let progressHandler: (@Sendable (String) -> Void)?
        if !arguments.quiet && style.isEnabled {
            progressHandler = { detail in spinner.update(detail: detail) }
        } else {
            progressHandler = nil
        }

        let options = HydrateOptions(
            sourcePackagesOverride: arguments.sourcePackages,
            force: arguments.force,
            commandTimeout: resolvedTimeout,
            progressHandler: progressHandler,
            verboseLogger: verboseLogger
        )

        let result = try engine.hydrate(project: detected, options: options)
        spinner.stop()
        guard !arguments.quiet else { return }

        printSummary(result, duration: Date().timeIntervalSince(startedAt), verbose: arguments.verbose, style: style)
    }

    private static func printSummary(
        _ result: HydrateResult,
        duration: TimeInterval,
        verbose: Bool,
        style: TerminalStyle
    ) {
        print("  \(style.gray("Target:")) \(result.sourcePackagesURL.path)")
        print("")

        let wsState = result.workspaceStateURL != nil
            ? (result.didUpdateWorkspaceState ? "updated" : "unchanged")
            : "none"
        print("\(style.gray("Progress:")) checkouts \(style.primaryBold("\(result.hydratedCheckouts.count)")) \(style.gray("cloned")), \(style.gray("\(result.skippedCheckouts.count) skipped")), artifacts \(style.primaryBold("\(result.hydratedArtifacts.count)")), prebuilts \(style.primaryBold("\(result.hydratedPrebuilts.count)")), workspace-state \(style.gray(wsState))")

        if verbose {
            print("")
            print(style.section("packages:"))
            if let toolchainHash = result.toolchainHash {
                print("  \(style.gray("toolchain:")) \(style.italic(style.gray(toolchainHash)))")
            }
            for item in result.hydratedCheckouts {
                print("  \(style.addIcon) \(item.identity) \(style.gray("\(item.revision.prefix(8)) (\(item.cloneMethod.rawValue))"))")
            }
            for item in result.skippedCheckouts {
                print("  \(style.skippedIcon) \(style.gray("\(item.identity) (\(item.reason.rawValue))"))")
            }
            for item in result.hydratedArtifacts {
                print("  \(style.addIcon) \(item.identity)/\(item.targetName) \(style.gray("(\(item.cloneMethod.rawValue))"))")
            }
            for item in result.hydratedPrebuilts {
                print("  \(style.addIcon) \(item.identity) \(style.gray("\(item.versionOrChecksum) (\(item.cloneMethod.rawValue))"))")
            }
        }

        print("")
        print(style.doneIn(seconds: duration))
    }
}

struct InstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Alias for 'pspm hydrate'."
    )

    @OptionGroup
    var arguments: HydrateArguments

    func run() throws {
        try HydrateCommand.execute(with: arguments)
    }
}

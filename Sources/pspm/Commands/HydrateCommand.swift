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

        let style = TerminalStyle.stdout
        let verboseLogger: (@Sendable (String) -> Void)?
        if arguments.verbose {
            verboseLogger = { message in print(style.gray("[verbose] \(message)")) }
        } else {
            verboseLogger = nil
        }

        let cloner = APFSCloner(verboseLogger: verboseLogger)
        let store = GlobalStore(cloner: cloner)

        if detected.type == .flutter {
            let flutterIntegrator = FlutterSPMIntegrator(store: store)
            if flutterIntegrator.isFlutterSPMProject(detected) {
                let flutterResult = try flutterIntegrator.prepareForHydration(project: detected)
                detected = flutterResult.project
            }
        }

        let engine = PackageSyncEngine(store: store)

        let options = HydrateOptions(
            sourcePackagesOverride: arguments.sourcePackages,
            force: arguments.force,
            verboseLogger: verboseLogger
        )

        let result = try engine.hydrate(project: detected, options: options)
        guard !arguments.quiet else { return }

        printSummary(result, verbose: arguments.verbose, style: style)
    }

    private static func printSummary(_ result: HydrateResult, verbose: Bool, style: TerminalStyle) {
        print("\(style.green(style.bold("\(style.successIcon) Hydrated"))) \(style.bold(result.project.type.rawValue)) project at \(style.path(result.project.rootPath))")
        print("  \(style.dim("Target:"))          \(style.path(result.sourcePackagesURL.path))")
        print("  \(style.dim("Checkouts:"))       \(style.bold("\(result.hydratedCheckouts.count)")) cloned, \(style.gray("\(result.skippedCheckouts.count) skipped"))")
        print("  \(style.dim("Artifacts:"))       \(style.bold("\(result.hydratedArtifacts.count)")) cloned")
        print("  \(style.dim("Prebuilts:"))       \(style.bold("\(result.hydratedPrebuilts.count)")) cloned")
        if let wsURL = result.workspaceStateURL {
            let status = result.didUpdateWorkspaceState ? style.green("updated") : style.gray("unchanged")
            print("  \(style.dim("workspace-state:")) \(style.path(wsURL.path)) (\(status))")
        }

        if verbose {
            if let toolchainHash = result.toolchainHash {
                print("  \(style.dim("Toolchain hash:"))  \(style.italic(toolchainHash))")
            }
            for item in result.hydratedCheckouts {
                print("  \(style.green(style.successIcon)) \(style.dim("[checkout+]")) \(style.bold(item.identity))@\(item.revision) \(style.gray("(\(item.cloneMethod.rawValue))")) -> \(style.path(item.destinationURL.path))")
            }
            for item in result.skippedCheckouts {
                print("  \(style.gray(style.skippedIcon)) \(style.gray("[checkout=] \(item.identity) (\(item.reason.rawValue))"))")
            }
            for item in result.hydratedArtifacts {
                print("  \(style.green(style.successIcon)) \(style.dim("[artifact+]")) \(style.bold(item.identity))/\(item.targetName) \(style.gray("(\(item.cloneMethod.rawValue))")) -> \(style.path(item.destinationURL.path))")
            }
            for item in result.hydratedPrebuilts {
                print("  \(style.green(style.successIcon)) \(style.dim("[prebuilt+]")) \(style.bold(item.identity))@\(item.versionOrChecksum) \(style.gray("(\(item.cloneMethod.rawValue))")) -> \(style.path(item.destinationURL.path))")
            }
        }
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

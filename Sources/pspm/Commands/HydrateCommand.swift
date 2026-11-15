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

        let verboseLogger: (@Sendable (String) -> Void)?
        if arguments.verbose {
            verboseLogger = { message in print("[verbose] \(message)") }
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

        printSummary(result, verbose: arguments.verbose)
    }

    private static func printSummary(_ result: HydrateResult, verbose: Bool) {
        print("Hydrated \(result.project.type.rawValue) project at \(result.project.rootPath)")
        print("  Target:          \(result.sourcePackagesURL.path)")
        print("  Checkouts:       \(result.hydratedCheckouts.count) cloned, \(result.skippedCheckouts.count) skipped")
        print("  Artifacts:       \(result.hydratedArtifacts.count) cloned")
        print("  Prebuilts:       \(result.hydratedPrebuilts.count) cloned")
        if let wsURL = result.workspaceStateURL {
            let status = result.didUpdateWorkspaceState ? "updated" : "unchanged"
            print("  workspace-state: \(wsURL.path) (\(status))")
        }

        if verbose {
            if let toolchainHash = result.toolchainHash {
                print("  Toolchain hash:  \(toolchainHash)")
            }
            for item in result.hydratedCheckouts {
                print("  [checkout+] \(item.identity)@\(item.revision) (\(item.cloneMethod.rawValue)) -> \(item.destinationURL.path)")
            }
            for item in result.skippedCheckouts {
                print("  [checkout=] \(item.identity) (\(item.reason.rawValue))")
            }
            for item in result.hydratedArtifacts {
                print("  [artifact+] \(item.identity)/\(item.targetName) (\(item.cloneMethod.rawValue)) -> \(item.destinationURL.path)")
            }
            for item in result.hydratedPrebuilts {
                print("  [prebuilt+] \(item.identity)@\(item.versionOrChecksum) (\(item.cloneMethod.rawValue)) -> \(item.destinationURL.path)")
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

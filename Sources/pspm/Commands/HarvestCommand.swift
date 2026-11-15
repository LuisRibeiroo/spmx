import ArgumentParser
import Foundation
import PSPMCore

struct HarvestCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "harvest",
        abstract: "Store resolved checkouts, artifacts, and prebuilts from SourcePackages (or .build) into the global pspm store."
    )

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
        help: "Override the source SourcePackages (or .build) directory path."
    )
    var sourcePackages: String?

    @Flag(
        name: [.short, .long],
        help: "Suppress standard output."
    )
    var quiet: Bool = false

    @Flag(
        name: [.short, .long],
        help: "Print detailed harvest diagnostics."
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

    func run() throws {
        let detected = try ProjectDetector.detect(
            in: path,
            projectPath: project,
            workspacePath: workspace
        )

        let style = TerminalStyle.stdout
        let verboseLogger: (@Sendable (String) -> Void)?
        if verbose {
            verboseLogger = { message in print(style.gray("[verbose] \(message)")) }
        } else {
            verboseLogger = nil
        }

        let cloner = APFSCloner(verboseLogger: verboseLogger)
        let store = GlobalStore(cloner: cloner)
        let engine = PackageSyncEngine(store: store)

        let options = HarvestOptions(
            sourcePackagesOverride: sourcePackages,
            verboseLogger: verboseLogger
        )

        let result = try engine.harvest(project: detected, options: options)

        if detected.type == .flutter {
            let flutterIntegrator = FlutterSPMIntegrator(store: store)
            if flutterIntegrator.isFlutterSPMProject(detected) {
                _ = try? flutterIntegrator.recordResolvedDependencies(project: detected)
            }
        }

        guard !quiet else { return }

        print("\(style.green(style.bold("\(style.successIcon) Harvested"))) \(style.bold(result.project.type.rawValue)) project at \(style.path(result.project.rootPath))")
        print("  \(style.dim("Source:"))    \(style.path(result.sourcePackagesURL.path))")
        print("  \(style.dim("Checkouts:")) \(style.bold("\(result.harvestedCheckouts.count)")) inspected")
        print("  \(style.dim("Artifacts:")) \(style.bold("\(result.harvestedArtifacts.count)")) inspected")
        print("  \(style.dim("Prebuilts:")) \(style.bold("\(result.harvestedPrebuilts.count)")) inspected")
        if !result.skippedItems.isEmpty {
            print("  \(style.dim("Skipped:"))   \(style.yellow("\(result.skippedItems.count)")) incomplete/partial item(s)")
        }

        if verbose {
            if let toolchainHash = result.toolchainHash {
                print("  \(style.dim("Toolchain hash:")) \(style.italic(toolchainHash))")
            }
            for item in result.harvestedCheckouts {
                let state = item.alreadyCached ? style.gray("cached") : style.green("stored (\(item.cloneMethod?.rawValue ?? "ok"))")
                let icon = item.alreadyCached ? style.gray(style.skippedIcon) : style.green(style.successIcon)
                print("  \(icon) \(style.dim("[checkout]")) \(style.bold(item.identity))@\(item.revision) -> \(state)")
            }
            for item in result.harvestedArtifacts {
                let state = item.alreadyCached ? style.gray("cached") : style.green("stored (\(item.cloneMethod?.rawValue ?? "ok"))")
                let icon = item.alreadyCached ? style.gray(style.skippedIcon) : style.green(style.successIcon)
                print("  \(icon) \(style.dim("[artifact]")) \(style.bold(item.identity))/\(item.targetName) -> \(state)")
            }
            for item in result.harvestedPrebuilts {
                let state = item.alreadyCached ? style.gray("cached") : style.green("stored (\(item.cloneMethod?.rawValue ?? "ok"))")
                let icon = item.alreadyCached ? style.gray(style.skippedIcon) : style.green(style.successIcon)
                print("  \(icon) \(style.dim("[prebuilt]")) \(style.bold(item.identity))@\(item.versionOrChecksum) -> \(state)")
            }
            for item in result.skippedItems {
                print("  \(style.yellow(style.warningIcon)) \(style.gray("[skipped \(item.kind)] \(item.identifier): \(item.reason)"))")
            }
        }
    }
}

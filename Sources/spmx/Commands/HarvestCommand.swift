import ArgumentParser
import Foundation
import SPMXCore

struct HarvestCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "harvest",
        abstract: "Store resolved checkouts, artifacts, and prebuilts from SourcePackages (or .build) into the global spmx store."
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
        help: "Print detailed harvest diagnostics."
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

    func run() throws {
        let detected = try ProjectDetector.detect(
            in: path,
            projectPath: project,
            workspacePath: workspace
        )

        let startedAt = Date()
        let style = TerminalStyle.stdout
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

        let resolvedTimeout = CommandExecutor.resolveDefaultTimeout(override: timeout)
        let cloner = APFSCloner(verboseLogger: verboseLogger)
        let store = GlobalStore(cloner: cloner)
        let engine = PackageSyncEngine(store: store)

        if !quiet {
            print("\(style.heading("spmx harvest")) \(style.gray("[\(detected.type.rawValue)]"))")
            print(style.scopeLine(detected.rootPath))
            if style.isEnabled {
                let shortName = URL(fileURLWithPath: detected.rootPath).lastPathComponent
                spinner.start(message: "\(shortName) [\(detected.type.rawValue)]", detail: "scanning SourcePackages")
            }
        }

        let progressHandler: (@Sendable (String) -> Void)?
        if !quiet && style.isEnabled {
            progressHandler = { detail in spinner.update(detail: detail) }
        } else {
            progressHandler = nil
        }

        let options = HarvestOptions(
            sourcePackagesOverride: sourcePackages,
            commandTimeout: resolvedTimeout,
            progressHandler: progressHandler,
            verboseLogger: verboseLogger
        )

        let result = try engine.harvest(project: detected, options: options)

        if detected.type == .flutter {
            if !quiet && style.isEnabled {
                spinner.update(detail: "recording Flutter Package.resolved")
            }
            let flutterIntegrator = FlutterSPMIntegrator(
                store: store,
                commandRunner: ProcessFlutterCommandRunner(timeout: resolvedTimeout)
            )
            if flutterIntegrator.isFlutterSPMProject(detected) {
                _ = try? flutterIntegrator.recordResolvedDependencies(project: detected)
            }
        }

        spinner.stop()
        guard !quiet else { return }

        let duration = Date().timeIntervalSince(startedAt)
        print("  \(style.gray("Source:")) \(result.sourcePackagesURL.path)")
        print("")

        var progressParts = [
            "checkouts \(style.primaryBold("\(result.harvestedCheckouts.count)"))",
            "artifacts \(style.primaryBold("\(result.harvestedArtifacts.count)"))",
            "prebuilts \(style.primaryBold("\(result.harvestedPrebuilts.count)"))"
        ]
        if !result.skippedItems.isEmpty {
            progressParts.append(style.yellow("\(result.skippedItems.count) skipped"))
        }
        print("\(style.gray("Progress:")) \(progressParts.joined(separator: ", "))")

        if verbose {
            print("")
            print(style.section("packages:"))
            if let toolchainHash = result.toolchainHash {
                print("  \(style.gray("toolchain:")) \(style.italic(style.gray(toolchainHash)))")
            }
            for item in result.harvestedCheckouts {
                if item.alreadyCached {
                    print("  \(style.skippedIcon) \(style.gray("\(item.identity) \(item.revision.prefix(8)) (cached)"))")
                } else {
                    print("  \(style.addIcon) \(item.identity) \(style.gray("\(item.revision.prefix(8)) (\(item.cloneMethod?.rawValue ?? "stored"))"))")
                }
            }
            for item in result.harvestedArtifacts {
                if item.alreadyCached {
                    print("  \(style.skippedIcon) \(style.gray("\(item.identity)/\(item.targetName) (cached)"))")
                } else {
                    print("  \(style.addIcon) \(item.identity)/\(item.targetName) \(style.gray("(\(item.cloneMethod?.rawValue ?? "stored"))"))")
                }
            }
            for item in result.harvestedPrebuilts {
                if item.alreadyCached {
                    print("  \(style.skippedIcon) \(style.gray("\(item.identity) \(item.versionOrChecksum) (cached)"))")
                } else {
                    print("  \(style.addIcon) \(item.identity) \(style.gray("\(item.versionOrChecksum) (\(item.cloneMethod?.rawValue ?? "stored"))"))")
                }
            }
            for item in result.skippedItems {
                print("  \(style.warningIcon) \(style.gray("\(item.identifier): \(item.reason)"))")
            }
        }

        print("")
        print(style.doneIn(seconds: duration))
    }
}

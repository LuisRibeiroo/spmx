import ArgumentParser
import Foundation
import PSPMCore

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Inspect project detection, DerivedData/SourcePackages paths, cached pins, and compilation cache status."
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

    func validate() throws {
        if project != nil && workspace != nil {
            throw ValidationError("Cannot specify both --project and --workspace.")
        }
    }

    func run() throws {
        let style = TerminalStyle.stdout
        let report = try ProjectStatusInspector().inspect(
            in: path,
            projectPath: project,
            workspacePath: workspace
        )

        print(style.heading("Project Status"))
        print("  \(style.dim("Project type:"))       \(style.bold(report.projectType.rawValue))")
        print("  \(style.dim("Root path:"))          \(style.path(report.rootPath))")
        if let containerPath = report.containerPath {
            print("  \(style.dim("Container path:"))     \(style.path(containerPath))")
        }

        if let swift = report.swiftVersion {
            let shortSwift = swift.split(separator: "\n").first.map(String.init) ?? swift
            print("  \(style.dim("Swift version:"))      \(shortSwift)")
        } else {
            print("  \(style.dim("Swift version:"))      \(style.yellow("unavailable"))")
        }

        if let xcode = report.xcodeVersion {
            let shortXcode = xcode.split(separator: "\n").joined(separator: " / ")
            print("  \(style.dim("Xcode version:"))      \(shortXcode)")
        }

        if let hash = report.toolchainHash {
            print("  \(style.dim("Toolchain hash:"))     \(style.italic(hash))")
        }

        let buildLabel = report.projectType == .swiftPackage ? "Build path:     " : "DerivedData path:"
        print("  \(style.dim(buildLabel)) \(style.path(report.derivedDataPath))")
        print("  \(style.dim("SourcePackages:"))     \(style.path(report.sourcePackagesPath))")

        if let resolvedPath = report.packageResolvedPath {
            print("  \(style.dim("Package.resolved:"))   \(style.path(resolvedPath))")
            let pinsStatus = report.missingPins.isEmpty
                ? style.green("\(style.successIcon) \(report.cachedPinsCount)/\(report.totalPins) (0 missing)")
                : style.yellow("\(style.warningIcon) \(report.cachedPinsCount)/\(report.totalPins) (\(report.missingPins.count) missing)")
            print("  \(style.dim("Cached pins:"))        \(pinsStatus)")
            if report.cachedPrebuiltsCount > 0 {
                print("  \(style.dim("Cached prebuilts:"))   \(style.green("\(report.cachedPrebuiltsCount)")) \(style.dim("(matching active toolchain)"))")
            }
            for pin in report.missingPins {
                let versionLabel = pin.version ?? pin.revision ?? pin.branch ?? "unknown"
                print("    \(style.yellow(style.warningIcon)) \(style.yellow("missing:")) \(style.bold(pin.identity)) \(style.gray("(\(versionLabel))"))")
            }
        } else {
            print("  \(style.dim("Package.resolved:"))   \(style.gray("none found"))")
        }

        let cacheState = report.compilationCache.enabled
            ? style.green("\(style.successIcon) enabled")
            : style.gray("\(style.skippedIcon) disabled")
        let cacheSize = formatBytes(report.compilationCache.sizeBytes)
        print("  \(style.dim("Compilation cache:"))  \(cacheState) at \(style.path(report.compilationCache.path)) \(style.dim("(\(cacheSize))"))")
        if let reason = report.compilationCache.reason {
            print("    \(style.tip("\(style.infoIcon) Note: \(reason)"))")
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))))
    }
}

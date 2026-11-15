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
        let report = try ProjectStatusInspector().inspect(
            in: path,
            projectPath: project,
            workspacePath: workspace
        )

        print("Project Status")
        print("  Project type:       \(report.projectType.rawValue)")
        print("  Root path:          \(report.rootPath)")
        if let containerPath = report.containerPath {
            print("  Container path:     \(containerPath)")
        }

        if let swift = report.swiftVersion {
            let shortSwift = swift.split(separator: "\n").first.map(String.init) ?? swift
            print("  Swift version:      \(shortSwift)")
        } else {
            print("  Swift version:      unavailable")
        }

        if let xcode = report.xcodeVersion {
            let shortXcode = xcode.split(separator: "\n").joined(separator: " / ")
            print("  Xcode version:      \(shortXcode)")
        }

        if let hash = report.toolchainHash {
            print("  Toolchain hash:     \(hash)")
        }

        let buildLabel = report.projectType == .swiftPackage ? "Build path" : "DerivedData path"
        print("  \(buildLabel):  \(report.derivedDataPath)")
        print("  SourcePackages:     \(report.sourcePackagesPath)")

        if let resolvedPath = report.packageResolvedPath {
            print("  Package.resolved:   \(resolvedPath)")
            print("  Cached pins:        \(report.cachedPinsCount)/\(report.totalPins) (\(report.missingPins.count) missing)")
            if report.cachedPrebuiltsCount > 0 {
                print("  Cached prebuilts:   \(report.cachedPrebuiltsCount) (matching active toolchain)")
            }
            for pin in report.missingPins {
                let versionLabel = pin.version ?? pin.revision ?? pin.branch ?? "unknown"
                print("    - missing: \(pin.identity) (\(versionLabel))")
            }
        } else {
            print("  Package.resolved:   none found")
        }

        let cacheState = report.compilationCache.enabled ? "enabled" : "disabled"
        let cacheSize = formatBytes(report.compilationCache.sizeBytes)
        print("  Compilation cache:  \(cacheState) at \(report.compilationCache.path) (\(cacheSize))")
        if let reason = report.compilationCache.reason {
            print("    Note: \(reason)")
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))))
    }
}

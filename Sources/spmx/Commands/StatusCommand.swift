import ArgumentParser
import Foundation
import SPMXCore

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

        print("\(style.heading("spmx status")) \(style.gray("[\(report.projectType.rawValue)]"))")
        print(style.scopeLine(report.rootPath))
        if let containerPath = report.containerPath {
            print("  \(style.gray("Container:"))       \(containerPath)")
        }
        print("")

        print(style.section("Toolchain:"))
        if let swift = report.swiftVersion {
            let shortSwift = swift.split(separator: "\n").first.map(String.init) ?? swift
            print("  \(style.gray("Swift:"))           \(shortSwift)")
        } else {
            print("  \(style.gray("Swift:"))           \(style.yellow("unavailable"))")
        }

        if let xcode = report.xcodeVersion {
            let shortXcode = xcode.split(separator: "\n").joined(separator: " / ")
            print("  \(style.gray("Xcode:"))           \(shortXcode)")
        }

        if let hash = report.toolchainHash {
            print("  \(style.gray("Toolchain hash:"))  \(style.italic(style.gray(hash)))")
        }

        print("")
        print(style.section("Paths:"))
        let buildLabel = report.projectType == .swiftPackage ? "Build path:     " : "DerivedData:    "
        print("  \(style.gray(buildLabel)) \(report.derivedDataPath)")
        print("  \(style.gray("SourcePackages:"))  \(report.sourcePackagesPath)")

        if let resolvedPath = report.packageResolvedPath {
            print("  \(style.gray("Package.resolved:")) \(resolvedPath)")
            print("")
            print(style.section("Packages:"))
            let pinsStatus = report.missingPins.isEmpty
                ? style.green("\(style.successIcon) \(report.cachedPinsCount)/\(report.totalPins) cached")
                : "\(style.warningIcon) \(style.primaryBold("\(report.cachedPinsCount)/\(report.totalPins)")) \(style.yellow("cached (\(report.missingPins.count) missing)"))"
            print("  \(style.gray("Cached pins:"))     \(pinsStatus)")
            if report.cachedPrebuiltsCount > 0 {
                print("  \(style.gray("Prebuilts:"))       \(style.green("\(report.cachedPrebuiltsCount)")) \(style.gray("(matching active toolchain)"))")
            }
            for pin in report.missingPins {
                let versionLabel = pin.version ?? pin.revision ?? pin.branch ?? "unknown"
                print("    \(style.warningIcon) \(pin.identity) \(style.gray("(\(versionLabel))"))")
            }
        } else {
            print("  \(style.gray("Package.resolved:")) \(style.gray("none found"))")
        }

        print("")
        print(style.section("Compilation cache:"))
        let cacheState = report.compilationCache.enabled
            ? style.green("\(style.successIcon) enabled")
            : style.gray("\(style.skippedIcon) disabled")
        let cacheSize = formatBytes(report.compilationCache.sizeBytes)
        print("  \(cacheState) \(style.gray("·")) \(report.compilationCache.path) \(style.gray("(\(cacheSize))"))")
        if let reason = report.compilationCache.reason {
            print("  \(style.tip("›")) \(style.tip(reason))")
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))))
    }
}

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

    @Flag(
        name: .long,
        help: "Output machine-readable JSON."
    )
    var json: Bool = false

    func validate() throws {
        if project != nil && workspace != nil {
            throw ValidationError("Cannot specify both --project and --workspace.")
        }
    }

    func run() throws {
        let inspector = ProjectStatusInspector(cacheProbe: DefaultCompilationCacheProbe())
        let report = try inspector.inspect(
            in: path,
            projectPath: project,
            workspacePath: workspace
        )

        if json {
            let payload = StatusJSONOutput(
                projectType: report.projectType.rawValue,
                rootPath: report.rootPath,
                containerPath: report.containerPath,
                isLinked: report.isLinked,
                swiftVersion: report.swiftVersion,
                xcodeVersion: report.xcodeVersion,
                toolchainHash: report.toolchainHash,
                derivedDataPath: report.derivedDataPath,
                sourcePackagesPath: report.sourcePackagesPath,
                packageResolvedPath: report.packageResolvedPath,
                totalPins: report.totalPins,
                cachedPinsCount: report.cachedPinsCount,
                pinStatuses: report.pinStatuses,
                cachedPrebuiltsCount: report.cachedPrebuiltsCount,
                projectSavedBytes: report.projectSavedBytes,
                compilationCache: CompilationCacheJSONOutput(
                    path: report.compilationCache.path,
                    enabled: report.compilationCache.enabled,
                    sizeBytes: report.compilationCache.sizeBytes,
                    reason: report.compilationCache.reason,
                    xcodeSupported: report.compilationCache.xcodeSupported,
                    swiftCapability: report.compilationCache.swiftCapability?.rawValue,
                    swiftGlobalCachePath: report.compilationCache.swiftGlobalCachePath,
                    isAlignedWithSwiftPM: report.compilationCache.isAlignedWithSwiftPM
                )
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            if let text = String(data: data, encoding: .utf8) {
                print(text)
            }
            return
        }

        let style = TerminalStyle.stdout
        print("\(style.heading("spmx status")) \(style.gray("[\(report.projectType.rawValue)]"))")
        print(style.scopeLine(report.rootPath))
        let linkLabel = report.isLinked
            ? style.green("\(style.successIcon) Linked to global store")
            : style.yellow("\(style.skippedIcon) Unlinked (using local project cache)")
        print("  \(style.gray("Store link:"))      \(linkLabel)")
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
            for entry in report.pinStatuses {
                let versionLabel = entry.version ?? entry.branch ?? entry.revision.map { String($0.prefix(8)) } ?? "unknown"
                let statusText: String
                let icon: String
                switch entry.status {
                case .hydrated:
                    icon = style.successIcon
                    statusText = style.green("hydrated / CoW clone")
                case .inStore:
                    icon = style.addIcon
                    statusText = style.primary("in store")
                case .missing:
                    icon = style.warningIcon
                    statusText = style.yellow("missing")
                }
                print("    \(icon) \(entry.identity) \(style.gray("@ \(versionLabel)"))  \(statusText)")
            }
            if report.isLinked {
                print("  \(style.gray("Estimated disk saved in this project:")) \(style.green(style.bold(formatBytes(report.projectSavedBytes))))")
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
        if report.compilationCache.isAlignedWithSwiftPM == false,
           let swiftPath = report.compilationCache.swiftGlobalCachePath {
            print("  \(style.warningIcon) \(style.yellow("SwiftPM global build-cache path (\(swiftPath)) diverges from \(report.compilationCache.path)."))")
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))))
    }
}

private struct StatusJSONOutput: Encodable {
    let projectType: String
    let rootPath: String
    let containerPath: String?
    let isLinked: Bool
    let swiftVersion: String?
    let xcodeVersion: String?
    let toolchainHash: String?
    let derivedDataPath: String
    let sourcePackagesPath: String
    let packageResolvedPath: String?
    let totalPins: Int
    let cachedPinsCount: Int
    let pinStatuses: [PinStatusEntry]
    let cachedPrebuiltsCount: Int
    let projectSavedBytes: UInt64
    let compilationCache: CompilationCacheJSONOutput
}

private struct CompilationCacheJSONOutput: Encodable {
    let path: String
    let enabled: Bool
    let sizeBytes: UInt64
    let reason: String?
    let xcodeSupported: Bool?
    let swiftCapability: String?
    let swiftGlobalCachePath: String?
    let isAlignedWithSwiftPM: Bool?
}

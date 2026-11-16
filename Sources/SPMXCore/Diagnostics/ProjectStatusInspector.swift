import Foundation

/// Status of the shared LLVM CAS compilation cache (`~/.spmx/compilation-cache`).
public struct CompilationCacheStatus: Sendable, Equatable {
    public let path: String
    public let enabled: Bool
    public let sizeBytes: UInt64
    public let reason: String?

    public init(
        path: String,
        enabled: Bool,
        sizeBytes: UInt64,
        reason: String? = nil
    ) {
        self.path = path
        self.enabled = enabled
        self.sizeBytes = sizeBytes
        self.reason = reason
    }
}

/// Snapshot of a project's `spmx` cache readiness, toolchain, paths, and pin coverage.
public struct ProjectStatusReport: Sendable, Equatable {
    public let projectType: ProjectType
    public let rootPath: String
    public let containerPath: String?
    public let swiftVersion: String?
    public let xcodeVersion: String?
    public let toolchainHash: String?
    public let derivedDataPath: String
    public let sourcePackagesPath: String
    public let packageResolvedPath: String?
    public let totalPins: Int
    public let cachedPinsCount: Int
    public let missingPins: [PackagePin]
    public let cachedPrebuiltsCount: Int
    public let compilationCache: CompilationCacheStatus

    public init(
        projectType: ProjectType,
        rootPath: String,
        containerPath: String?,
        swiftVersion: String?,
        xcodeVersion: String?,
        toolchainHash: String?,
        derivedDataPath: String,
        sourcePackagesPath: String,
        packageResolvedPath: String?,
        totalPins: Int,
        cachedPinsCount: Int,
        missingPins: [PackagePin],
        cachedPrebuiltsCount: Int = 0,
        compilationCache: CompilationCacheStatus
    ) {
        self.projectType = projectType
        self.rootPath = rootPath
        self.containerPath = containerPath
        self.swiftVersion = swiftVersion
        self.xcodeVersion = xcodeVersion
        self.toolchainHash = toolchainHash
        self.derivedDataPath = derivedDataPath
        self.sourcePackagesPath = sourcePackagesPath
        self.packageResolvedPath = packageResolvedPath
        self.totalPins = totalPins
        self.cachedPinsCount = cachedPinsCount
        self.missingPins = missingPins
        self.cachedPrebuiltsCount = cachedPrebuiltsCount
        self.compilationCache = compilationCache
    }
}

/// Inspects a Flutter, Xcode, or SwiftPM project and reports cache coverage against `GlobalStore`.
public struct ProjectStatusInspector: Sendable {
    public typealias ToolchainProvider = @Sendable () throws -> ToolchainFingerprint

    public let store: GlobalStore
    private let explicitCompilationCacheURL: URL?
    private let homeDirectory: URL
    private let toolchainProvider: ToolchainProvider

    public init(
        store: GlobalStore = GlobalStore(),
        compilationCacheURL: URL? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        toolchainProvider: @escaping ToolchainProvider = { try ToolchainFingerprint.current() }
    ) {
        self.store = store
        self.explicitCompilationCacheURL = compilationCacheURL?.standardizedFileURL
        self.homeDirectory = homeDirectory
        self.toolchainProvider = toolchainProvider
    }

    /// Detects the project at `directoryPath` (or explicit `projectPath` / `workspacePath`)
    /// and inspects its `DerivedData`/`SourcePackages` paths, pin cache hit rate, and compilation cache.
    public func inspect(
        in directoryPath: String? = nil,
        projectPath: String? = nil,
        workspacePath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ProjectStatusReport {
        let fileManager = FileManager.default
        let detected = try ProjectDetector.detect(
            in: directoryPath,
            projectPath: projectPath,
            workspacePath: workspacePath,
            currentDirectory: fileManager.currentDirectoryPath,
            fileManager: fileManager
        )

        let (derivedDataPath, sourcePackagesPath) = resolveBuildPaths(
            for: detected,
            fileManager: fileManager
        )

        let toolchain = try? toolchainProvider()

        let packageResolvedPath = detected.packageResolvedPath ?? detected.allPackageResolvedPaths.first
        var totalPins = 0
        var cachedPinsCount = 0
        var missingPins: [PackagePin] = []
        var cachedPrebuiltsCount = 0

        if let packageResolvedPath, fileManager.fileExists(atPath: packageResolvedPath) {
            let resolved = try PackageResolvedParser.parse(fileAt: packageResolvedPath, fileManager: fileManager)
            totalPins = resolved.pins.count

            for pin in resolved.pins {
                let identity = pin.identity.lowercased()
                if let revision = pin.revision,
                   !revision.isEmpty,
                   store.hasCheckout(identity: identity, revision: revision) {
                    cachedPinsCount += 1
                } else {
                    missingPins.append(pin)
                }
            }

            if let toolchainHash = toolchain?.hash {
                cachedPrebuiltsCount = countCachedPrebuilts(
                    for: resolved.pins,
                    toolchainHash: toolchainHash,
                    fileManager: fileManager
                )
            }
        }

        let cacheURL = explicitCompilationCacheURL
            ?? StoreManager.defaultCompilationCacheURL(environment: environment, homeDirectory: homeDirectory)
        let cacheSize = DiagnosticsSupport.directorySizeBytes(at: cacheURL, fileManager: fileManager)
        let (cacheEnabled, cacheReason) = evaluateCompilationCacheStatus(
            toolchain: toolchain,
            environment: environment
        )

        return ProjectStatusReport(
            projectType: detected.type,
            rootPath: detected.rootPath,
            containerPath: detected.containerPath,
            swiftVersion: toolchain?.swiftVersion,
            xcodeVersion: toolchain?.xcodeVersion,
            toolchainHash: toolchain?.hash,
            derivedDataPath: derivedDataPath,
            sourcePackagesPath: sourcePackagesPath,
            packageResolvedPath: packageResolvedPath,
            totalPins: totalPins,
            cachedPinsCount: cachedPinsCount,
            missingPins: missingPins,
            cachedPrebuiltsCount: cachedPrebuiltsCount,
            compilationCache: CompilationCacheStatus(
                path: cacheURL.path,
                enabled: cacheEnabled,
                sizeBytes: cacheSize,
                reason: cacheReason
            )
        )
    }

    // MARK: - Private Helpers

    private func resolveBuildPaths(
        for detected: DetectedProject,
        fileManager: FileManager
    ) -> (derivedDataPath: String, sourcePackagesPath: String) {
        switch detected.type {
        case .swiftPackage:
            let buildPath = URL(fileURLWithPath: detected.rootPath)
                .appendingPathComponent(".build")
                .standardizedFileURL
                .path
            return (buildPath, buildPath)

        case .xcode, .flutter:
            if let containerPath = detected.containerPath {
                let ddURL = DerivedDataPathCalculator.derivedDataURL(
                    forContainerPath: containerPath,
                    currentDirectory: fileManager.currentDirectoryPath,
                    fileManager: fileManager
                ).standardizedFileURL
                let ddSPURL = ddURL.appendingPathComponent("SourcePackages").standardizedFileURL
                if DiagnosticsSupport.isDirectory(atPath: ddSPURL.path, fileManager: fileManager) {
                    return (ddURL.path, ddSPURL.path)
                }

                // Flutter CLI builds store SourcePackages under `<root>/build/<platform>/SourcePackages`.
                if detected.type == .flutter {
                    let syncEngine = PackageSyncEngine(store: store, fileManager: fileManager)
                    let candidates = (try? syncEngine.resolveCandidateSourcePackagesURLs(for: detected)) ?? []
                    if let existingSP = candidates.first(where: {
                        DiagnosticsSupport.isDirectory(atPath: $0.path, fileManager: fileManager)
                    }) {
                        return (ddURL.path, existingSP.path)
                    }
                }
                return (ddURL.path, ddSPURL.path)
            }

            let fallbackBuild = URL(fileURLWithPath: detected.rootPath)
                .appendingPathComponent(".build")
                .standardizedFileURL
                .path
            return (fallbackBuild, fallbackBuild)
        }
    }

    private func countCachedPrebuilts(
        for pins: [PackagePin],
        toolchainHash: String,
        fileManager: FileManager
    ) -> Int {
        guard let toolchainDir = try? store.prebuiltToolchainDirectory(toolchainHash: toolchainHash),
              DiagnosticsSupport.isDirectory(atPath: toolchainDir.path, fileManager: fileManager),
              let entries = try? fileManager.contentsOfDirectory(
                  at: toolchainDir,
                  includingPropertiesForKeys: nil,
                  options: [.skipsHiddenFiles]
              ) else {
            return 0
        }

        let entryNames = entries.map { $0.lastPathComponent.lowercased() }
        var matched = 0
        for pin in pins {
            let prefix = "\(pin.identity.lowercased())-"
            if entryNames.contains(where: { $0.hasPrefix(prefix) }) {
                matched += 1
            }
        }
        return matched
    }

    private func evaluateCompilationCacheStatus(
        toolchain: ToolchainFingerprint?,
        environment: [String: String]
    ) -> (enabled: Bool, reason: String?) {
        if environment["SPMX_DISABLE"] == "1" {
            return (false, "Disabled by SPMX_DISABLE=1")
        }
        if environment["SPMX_NO_COMPILE_CACHE"] == "1" {
            return (false, "Disabled by SPMX_NO_COMPILE_CACHE=1")
        }
        guard let toolchain else {
            return (false, "Active Swift/Xcode toolchain unavailable")
        }
        if DiagnosticsSupport.supportsCompilationCache(
            swiftVersion: toolchain.swiftVersion,
            xcodeVersion: toolchain.xcodeVersion
        ) {
            return (true, "Supported by active Xcode 16+ / Swift 6+ toolchain")
        }
        return (false, "Requires Xcode 16+ or Swift 6+ for LLVM CAS compilation caching")
    }
}

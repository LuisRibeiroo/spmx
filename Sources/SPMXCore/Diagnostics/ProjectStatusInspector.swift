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

/// Cache state of a resolved package pin relative to the project and `GlobalStore`.
public enum PinCacheStatus: String, Sendable, Equatable, Codable {
    case hydrated
    case inStore = "in_store"
    case missing
}

/// Per-package status entry with semantic version and cache state.
public struct PinStatusEntry: Sendable, Equatable, Codable {
    public let identity: String
    public let version: String?
    public let branch: String?
    public let revision: String?
    public let status: PinCacheStatus

    public init(
        identity: String,
        version: String? = nil,
        branch: String? = nil,
        revision: String? = nil,
        status: PinCacheStatus
    ) {
        self.identity = identity
        self.version = version
        self.branch = branch
        self.revision = revision
        self.status = status
    }
}

/// Snapshot of a project's `spmx` cache readiness, toolchain, paths, and pin coverage.
public struct ProjectStatusReport: Sendable, Equatable {
    public let projectType: ProjectType
    public let rootPath: String
    public let containerPath: String?
    public let isLinked: Bool
    public let swiftVersion: String?
    public let xcodeVersion: String?
    public let toolchainHash: String?
    public let derivedDataPath: String
    public let sourcePackagesPath: String
    public let packageResolvedPath: String?
    public let totalPins: Int
    public let cachedPinsCount: Int
    public let missingPins: [PackagePin]
    public let pinStatuses: [PinStatusEntry]
    public let cachedPrebuiltsCount: Int
    public let projectSavedBytes: UInt64
    public let compilationCache: CompilationCacheStatus

    public init(
        projectType: ProjectType,
        rootPath: String,
        containerPath: String?,
        isLinked: Bool = true,
        swiftVersion: String?,
        xcodeVersion: String?,
        toolchainHash: String?,
        derivedDataPath: String,
        sourcePackagesPath: String,
        packageResolvedPath: String?,
        totalPins: Int,
        cachedPinsCount: Int,
        missingPins: [PackagePin],
        pinStatuses: [PinStatusEntry] = [],
        cachedPrebuiltsCount: Int = 0,
        projectSavedBytes: UInt64 = 0,
        compilationCache: CompilationCacheStatus
    ) {
        self.projectType = projectType
        self.rootPath = rootPath
        self.containerPath = containerPath
        self.isLinked = isLinked
        self.swiftVersion = swiftVersion
        self.xcodeVersion = xcodeVersion
        self.toolchainHash = toolchainHash
        self.derivedDataPath = derivedDataPath
        self.sourcePackagesPath = sourcePackagesPath
        self.packageResolvedPath = packageResolvedPath
        self.totalPins = totalPins
        self.cachedPinsCount = cachedPinsCount
        self.missingPins = missingPins
        self.pinStatuses = pinStatuses
        self.cachedPrebuiltsCount = cachedPrebuiltsCount
        self.projectSavedBytes = projectSavedBytes
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

        let isLinked = !store.isProjectExcluded(at: detected.rootPath, fileManager: fileManager)
        let packageResolvedPath = detected.packageResolvedPath ?? detected.allPackageResolvedPaths.first
        var totalPins = 0
        var cachedPinsCount = 0
        var missingPins: [PackagePin] = []
        var pinStatuses: [PinStatusEntry] = []
        var cachedPrebuiltsCount = 0
        let sourcePackagesURL = URL(fileURLWithPath: sourcePackagesPath)

        if let packageResolvedPath, fileManager.fileExists(atPath: packageResolvedPath) {
            let resolved = try PackageResolvedParser.parse(fileAt: packageResolvedPath, fileManager: fileManager)
            totalPins = resolved.pins.count

            let checkoutsDir = sourcePackagesURL.appendingPathComponent("checkouts")
            let existingCheckoutNames: Set<String> = Set(
                ((try? fileManager.contentsOfDirectory(atPath: checkoutsDir.path)) ?? []).map { $0.lowercased() }
            )

            for pin in resolved.pins {
                let identity = pin.identity.lowercased()
                let inStore: Bool
                if let revision = pin.revision,
                   !revision.isEmpty,
                   store.hasCheckout(identity: identity, revision: revision) {
                    cachedPinsCount += 1
                    inStore = true
                } else {
                    missingPins.append(pin)
                    inStore = false
                }

                let isHydratedLocally = existingCheckoutNames.contains(identity)
                    || existingCheckoutNames.contains(where: { $0.hasPrefix("\(identity)-") })
                let status: PinCacheStatus
                if inStore && isHydratedLocally && isLinked {
                    status = .hydrated
                } else if inStore {
                    status = .inStore
                } else {
                    status = .missing
                }
                pinStatuses.append(PinStatusEntry(
                    identity: identity,
                    version: pin.version,
                    branch: pin.branch,
                    revision: pin.revision,
                    status: status
                ))
            }

            if let toolchainHash = toolchain?.hash {
                cachedPrebuiltsCount = countCachedPrebuilts(
                    for: resolved.pins,
                    toolchainHash: toolchainHash,
                    fileManager: fileManager
                )
            }
        }

        let projectSavedBytes = isLinked
            ? estimateProjectSavedBytes(
                sourcePackagesURL: sourcePackagesURL,
                pinStatuses: pinStatuses,
                toolchainHash: toolchain?.hash,
                fileManager: fileManager
            )
            : 0

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
            isLinked: isLinked,
            swiftVersion: toolchain?.swiftVersion,
            xcodeVersion: toolchain?.xcodeVersion,
            toolchainHash: toolchain?.hash,
            derivedDataPath: derivedDataPath,
            sourcePackagesPath: sourcePackagesPath,
            packageResolvedPath: packageResolvedPath,
            totalPins: totalPins,
            cachedPinsCount: cachedPinsCount,
            missingPins: missingPins,
            pinStatuses: pinStatuses,
            cachedPrebuiltsCount: cachedPrebuiltsCount,
            projectSavedBytes: projectSavedBytes,
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

    private func estimateProjectSavedBytes(
        sourcePackagesURL: URL,
        pinStatuses: [PinStatusEntry],
        toolchainHash: String?,
        fileManager: FileManager
    ) -> UInt64 {
        guard APFSCloner.isAPFS(at: store.rootURL) else {
            return 0
        }

        var savedBytes: UInt64 = 0

        // 1. Checkouts
        let checkoutsDir = sourcePackagesURL.appendingPathComponent("checkouts")
        if DiagnosticsSupport.isDirectory(atPath: checkoutsDir.path, fileManager: fileManager),
           let entries = try? fileManager.contentsOfDirectory(
               at: checkoutsDir,
               includingPropertiesForKeys: nil,
               options: [.skipsHiddenFiles]
           ) {
            let hydratedPins = pinStatuses.filter { $0.status == .hydrated }
            for entryURL in entries {
                let name = entryURL.lastPathComponent.lowercased()
                let matchesStorePin = hydratedPins.contains { pin in
                    name == pin.identity || name.hasPrefix("\(pin.identity)-")
                }
                if matchesStorePin {
                    savedBytes += DiagnosticsSupport.itemSizeBytes(at: entryURL, fileManager: fileManager)
                }
            }
        } else {
            // If checkouts dir isn't materialized yet, estimate from store entries for hydrated pins
            for pin in pinStatuses where pin.status == .hydrated {
                if let rev = pin.revision,
                   let storeCheckout = try? store.checkoutURL(identity: pin.identity, revision: rev),
                   fileManager.fileExists(atPath: storeCheckout.path) {
                    savedBytes += DiagnosticsSupport.itemSizeBytes(at: storeCheckout, fileManager: fileManager)
                }
            }
        }

        // 2. Repositories
        let reposDir = sourcePackagesURL.appendingPathComponent("repositories")
        if DiagnosticsSupport.isDirectory(atPath: reposDir.path, fileManager: fileManager),
           let entries = try? fileManager.contentsOfDirectory(
               at: reposDir,
               includingPropertiesForKeys: nil,
               options: [.skipsHiddenFiles]
           ) {
            for entryURL in entries {
                let folder = entryURL.lastPathComponent.lowercased()
                let matchedIdentity = pinStatuses.first { pin in
                    folder == pin.identity || folder.hasPrefix("\(pin.identity)-")
                }?.identity
                if let identity = matchedIdentity, store.hasRepository(identity: identity) {
                    savedBytes += DiagnosticsSupport.itemSizeBytes(at: entryURL, fileManager: fileManager)
                }
            }
        }

        // 3. Artifacts
        let artifactsDir = sourcePackagesURL.appendingPathComponent("artifacts")
        if DiagnosticsSupport.isDirectory(atPath: artifactsDir.path, fileManager: fileManager),
           let identityDirs = try? fileManager.contentsOfDirectory(
               at: artifactsDir,
               includingPropertiesForKeys: nil,
               options: [.skipsHiddenFiles]
           ) {
            for idURL in identityDirs {
                let identity = idURL.lastPathComponent.lowercased()
                let storeArtifactIdentityDir = store.artifactsDirectory.appendingPathComponent(identity)
                if DiagnosticsSupport.isDirectory(atPath: storeArtifactIdentityDir.path, fileManager: fileManager) {
                    savedBytes += DiagnosticsSupport.itemSizeBytes(at: idURL, fileManager: fileManager)
                }
            }
        }

        // 4. Prebuilts
        let prebuiltsDir = sourcePackagesURL.appendingPathComponent("prebuilts")
        if let toolchainHash,
           let storeToolchainDir = try? store.prebuiltToolchainDirectory(toolchainHash: toolchainHash),
           DiagnosticsSupport.isDirectory(atPath: storeToolchainDir.path, fileManager: fileManager),
           DiagnosticsSupport.isDirectory(atPath: prebuiltsDir.path, fileManager: fileManager),
           let entries = try? fileManager.contentsOfDirectory(
               at: prebuiltsDir,
               includingPropertiesForKeys: nil,
               options: [.skipsHiddenFiles]
           ) {
            let storeNames = ((try? fileManager.contentsOfDirectory(atPath: storeToolchainDir.path)) ?? []).map { $0.lowercased() }
            for entryURL in entries {
                let name = entryURL.lastPathComponent.lowercased()
                if storeNames.contains(where: { $0 == name || $0.hasPrefix("\(name)-") }) {
                    savedBytes += DiagnosticsSupport.itemSizeBytes(at: entryURL, fileManager: fileManager)
                }
            }
        }

        return savedBytes
    }
}

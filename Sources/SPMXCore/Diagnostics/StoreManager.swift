import Foundation

/// Summary of cached `prebuilts/` grouped by toolchain fingerprint hash.
public struct PrebuiltToolchainGroup: Sendable, Equatable {
    public let toolchainHash: String
    public let swiftVersion: String?
    public let xcodeVersion: String?
    public let count: Int
    public let sizeBytes: UInt64

    public init(
        toolchainHash: String,
        swiftVersion: String? = nil,
        xcodeVersion: String? = nil,
        count: Int,
        sizeBytes: UInt64
    ) {
        self.toolchainHash = toolchainHash
        self.swiftVersion = swiftVersion
        self.xcodeVersion = xcodeVersion
        self.count = count
        self.sizeBytes = sizeBytes
    }
}

/// Per-project space savings summary in `spmx store status`.
public struct ProjectSavingsSummary: Sendable, Equatable, Codable {
    public let projectPath: String
    public let sharedPackagesCount: Int
    public let projectSavedBytes: UInt64

    public init(
        projectPath: String,
        sharedPackagesCount: Int,
        projectSavedBytes: UInt64
    ) {
        self.projectPath = projectPath
        self.sharedPackagesCount = sharedPackagesCount
        self.projectSavedBytes = projectSavedBytes
    }
}

/// Single `(identity, version/revision)` slice stored in `~/.spmx/store` for `spmx store list`.
public struct StorePackageSlice: Sendable, Equatable, Codable {
    public let identity: String
    public let version: String?
    public let branch: String?
    public let revision: String
    public let location: String?
    public let sizeBytes: UInt64
    public let linkedProjects: [String]

    public init(
        identity: String,
        version: String? = nil,
        branch: String? = nil,
        revision: String,
        location: String? = nil,
        sizeBytes: UInt64,
        linkedProjects: [String]
    ) {
        self.identity = identity
        self.version = version
        self.branch = branch
        self.revision = revision
        self.location = location
        self.sizeBytes = sizeBytes
        self.linkedProjects = linkedProjects
    }
}

/// Report returned by `StoreManager.list()`.
public struct StoreListReport: Sendable, Equatable, Codable {
    public let storePath: String
    public let packages: [StorePackageSlice]
    public let repositoriesCount: Int
    public let repositoriesSizeBytes: UInt64
    public let totalCheckoutsSizeBytes: UInt64

    public init(
        storePath: String,
        packages: [StorePackageSlice],
        repositoriesCount: Int,
        repositoriesSizeBytes: UInt64,
        totalCheckoutsSizeBytes: UInt64
    ) {
        self.storePath = storePath
        self.packages = packages
        self.repositoriesCount = repositoriesCount
        self.repositoriesSizeBytes = repositoriesSizeBytes
        self.totalCheckoutsSizeBytes = totalCheckoutsSizeBytes
    }
}

/// Snapshot of `~/.spmx/store`, `~/.spmx/compilation-cache`, registered projects, and CoW savings.
public struct StoreStatusReport: Sendable, Equatable {
    public let storePath: String
    public let checkoutsCount: Int
    public let checkoutsSizeBytes: UInt64
    public let repositoriesCount: Int
    public let repositoriesSizeBytes: UInt64
    public let artifactsCount: Int
    public let artifactsSizeBytes: UInt64
    public let prebuiltsCount: Int
    public let prebuiltsSizeBytes: UInt64
    public let prebuiltsByToolchain: [PrebuiltToolchainGroup]
    public let logicalStoreSizeBytes: UInt64
    public let compilationCachePath: String
    public let compilationCacheSizeBytes: UInt64
    public let activeProjectsCount: Int
    public let missingProjectsCount: Int
    public let excludedProjects: [String]
    public let projectSavings: [ProjectSavingsSummary]
    public let estimatedCoWSavingsBytes: UInt64

    public var totalMachineSavedBytes: UInt64 {
        estimatedCoWSavingsBytes
    }

    public var totalRegisteredProjectsCount: Int {
        activeProjectsCount + missingProjectsCount
    }

    public init(
        storePath: String,
        checkoutsCount: Int,
        checkoutsSizeBytes: UInt64,
        repositoriesCount: Int = 0,
        repositoriesSizeBytes: UInt64 = 0,
        artifactsCount: Int,
        artifactsSizeBytes: UInt64,
        prebuiltsCount: Int,
        prebuiltsSizeBytes: UInt64,
        prebuiltsByToolchain: [PrebuiltToolchainGroup],
        logicalStoreSizeBytes: UInt64,
        compilationCachePath: String,
        compilationCacheSizeBytes: UInt64,
        activeProjectsCount: Int,
        missingProjectsCount: Int,
        excludedProjects: [String] = [],
        projectSavings: [ProjectSavingsSummary] = [],
        estimatedCoWSavingsBytes: UInt64
    ) {
        self.storePath = storePath
        self.checkoutsCount = checkoutsCount
        self.checkoutsSizeBytes = checkoutsSizeBytes
        self.repositoriesCount = repositoriesCount
        self.repositoriesSizeBytes = repositoriesSizeBytes
        self.artifactsCount = artifactsCount
        self.artifactsSizeBytes = artifactsSizeBytes
        self.prebuiltsCount = prebuiltsCount
        self.prebuiltsSizeBytes = prebuiltsSizeBytes
        self.prebuiltsByToolchain = prebuiltsByToolchain
        self.logicalStoreSizeBytes = logicalStoreSizeBytes
        self.compilationCachePath = compilationCachePath
        self.compilationCacheSizeBytes = compilationCacheSizeBytes
        self.activeProjectsCount = activeProjectsCount
        self.missingProjectsCount = missingProjectsCount
        self.excludedProjects = excludedProjects
        self.projectSavings = projectSavings
        self.estimatedCoWSavingsBytes = estimatedCoWSavingsBytes
    }
}

/// Options controlling `StoreManager.prune(options:)`.
public struct PruneOptions: Sendable, Equatable {
    public var dryRun: Bool
    public var olderThanDays: Int
    public var now: Date

    public init(
        dryRun: Bool = false,
        olderThanDays: Int = 30,
        now: Date = Date()
    ) {
        self.dryRun = dryRun
        self.olderThanDays = olderThanDays
        self.now = now
    }
}

/// Summary of entries removed (or slated for removal in `--dry-run`) by `StoreManager.prune(options:)`.
public struct PruneReport: Sendable, Equatable, Codable {
    public let dryRun: Bool
    public let removedMissingProjects: [String]
    public let removedCheckouts: [String]
    public let removedArtifacts: [String]
    public let removedPrebuilts: [String]
    public let removedCompilationCacheEntries: [String]
    public let reclaimedBytes: UInt64

    public var totalRemovedCount: Int {
        removedMissingProjects.count
            + removedCheckouts.count
            + removedArtifacts.count
            + removedPrebuilts.count
            + removedCompilationCacheEntries.count
    }

    public init(
        dryRun: Bool,
        removedMissingProjects: [String],
        removedCheckouts: [String],
        removedArtifacts: [String],
        removedPrebuilts: [String],
        removedCompilationCacheEntries: [String],
        reclaimedBytes: UInt64
    ) {
        self.dryRun = dryRun
        self.removedMissingProjects = removedMissingProjects
        self.removedCheckouts = removedCheckouts
        self.removedArtifacts = removedArtifacts
        self.removedPrebuilts = removedPrebuilts
        self.removedCompilationCacheEntries = removedCompilationCacheEntries
        self.reclaimedBytes = reclaimedBytes
    }
}

/// Result of evaluating whether a periodic automatic prune reminder is due.
public struct AutoPruneEvaluation: Sendable, Equatable, Codable {
    public let enabled: Bool
    public let intervalDays: Int
    public let lastPrunedAt: Date?
    public let referenceDate: Date?
    public let daysSinceLastPrune: Int?
    public let isDue: Bool

    public init(
        enabled: Bool,
        intervalDays: Int,
        lastPrunedAt: Date?,
        referenceDate: Date?,
        daysSinceLastPrune: Int?,
        isDue: Bool
    ) {
        self.enabled = enabled
        self.intervalDays = intervalDays
        self.lastPrunedAt = lastPrunedAt
        self.referenceDate = referenceDate
        self.daysSinceLastPrune = daysSinceLastPrune
        self.isDue = isDue
    }
}

/// Outcome of an interactive periodic prune reminder prompt.
public enum AutoPrunePromptOutcome: Sendable, Equatable {
    case notDue
    case skipped
    case prunedDirectly(PruneReport)
    case previewedAndPruned(preview: PruneReport, applied: PruneReport)
    case previewedAndSkipped(preview: PruneReport)
}

/// Manages inspection and garbage collection for the global `spmx` store and compilation cache.
public struct StoreManager: Sendable {
    public static let compilationCacheEnvironmentKey = "SPMX_COMPILATION_CACHE_DIR"

    public let store: GlobalStore
    public let compilationCacheURL: URL

    public init(
        store: GlobalStore = GlobalStore(),
        compilationCacheURL: URL? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.store = store
        self.compilationCacheURL = (
            compilationCacheURL
                ?? Self.defaultCompilationCacheURL(environment: environment, homeDirectory: homeDirectory)
        ).standardizedFileURL
    }

    /// Resolves `~/.spmx/compilation-cache` (or `SPMX_COMPILATION_CACHE_DIR` when set).
    public static func defaultCompilationCacheURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let override = environment[compilationCacheEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        return homeDirectory
            .appendingPathComponent(".spmx")
            .appendingPathComponent("compilation-cache")
            .standardizedFileURL
    }

    /// Returns the absolute path to the global store root (`~/.spmx/store` or `SPMX_STORE_DIR`).
    public func storePath() -> String {
        store.rootURL.path
    }

    /// Inspects store entries, compilation cache size, registered projects, and estimated CoW savings.
    public func status() throws -> StoreStatusReport {
        let fileManager = FileManager.default
        let index: StoreIndex
        if fileManager.fileExists(atPath: store.indexURL.path) || fileManager.fileExists(atPath: store.rootURL.path) {
            index = try store.readIndex()
        } else {
            index = StoreIndex()
        }

        let checkoutEntries = scanCheckouts(fileManager: fileManager)
        let repositoryEntries = scanRepositories(fileManager: fileManager)
        let artifactEntries = scanArtifacts(fileManager: fileManager)
        let prebuiltEntries = scanPrebuilts(fileManager: fileManager)

        let checkoutsSize = checkoutEntries.reduce(UInt64(0)) { $0 + $1.sizeBytes }
        let repositoriesSize = repositoryEntries.reduce(UInt64(0)) { $0 + $1.sizeBytes }
        let artifactsSize = artifactEntries.reduce(UInt64(0)) { $0 + $1.sizeBytes }
        let prebuiltsSize = prebuiltEntries.reduce(UInt64(0)) { $0 + $1.sizeBytes }

        let prebuiltsByToolchain = groupPrebuiltsByToolchain(
            entries: prebuiltEntries,
            toolchains: index.toolchains
        )

        let totalStoreSize: UInt64
        if DiagnosticsSupport.isDirectory(atPath: store.rootURL.path, fileManager: fileManager) {
            totalStoreSize = DiagnosticsSupport.directorySizeBytes(
                at: store.rootURL,
                excludingNames: [".locks"],
                fileManager: fileManager
            )
        } else {
            totalStoreSize = 0
        }

        let compilationCacheSize = DiagnosticsSupport.directorySizeBytes(
            at: compilationCacheURL,
            fileManager: fileManager
        )

        var activeProjects: [StoreIndex.RegisteredProject] = []
        var missingProjectsCount = 0
        for project in index.projects.values {
            if DiagnosticsSupport.isDirectory(atPath: project.path, fileManager: fileManager) {
                activeProjects.append(project)
            } else {
                missingProjectsCount += 1
            }
        }

        let (estimatedSavings, projectSavings) = computeSavings(
            activeProjects: activeProjects,
            checkouts: checkoutEntries,
            repositories: repositoryEntries,
            artifacts: artifactEntries,
            prebuilts: prebuiltEntries,
            fileManager: fileManager
        )

        return StoreStatusReport(
            storePath: store.rootURL.path,
            checkoutsCount: checkoutEntries.count,
            checkoutsSizeBytes: checkoutsSize,
            repositoriesCount: repositoryEntries.count,
            repositoriesSizeBytes: repositoriesSize,
            artifactsCount: artifactEntries.count,
            artifactsSizeBytes: artifactsSize,
            prebuiltsCount: prebuiltEntries.count,
            prebuiltsSizeBytes: prebuiltsSize,
            prebuiltsByToolchain: prebuiltsByToolchain,
            logicalStoreSizeBytes: totalStoreSize,
            compilationCachePath: compilationCacheURL.path,
            compilationCacheSizeBytes: compilationCacheSize,
            activeProjectsCount: activeProjects.count,
            missingProjectsCount: missingProjectsCount,
            excludedProjects: index.excludedProjects.keys.sorted(),
            projectSavings: projectSavings,
            estimatedCoWSavingsBytes: estimatedSavings
        )
    }

    /// Lists all cached `(package, version/revision)` slices in `~/.spmx/store` with semantic versions and linked projects.
    public func list() throws -> StoreListReport {
        let fileManager = FileManager.default
        let index: StoreIndex
        if fileManager.fileExists(atPath: store.indexURL.path) || fileManager.fileExists(atPath: store.rootURL.path) {
            index = try store.readIndex()
        } else {
            index = StoreIndex()
        }

        let checkoutEntries = scanCheckouts(fileManager: fileManager)
        let repositoryEntries = scanRepositories(fileManager: fileManager)
        let templates = PackageSyncEngine(store: store, fileManager: fileManager).loadAllPackageTemplates()
        var templateByFolder: [String: PackageSyncEngine.PackageTemplateRecord] = [:]
        for record in templates {
            let folderKey = sanitizeStoreComponent("\(record.identity.lowercased())-\(record.revision)").lowercased()
            templateByFolder[folderKey] = record
        }

        let activeProjects = index.projects.values
            .filter { DiagnosticsSupport.isDirectory(atPath: $0.path, fileManager: fileManager) }
            .sorted { $0.path < $1.path }

        // Precompute refs for projects without pinnedDependencies
        var fallbackProjectRefs: [String: ProjectReferences] = [:]
        for project in activeProjects where project.pinnedDependencies.isEmpty {
            fallbackProjectRefs[project.path] = collectProjectReferences(for: project, fileManager: fileManager)
        }

        let packages: [StorePackageSlice] = checkoutEntries.map { entry in
            let template = templateByFolder[entry.folderName.lowercased()]
            let identity = template?.identity.lowercased() ?? entry.identity
            let revision = template?.revision ?? extractRevisionFromCheckoutFolder(entry.folderName, identity: identity)

            var linked: [String] = []
            var resolvedVersion = template?.version
            var resolvedBranch = template?.branch
            var resolvedLocation = template?.location

            for project in activeProjects {
                if !project.pinnedDependencies.isEmpty {
                    if let matchedPin = project.pinnedDependencies.first(where: { pin in
                        pin.identity.lowercased() == identity && (pin.revision == revision || revision.isEmpty)
                    }) {
                        linked.append(project.path)
                        if resolvedVersion == nil { resolvedVersion = matchedPin.version }
                        if resolvedBranch == nil { resolvedBranch = matchedPin.branch }
                        if resolvedLocation == nil { resolvedLocation = matchedPin.location }
                    }
                } else if let refs = fallbackProjectRefs[project.path] {
                    if refs.checkoutFolderNames.contains(entry.folderName)
                        || refs.fallbackIdentities.contains(identity) {
                        linked.append(project.path)
                    }
                }
            }

            return StorePackageSlice(
                identity: identity,
                version: resolvedVersion,
                branch: resolvedBranch,
                revision: revision,
                location: resolvedLocation,
                sizeBytes: entry.sizeBytes,
                linkedProjects: linked.sorted()
            )
        }
        .sorted { lhs, rhs in
            if lhs.identity != rhs.identity {
                return lhs.identity < rhs.identity
            }
            let lhsVer = lhs.version ?? lhs.branch ?? lhs.revision
            let rhsVer = rhs.version ?? rhs.branch ?? rhs.revision
            return lhsVer < rhsVer
        }

        return StoreListReport(
            storePath: store.rootURL.path,
            packages: packages,
            repositoriesCount: repositoryEntries.count,
            repositoriesSizeBytes: repositoryEntries.reduce(UInt64(0)) { $0 + $1.sizeBytes },
            totalCheckoutsSizeBytes: checkoutEntries.reduce(UInt64(0)) { $0 + $1.sizeBytes }
        )
    }

    /// Removes stale project registrations, unreferenced store entries, and old compilation cache items.
    public func prune(options: PruneOptions = PruneOptions()) throws -> PruneReport {
        let fileManager = FileManager.default
        let storeExists = fileManager.fileExists(atPath: store.rootURL.path)
        let index: StoreIndex
        if storeExists {
            index = try store.readIndex()
        } else {
            index = StoreIndex()
        }

        var missingProjectKeys: [String] = []
        var activeProjects: [StoreIndex.RegisteredProject] = []

        for (key, project) in index.projects.sorted(by: { $0.key < $1.key }) {
            if DiagnosticsSupport.isDirectory(atPath: project.path, fileManager: fileManager) {
                activeProjects.append(project)
            } else {
                missingProjectKeys.append(key)
            }
        }

        if !options.dryRun && storeExists {
            try store.updateIndex { mutableIndex in
                for key in missingProjectKeys {
                    mutableIndex.projects.removeValue(forKey: key)
                }
                mutableIndex.autoPrune.lastPrunedAt = options.now
            }
        }

        let references = collectActiveReferences(
            from: activeProjects,
            fileManager: fileManager
        )

        let cutoffDate: Date? = options.olderThanDays > 0
            ? options.now.addingTimeInterval(-Double(options.olderThanDays) * 86_400)
            : nil

        var removedCheckouts: [String] = []
        var removedArtifacts: [String] = []
        var removedPrebuilts: [String] = []
        var removedCacheEntries: [String] = []
        var reclaimedBytes: UInt64 = 0

        // 1. Prune unreferenced checkouts
        for entry in scanCheckouts(fileManager: fileManager) {
            let isReferenced = references.checkoutFolderNames.contains(entry.folderName)
                || references.fallbackIdentities.contains { entry.folderName.hasPrefix("\($0)-") }
            guard !isReferenced else { continue }
            guard isEligibleForPrune(url: entry.url, cutoffDate: cutoffDate, fileManager: fileManager) else {
                continue
            }

            removedCheckouts.append(entry.url.path)
            reclaimedBytes += entry.sizeBytes
            if !options.dryRun {
                try fileManager.removeItem(at: entry.url)
            }
        }

        // 2. Prune unreferenced artifacts
        for entry in scanArtifacts(fileManager: fileManager) {
            let isReferenced = references.artifactKeys.contains(entry.relativeKey)
                || references.fallbackIdentities.contains(entry.identity)
            guard !isReferenced else { continue }
            guard isEligibleForPrune(url: entry.url, cutoffDate: cutoffDate, fileManager: fileManager) else {
                continue
            }

            removedArtifacts.append(entry.url.path)
            reclaimedBytes += entry.sizeBytes
            if !options.dryRun {
                try fileManager.removeItem(at: entry.url)
                removeDirectoryIfEmpty(entry.url.deletingLastPathComponent(), fileManager: fileManager)
            }
        }

        // 3. Prune unreferenced prebuilts
        for entry in scanPrebuilts(fileManager: fileManager) {
            let isReferenced = references.prebuiltKeys.contains(entry.relativeKey)
                || references.wildcardPrebuiltEntries.contains(entry.entryName)
                || references.fallbackToolchainIdentities.contains("\(entry.toolchainHash)/\(entry.identity)")
            guard !isReferenced else { continue }
            guard isEligibleForPrune(url: entry.url, cutoffDate: cutoffDate, fileManager: fileManager) else {
                continue
            }

            removedPrebuilts.append(entry.url.path)
            reclaimedBytes += entry.sizeBytes
            if !options.dryRun {
                try fileManager.removeItem(at: entry.url)
                removeDirectoryIfEmpty(entry.url.deletingLastPathComponent(), fileManager: fileManager)
            }
        }

        // 4. Prune old compilation-cache entries
        if DiagnosticsSupport.isDirectory(atPath: compilationCacheURL.path, fileManager: fileManager) {
            let cacheResult = try pruneCompilationCache(
                at: compilationCacheURL,
                cutoffDate: cutoffDate,
                dryRun: options.dryRun,
                fileManager: fileManager
            )
            removedCacheEntries = cacheResult.removedPaths
            reclaimedBytes += cacheResult.reclaimedBytes
        }

        return PruneReport(
            dryRun: options.dryRun,
            removedMissingProjects: missingProjectKeys.sorted(),
            removedCheckouts: removedCheckouts.sorted(),
            removedArtifacts: removedArtifacts.sorted(),
            removedPrebuilts: removedPrebuilts.sorted(),
            removedCompilationCacheEntries: removedCacheEntries.sorted(),
            reclaimedBytes: reclaimedBytes
        )
    }

    // MARK: - Periodic Auto-Prune Reminder

    public static let autoPruneDaysEnvironmentKey = "SPMX_AUTO_PRUNE_DAYS"

    /// Evaluates whether the periodic store prune reminder is due based on `index.json` (`autoPrune`)
    /// and optional `SPMX_AUTO_PRUNE_DAYS` override.
    public func evaluateAutoPrune(
        now: Date = Date(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> AutoPruneEvaluation {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: store.indexURL.path) else {
            var enabled = false
            var intervalDays = StoreIndex.AutoPruneConfig.defaultIntervalDays
            if let rawEnv = environment[Self.autoPruneDaysEnvironmentKey]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               let parsedDays = Int(rawEnv),
               parsedDays > 0 {
                enabled = true
                intervalDays = parsedDays
            }
            return AutoPruneEvaluation(
                enabled: enabled,
                intervalDays: intervalDays,
                lastPrunedAt: nil,
                referenceDate: nil,
                daysSinceLastPrune: nil,
                isDue: false
            )
        }

        let index = try store.readIndex()
        var enabled = index.autoPrune.enabled
        var intervalDays = max(1, index.autoPrune.intervalDays)

        if let rawEnv = environment[Self.autoPruneDaysEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let parsedDays = Int(rawEnv) {
            if parsedDays <= 0 {
                enabled = false
            } else {
                enabled = true
                intervalDays = parsedDays
            }
        }

        let referenceDate = index.autoPrune.lastPrunedAt
            ?? index.projects.values.map(\.registeredAt).min()

        guard let referenceDate else {
            return AutoPruneEvaluation(
                enabled: enabled,
                intervalDays: intervalDays,
                lastPrunedAt: index.autoPrune.lastPrunedAt,
                referenceDate: nil,
                daysSinceLastPrune: nil,
                isDue: false
            )
        }

        let elapsedSeconds = max(0, now.timeIntervalSince(referenceDate))
        let daysElapsed = Int(floor(elapsedSeconds / 86_400.0))
        let isDue = enabled && (daysElapsed >= intervalDays)

        return AutoPruneEvaluation(
            enabled: enabled,
            intervalDays: intervalDays,
            lastPrunedAt: index.autoPrune.lastPrunedAt,
            referenceDate: referenceDate,
            daysSinceLastPrune: daysElapsed,
            isDue: isDue
        )
    }

    /// Checks if periodic prune is due and prompts the user to run prune directly (default),
    /// preview reclaimable space first (`--dry-run`), or skip.
    @discardableResult
    public func runInteractiveAutoPruneIfDue(
        now: Date = Date(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        style: TerminalStyle = .stdout,
        inputReader: () -> String? = { readLine() },
        outputWriter: (String) -> Void = { fputs($0, Darwin.stdout); fflush(Darwin.stdout) }
    ) throws -> AutoPrunePromptOutcome {
        let evaluation = try evaluateAutoPrune(now: now, environment: environment)
        guard evaluation.isDue else {
            return .notDue
        }

        let days = evaluation.daysSinceLastPrune ?? evaluation.intervalDays
        outputWriter("\n")
        outputWriter("  \(style.warningIcon) \(style.yellow(style.bold("Store prune reminder:"))) last prune was \(style.bold("\(days) day(s) ago")) \(style.gray("(configured every \(evaluation.intervalDays) day(s))")).\n")
        outputWriter("  \(style.tip("›")) \(style.tip("Pruning removes cached package versions and compilation cache entries not in use by any current project."))\n")
        outputWriter("  Run prune now, preview reclaimable space first, or skip? [Y/d/n] \(style.gray("(Y = run now, d = dry-run preview, n = skip)")): ")

        let rawChoice = (inputReader() ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if rawChoice.isEmpty || rawChoice == "y" || rawChoice == "yes" || rawChoice == "1" {
            let report = try prune(options: PruneOptions(dryRun: false, olderThanDays: evaluation.intervalDays, now: now))
            let sizeText = DiagnosticsSupport.formatBytes(report.reclaimedBytes)
            outputWriter("  \(style.successIcon) \(style.bold("Prune complete:")) reclaimed \(style.green(style.bold(sizeText))) \(style.gray("(\(report.totalRemovedCount) item(s) removed)")).\n")
            return .prunedDirectly(report)
        }

        if rawChoice == "d" || rawChoice == "dry" || rawChoice == "dry-run" || rawChoice == "preview" || rawChoice == "v" || rawChoice == "2" {
            let preview = try prune(options: PruneOptions(dryRun: true, olderThanDays: evaluation.intervalDays, now: now))
            let previewSize = DiagnosticsSupport.formatBytes(preview.reclaimedBytes)
            outputWriter("  \(style.dryRunBadge()) Would remove \(preview.removedCheckouts.count) checkout(s), \(preview.removedArtifacts.count) artifact(s), \(preview.removedPrebuilts.count) prebuilt(s), \(preview.removedCompilationCacheEntries.count) compilation-cache file(s), and \(preview.removedMissingProjects.count) missing project(s).\n")
            outputWriter("  \(style.bold("Would reclaim:")) \(style.green(style.bold(previewSize)))\n")
            outputWriter("  Execute prune now and reclaim \(previewSize)? [Y/n]: ")

            let confirmChoice = (inputReader() ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if confirmChoice.isEmpty || confirmChoice == "y" || confirmChoice == "yes" {
                let applied = try prune(options: PruneOptions(dryRun: false, olderThanDays: evaluation.intervalDays, now: now))
                let appliedSize = DiagnosticsSupport.formatBytes(applied.reclaimedBytes)
                outputWriter("  \(style.successIcon) \(style.bold("Prune complete:")) reclaimed \(style.green(style.bold(appliedSize))).\n")
                return .previewedAndPruned(preview: preview, applied: applied)
            } else {
                outputWriter("  \(style.gray("◦")) \(style.gray("Skipped prune."))\n")
                return .previewedAndSkipped(preview: preview)
            }
        }

        outputWriter("  \(style.gray("◦")) \(style.gray("Skipped prune (run `spmx prune` anytime)."))\n")
        return .skipped
    }

    // MARK: - Store Scanning

    private struct CheckoutEntry {
        let folderName: String
        let identity: String
        let url: URL
        let sizeBytes: UInt64
    }

    private struct RepositoryEntry {
        let identity: String
        let url: URL
        let sizeBytes: UInt64
    }

    private struct ArtifactEntry {
        let identity: String
        let entryName: String
        let relativeKey: String
        let url: URL
        let sizeBytes: UInt64
    }

    private struct PrebuiltEntry {
        let toolchainHash: String
        let identity: String
        let entryName: String
        let relativeKey: String
        let url: URL
        let sizeBytes: UInt64
    }

    private func scanCheckouts(fileManager: FileManager) -> [CheckoutEntry] {
        guard DiagnosticsSupport.isDirectory(atPath: store.checkoutsDirectory.path, fileManager: fileManager) else {
            return []
        }
        let entries = nonHiddenContents(of: store.checkoutsDirectory, fileManager: fileManager)
        return entries.compactMap { url in
            let name = url.lastPathComponent
            let identity = extractIdentityFromCheckoutFolder(name)
            let size = DiagnosticsSupport.itemSizeBytes(at: url, fileManager: fileManager)
            return CheckoutEntry(folderName: name, identity: identity, url: url, sizeBytes: size)
        }
    }

    private func scanRepositories(fileManager: FileManager) -> [RepositoryEntry] {
        guard DiagnosticsSupport.isDirectory(atPath: store.repositoriesDirectory.path, fileManager: fileManager) else {
            return []
        }
        let entries = nonHiddenContents(of: store.repositoriesDirectory, fileManager: fileManager)
        return entries.compactMap { url in
            let identity = url.lastPathComponent.lowercased()
            let size = DiagnosticsSupport.itemSizeBytes(at: url, fileManager: fileManager)
            return RepositoryEntry(identity: identity, url: url, sizeBytes: size)
        }
    }

    private func extractRevisionFromCheckoutFolder(_ folderName: String, identity: String) -> String {
        let prefix = "\(identity)-"
        if folderName.lowercased().hasPrefix(prefix.lowercased()) {
            return String(folderName.dropFirst(prefix.count))
        }
        if let lastDash = folderName.lastIndex(of: "-") {
            return String(folderName[folderName.index(after: lastDash)...])
        }
        return ""
    }

    private func scanArtifacts(fileManager: FileManager) -> [ArtifactEntry] {
        guard DiagnosticsSupport.isDirectory(atPath: store.artifactsDirectory.path, fileManager: fileManager) else {
            return []
        }
        var results: [ArtifactEntry] = []
        for identityURL in nonHiddenContents(of: store.artifactsDirectory, fileManager: fileManager) {
            guard DiagnosticsSupport.isDirectory(atPath: identityURL.path, fileManager: fileManager) else { continue }
            let identity = identityURL.lastPathComponent.lowercased()
            for itemURL in nonHiddenContents(of: identityURL, fileManager: fileManager) {
                let entryName = itemURL.lastPathComponent
                let size = DiagnosticsSupport.itemSizeBytes(at: itemURL, fileManager: fileManager)
                results.append(ArtifactEntry(
                    identity: identity,
                    entryName: entryName,
                    relativeKey: "\(identity)/\(entryName)",
                    url: itemURL,
                    sizeBytes: size
                ))
            }
        }
        return results
    }

    private func scanPrebuilts(fileManager: FileManager) -> [PrebuiltEntry] {
        guard DiagnosticsSupport.isDirectory(atPath: store.prebuiltsDirectory.path, fileManager: fileManager) else {
            return []
        }
        var results: [PrebuiltEntry] = []
        for toolchainURL in nonHiddenContents(of: store.prebuiltsDirectory, fileManager: fileManager) {
            guard DiagnosticsSupport.isDirectory(atPath: toolchainURL.path, fileManager: fileManager) else { continue }
            let toolchainHash = toolchainURL.lastPathComponent
            for itemURL in nonHiddenContents(of: toolchainURL, fileManager: fileManager) {
                let entryName = itemURL.lastPathComponent
                let identity = extractIdentityFromPrebuiltFolder(entryName)
                let size = DiagnosticsSupport.itemSizeBytes(at: itemURL, fileManager: fileManager)
                results.append(PrebuiltEntry(
                    toolchainHash: toolchainHash,
                    identity: identity,
                    entryName: entryName,
                    relativeKey: "\(toolchainHash)/\(entryName)",
                    url: itemURL,
                    sizeBytes: size
                ))
            }
        }
        return results
    }

    private func groupPrebuiltsByToolchain(
        entries: [PrebuiltEntry],
        toolchains: [String: StoreIndex.ToolchainRecord]
    ) -> [PrebuiltToolchainGroup] {
        let grouped = Dictionary(grouping: entries, by: \.toolchainHash)
        return grouped.keys.sorted().map { hash in
            let items = grouped[hash] ?? []
            let totalSize = items.reduce(UInt64(0)) { $0 + $1.sizeBytes }
            let fingerprint = toolchains[hash]?.fingerprint
            return PrebuiltToolchainGroup(
                toolchainHash: hash,
                swiftVersion: fingerprint?.swiftVersion,
                xcodeVersion: fingerprint?.xcodeVersion,
                count: items.count,
                sizeBytes: totalSize
            )
        }
    }

    // MARK: - Reference Collection & CoW Estimation

    private struct ActiveReferences {
        var checkoutFolderNames: Set<String> = []
        var artifactKeys: Set<String> = []
        var prebuiltKeys: Set<String> = []
        var wildcardPrebuiltEntries: Set<String> = []
        var fallbackIdentities: Set<String> = []
        var fallbackToolchainIdentities: Set<String> = []
    }

    private struct ProjectReferences {
        var checkoutFolderNames: Set<String> = []
        var artifactKeys: Set<String> = []
        var prebuiltKeys: Set<String> = []
        var wildcardPrebuiltEntries: Set<String> = []
        var fallbackIdentities: Set<String> = []
        var fallbackToolchainIdentities: Set<String> = []
    }

    private func collectActiveReferences(
        from activeProjects: [StoreIndex.RegisteredProject],
        fileManager: FileManager
    ) -> ActiveReferences {
        var combined = ActiveReferences()
        for project in activeProjects {
            let projRefs = collectProjectReferences(for: project, fileManager: fileManager)
            combined.checkoutFolderNames.formUnion(projRefs.checkoutFolderNames)
            combined.artifactKeys.formUnion(projRefs.artifactKeys)
            combined.prebuiltKeys.formUnion(projRefs.prebuiltKeys)
            combined.wildcardPrebuiltEntries.formUnion(projRefs.wildcardPrebuiltEntries)
            combined.fallbackIdentities.formUnion(projRefs.fallbackIdentities)
            combined.fallbackToolchainIdentities.formUnion(projRefs.fallbackToolchainIdentities)
        }
        return combined
    }

    private func collectProjectReferences(
        for project: StoreIndex.RegisteredProject,
        fileManager: FileManager
    ) -> ProjectReferences {
        var refs = ProjectReferences()
        var foundResolvedOrWorkspaceState = false

        let detected = try? ProjectDetector.detect(in: project.path, fileManager: fileManager)

        // 1. Collect Package.resolved pins
        var resolvedPaths = detected?.allPackageResolvedPaths ?? []
        let directResolved = URL(fileURLWithPath: project.path).appendingPathComponent("Package.resolved").path
        if fileManager.fileExists(atPath: directResolved) && !resolvedPaths.contains(directResolved) {
            resolvedPaths.append(directResolved)
        }

        var activePins: [PackagePin] = []
        for resolvedPath in resolvedPaths {
            guard let parsed = try? PackageResolvedParser.parse(fileAt: resolvedPath, fileManager: fileManager) else {
                continue
            }
            foundResolvedOrWorkspaceState = true
            activePins.append(contentsOf: parsed.pins)
            for pin in parsed.pins {
                let identity = pin.identity.lowercased()
                if let revision = pin.revision, !revision.isEmpty {
                    let folder = sanitizeStoreComponent("\(identity)-\(revision)")
                    refs.checkoutFolderNames.insert(folder)

                    // Also consult store package templates for associated artifacts when DerivedData isn't present.
                    if let templateArtifacts = loadPackageTemplateArtifacts(identity: identity, revision: revision) {
                        for artifact in templateArtifacts {
                            let key = "\(identity)/\(sanitizeStoreComponent("\(artifact.targetName)-\(artifact.checksum)"))"
                            refs.artifactKeys.insert(key)
                        }
                    }
                }
            }
        }

        // 2. Collect workspace-state.json references
        let workspaceStatePaths = candidateWorkspaceStatePaths(
            for: project,
            detected: detected,
            fileManager: fileManager
        )
        var parsedWorkspaceState = false
        for wsPath in workspaceStatePaths {
            guard let ws = try? WorkspaceStateParser.parse(fileAt: wsPath, fileManager: fileManager) else {
                continue
            }
            foundResolvedOrWorkspaceState = true
            parsedWorkspaceState = true

            for dep in ws.dependencies {
                let identity = dep.packageRef.identity.lowercased()
                if let rev = dep.state.checkoutState?.revision, !rev.isEmpty {
                    refs.checkoutFolderNames.insert(sanitizeStoreComponent("\(identity)-\(rev)"))
                }
            }

            for artifact in ws.artifacts {
                let identity = artifact.packageRef.identity.lowercased()
                if let checksum = artifact.checksum, !checksum.isEmpty {
                    let key = "\(identity)/\(sanitizeStoreComponent("\(artifact.targetName)-\(checksum)"))"
                    refs.artifactKeys.insert(key)
                }
            }

            for prebuilt in ws.prebuilts {
                let identity = prebuilt.identity.lowercased()
                if let voc = prebuilt.checksum ?? prebuilt.version, !voc.isEmpty {
                    let entryName = sanitizeStoreComponent("\(identity)-\(voc)")
                    if let tcHash = project.toolchainHash {
                        refs.prebuiltKeys.insert("\(sanitizeStoreComponent(tcHash))/\(entryName)")
                    } else {
                        refs.wildcardPrebuiltEntries.insert(entryName)
                    }
                }
            }
        }

        // 3. If workspace-state.json wasn't on disk, check store prebuilt templates matching active pins + toolchain
        if !parsedWorkspaceState, let tcHash = project.toolchainHash, !activePins.isEmpty {
            let pinMap = Dictionary(grouping: activePins, by: { $0.identity.lowercased() })
            for template in loadPrebuiltTemplates(toolchainHash: tcHash) {
                guard let matchingPins = pinMap[template.identity.lowercased()] else { continue }
                let matches = matchingPins.contains { pin in
                    if let tRev = template.revision, let pRev = pin.revision { return tRev == pRev }
                    if let tVer = template.version, let pVer = pin.version { return tVer == pVer }
                    return template.revision == nil && template.version == nil
                }
                if matches {
                    let entryName = sanitizeStoreComponent("\(template.identity.lowercased())-\(template.versionOrChecksum)")
                    refs.prebuiltKeys.insert("\(sanitizeStoreComponent(tcHash))/\(entryName)")
                }
            }
        }

        // 4. Fallback to registered identities from index.json when neither Package.resolved nor workspace-state exists
        if !foundResolvedOrWorkspaceState {
            for identity in project.packageIdentities {
                let normalized = sanitizeStoreComponent(identity.lowercased())
                refs.fallbackIdentities.insert(normalized)
                if let tcHash = project.toolchainHash {
                    refs.fallbackToolchainIdentities.insert("\(sanitizeStoreComponent(tcHash))/\(normalized)")
                }
            }
        }

        return refs
    }

    private func computeSavings(
        activeProjects: [StoreIndex.RegisteredProject],
        checkouts: [CheckoutEntry],
        repositories: [RepositoryEntry],
        artifacts: [ArtifactEntry],
        prebuilts: [PrebuiltEntry],
        fileManager: FileManager
    ) -> (totalSavings: UInt64, projectSavings: [ProjectSavingsSummary]) {
        let sortedProjects = activeProjects.sorted { $0.path < $1.path }
        guard !sortedProjects.isEmpty, APFSCloner.isAPFS(at: store.rootURL) else {
            return (0, sortedProjects.map {
                ProjectSavingsSummary(
                    projectPath: $0.path,
                    sharedPackagesCount: $0.packageIdentities.count,
                    projectSavedBytes: 0
                )
            })
        }

        var totalSavings: UInt64 = 0
        var summaries: [ProjectSavingsSummary] = []

        for project in sortedProjects {
            let refs = collectProjectReferences(for: project, fileManager: fileManager)
            var projectBytes: UInt64 = 0
            var matchedIdentities: Set<String> = []

            for entry in checkouts {
                let matches = refs.checkoutFolderNames.contains(entry.folderName)
                    || refs.fallbackIdentities.contains { entry.folderName.hasPrefix("\($0)-") }
                if matches {
                    projectBytes += entry.sizeBytes
                    matchedIdentities.insert(entry.identity)
                }
            }

            for entry in repositories {
                let matches = refs.fallbackIdentities.contains(entry.identity)
                    || refs.checkoutFolderNames.contains(where: { $0.hasPrefix("\(entry.identity)-") })
                if matches {
                    projectBytes += entry.sizeBytes
                    matchedIdentities.insert(entry.identity)
                }
            }

            for entry in artifacts {
                let matches = refs.artifactKeys.contains(entry.relativeKey)
                    || refs.fallbackIdentities.contains(entry.identity)
                if matches {
                    projectBytes += entry.sizeBytes
                    matchedIdentities.insert(entry.identity)
                }
            }

            for entry in prebuilts {
                let matches = refs.prebuiltKeys.contains(entry.relativeKey)
                    || refs.wildcardPrebuiltEntries.contains(entry.entryName)
                    || refs.fallbackToolchainIdentities.contains("\(entry.toolchainHash)/\(entry.identity)")
                if matches {
                    projectBytes += entry.sizeBytes
                    matchedIdentities.insert(entry.identity)
                }
            }

            totalSavings += projectBytes
            summaries.append(ProjectSavingsSummary(
                projectPath: project.path,
                sharedPackagesCount: max(matchedIdentities.count, project.packageIdentities.count),
                projectSavedBytes: projectBytes
            ))
        }

        return (totalSavings, summaries)
    }

    private func candidateWorkspaceStatePaths(
        for project: StoreIndex.RegisteredProject,
        detected: DetectedProject?,
        fileManager: FileManager
    ) -> [String] {
        var candidates: [String] = []
        let projectURL = URL(fileURLWithPath: project.path)

        if let detected {
            switch detected.type {
            case .swiftPackage:
                candidates.append(
                    URL(fileURLWithPath: detected.rootPath)
                        .appendingPathComponent(".build")
                        .appendingPathComponent("workspace-state.json").path
                )
            case .xcode, .flutter:
                if let containerPath = detected.containerPath {
                    candidates.append(
                        DerivedDataPathCalculator.derivedDataURL(
                            forContainerPath: containerPath,
                            fileManager: fileManager
                        )
                        .appendingPathComponent("SourcePackages")
                        .appendingPathComponent("workspace-state.json").path
                    )
                }
            }
        }

        candidates.append(
            projectURL.appendingPathComponent(".build").appendingPathComponent("workspace-state.json").path
        )
        candidates.append(
            projectURL.appendingPathComponent("SourcePackages").appendingPathComponent("workspace-state.json").path
        )

        var seen: Set<String> = []
        return candidates.filter { seen.insert($0).inserted && fileManager.fileExists(atPath: $0) }
    }

    // MARK: - Store Template Inspection Helpers

    private struct TemplateArtifactSummary: Decodable {
        let targetName: String
        let checksum: String
    }

    private struct PackageTemplateSummary: Decodable {
        let artifacts: [TemplateArtifactSummary]
    }

    private struct PrebuiltTemplateSummary: Decodable {
        let identity: String
        let revision: String?
        let version: String?
        let versionOrChecksum: String
    }

    private func loadPackageTemplateArtifacts(identity: String, revision: String) -> [TemplateArtifactSummary]? {
        let filename = "\(sanitizeStoreComponent(identity))-\(sanitizeStoreComponent(revision)).json"
        let url = store.rootURL
            .appendingPathComponent("templates")
            .appendingPathComponent("packages")
            .appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(PackageTemplateSummary.self, from: data) else {
            return nil
        }
        return decoded.artifacts
    }

    private func loadPrebuiltTemplates(toolchainHash: String) -> [PrebuiltTemplateSummary] {
        let dir = store.rootURL
            .appendingPathComponent("templates")
            .appendingPathComponent("prebuilts")
            .appendingPathComponent(sanitizeStoreComponent(toolchainHash))
        let fileManager = FileManager.default
        guard DiagnosticsSupport.isDirectory(atPath: dir.path, fileManager: fileManager) else {
            return []
        }
        let decoder = JSONDecoder()
        return nonHiddenContents(of: dir, fileManager: fileManager).compactMap { url in
            guard url.pathExtension == "json", let data = try? Data(contentsOf: url) else {
                return nil
            }
            return try? decoder.decode(PrebuiltTemplateSummary.self, from: data)
        }
    }

    // MARK: - Compilation Cache Pruning & Filesystem Helpers

    private func pruneCompilationCache(
        at rootURL: URL,
        cutoffDate: Date?,
        dryRun: Bool,
        fileManager: FileManager
    ) throws -> (removedPaths: [String], reclaimedBytes: UInt64) {
        var removedPaths: [String] = []
        var reclaimedBytes: UInt64 = 0

        for entryURL in nonHiddenContents(of: rootURL, fileManager: fileManager) {
            if DiagnosticsSupport.isDirectory(atPath: entryURL.path, fileManager: fileManager) {
                let dirSize = DiagnosticsSupport.itemSizeBytes(at: entryURL, fileManager: fileManager)
                if isDirectoryTreeEligibleForPrune(entryURL, cutoffDate: cutoffDate, fileManager: fileManager) {
                    removedPaths.append(entryURL.path)
                    reclaimedBytes += dirSize
                    if !dryRun {
                        try fileManager.removeItem(at: entryURL)
                    }
                } else {
                    let nested = try pruneCompilationCache(
                        at: entryURL,
                        cutoffDate: cutoffDate,
                        dryRun: dryRun,
                        fileManager: fileManager
                    )
                    removedPaths.append(contentsOf: nested.removedPaths)
                    reclaimedBytes += nested.reclaimedBytes
                    if !dryRun {
                        removeDirectoryIfEmpty(entryURL, fileManager: fileManager)
                    }
                }
            } else {
                guard isEligibleForPrune(url: entryURL, cutoffDate: cutoffDate, fileManager: fileManager) else {
                    continue
                }
                let size = DiagnosticsSupport.itemSizeBytes(at: entryURL, fileManager: fileManager)
                removedPaths.append(entryURL.path)
                reclaimedBytes += size
                if !dryRun {
                    try fileManager.removeItem(at: entryURL)
                }
            }
        }

        return (removedPaths, reclaimedBytes)
    }

    private func isDirectoryTreeEligibleForPrune(
        _ directoryURL: URL,
        cutoffDate: Date?,
        fileManager: FileManager
    ) -> Bool {
        guard let cutoffDate else { return true }
        guard isEligibleForPrune(url: directoryURL, cutoffDate: cutoffDate, fileManager: fileManager) else {
            return false
        }
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return true
        }
        for case let childURL as URL in enumerator {
            if !isEligibleForPrune(url: childURL, cutoffDate: cutoffDate, fileManager: fileManager) {
                return false
            }
        }
        return true
    }

    private func isEligibleForPrune(
        url: URL,
        cutoffDate: Date?,
        fileManager: FileManager
    ) -> Bool {
        guard let cutoffDate else { return true }
        let attrs = try? fileManager.attributesOfItem(atPath: url.path)
        let modDate = (attrs?[.modificationDate] as? Date)
            ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? Date.distantPast
        return modDate <= cutoffDate
    }

    private func nonHiddenContents(of directoryURL: URL, fileManager: FileManager) -> [URL] {
        let entries = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return entries.map { directoryURL.appendingPathComponent($0.lastPathComponent) }
    }

    private func removeDirectoryIfEmpty(_ directoryURL: URL, fileManager: FileManager) {
        guard DiagnosticsSupport.isDirectory(atPath: directoryURL.path, fileManager: fileManager) else { return }
        let remaining = (try? fileManager.contentsOfDirectory(atPath: directoryURL.path)) ?? []
        if remaining.isEmpty {
            try? fileManager.removeItem(at: directoryURL)
        }
    }

    private func sanitizeStoreComponent(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
    }

    private func extractIdentityFromCheckoutFolder(_ name: String) -> String {
        guard let lastHyphen = name.lastIndex(of: "-") else {
            return name.lowercased()
        }
        let stem = String(name[..<lastHyphen]).lowercased()
        return stem.isEmpty ? name.lowercased() : stem
    }

    private func extractIdentityFromPrebuiltFolder(_ name: String) -> String {
        guard let lastHyphen = name.lastIndex(of: "-") else {
            return name.lowercased()
        }
        let stem = String(name[..<lastHyphen]).lowercased()
        return stem.isEmpty ? name.lowercased() : stem
    }
}

// MARK: - Internal Shared Diagnostics Support

enum DiagnosticsSupport {
    struct SemanticVersion: Sendable, Equatable, Comparable {
        let major: Int
        let minor: Int
        let patch: Int

        static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
            if lhs.major != rhs.major { return lhs.major < rhs.major }
            if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
            return lhs.patch < rhs.patch
        }
    }

    static func isDirectory(atPath path: String, fileManager: FileManager = .default) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    static func itemSizeBytes(at url: URL, fileManager: FileManager = .default) -> UInt64 {
        if isDirectory(atPath: url.path, fileManager: fileManager) {
            return directorySizeBytes(at: url, fileManager: fileManager)
        }
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let size = values.fileSize else {
            if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? NSNumber {
                return size.uint64Value
            }
            return 0
        }
        return UInt64(max(0, size))
    }

    static func directorySizeBytes(
        at url: URL,
        excludingNames: Set<String> = [],
        fileManager: FileManager = .default
    ) -> UInt64 {
        guard isDirectory(atPath: url.path, fileManager: fileManager) else {
            return 0
        }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: []
        ) else {
            return 0
        }

        var total: UInt64 = 0
        for case let itemURL as URL in enumerator {
            if excludingNames.contains(itemURL.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? itemURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            ) else {
                continue
            }
            if values.isSymbolicLink == true {
                continue
            }
            if values.isRegularFile == true, let size = values.fileSize {
                total += UInt64(max(0, size))
            }
        }
        return total
    }

    static func parseSwiftVersion(from output: String) -> SemanticVersion? {
        extractVersion(from: output, pattern: #"Swift version\s+(\d+)\.(\d+)(?:\.(\d+))?"#)
    }

    static func parseXcodeVersion(from output: String) -> SemanticVersion? {
        extractVersion(from: output, pattern: #"Xcode\s+(\d+)\.(\d+)(?:\.(\d+))?"#)
    }

    static func supportsCompilationCache(swiftVersion: String?, xcodeVersion: String?) -> Bool {
        if let xcodeVersion, let ver = parseXcodeVersion(from: xcodeVersion), ver.major >= 16 {
            return true
        }
        if let swiftVersion, let ver = parseSwiftVersion(from: swiftVersion), ver.major >= 6 {
            return true
        }
        return false
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))))
    }

    private static func extractVersion(from text: String, pattern: String) -> SemanticVersion? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let majorRange = Range(match.range(at: 1), in: text),
              let minorRange = Range(match.range(at: 2), in: text),
              let major = Int(text[majorRange]),
              let minor = Int(text[minorRange]) else {
            return nil
        }
        let patch: Int
        if match.range(at: 3).location != NSNotFound,
           let patchRange = Range(match.range(at: 3), in: text),
           let parsedPatch = Int(text[patchRange]) {
            patch = parsedPatch
        } else {
            patch = 0
        }
        return SemanticVersion(major: major, minor: minor, patch: patch)
    }
}

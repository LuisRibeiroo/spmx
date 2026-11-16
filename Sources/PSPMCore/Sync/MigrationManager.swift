import Darwin
import Foundation

/// Configuration options for scanning and migrating existing projects/worktrees into ``GlobalStore``.
public struct MigrationOptions: Sendable {
    public var searchRoots: [String]
    public var dryRun: Bool
    public var deduplicate: Bool
    public var maxDepth: Int
    public var excludePatterns: [String]
    public var includeGitWorktreeDiscovery: Bool
    public var installRepoHooks: Bool
    public var commandTimeout: TimeInterval?
    public var verboseLogger: (@Sendable (String) -> Void)?

    public init(
        searchRoots: [String] = [FileManager.default.currentDirectoryPath],
        dryRun: Bool = true,
        deduplicate: Bool = true,
        maxDepth: Int = 6,
        excludePatterns: [String] = [],
        includeGitWorktreeDiscovery: Bool = true,
        installRepoHooks: Bool = false,
        commandTimeout: TimeInterval? = CommandExecutor.resolveDefaultTimeout(),
        verboseLogger: (@Sendable (String) -> Void)? = nil
    ) {
        self.searchRoots = searchRoots
        self.dryRun = dryRun
        self.deduplicate = deduplicate
        self.maxDepth = maxDepth
        self.excludePatterns = excludePatterns
        self.includeGitWorktreeDiscovery = includeGitWorktreeDiscovery
        self.installRepoHooks = installRepoHooks
        self.commandTimeout = commandTimeout
        self.verboseLogger = verboseLogger
    }
}

/// Per-project migration outcome produced by ``MigrationManager``.
public struct MigratedProjectOutcome: Sendable, Equatable {
    public let project: DetectedProject
    public let sourcePackagesPaths: [String]
    public let existingCacheBytes: UInt64
    public let hasExistingCache: Bool
    public let harvestedCheckoutsCount: Int
    public let harvestedArtifactsCount: Int
    public let harvestedPrebuiltsCount: Int
    public let deduplicatedCheckoutsCount: Int
    public let deduplicatedArtifactsCount: Int
    public let deduplicatedPrebuiltsCount: Int
    public let skippedLocallyModifiedCount: Int
    public let estimatedReclaimedBytes: UInt64
    public let recordedFlutterResolved: Bool
    public let installedRepoHook: Bool
    public let skippedReason: String?

    public var totalHarvestedItemsCount: Int {
        harvestedCheckoutsCount + harvestedArtifactsCount + harvestedPrebuiltsCount
    }

    public var totalDeduplicatedItemsCount: Int {
        deduplicatedCheckoutsCount + deduplicatedArtifactsCount + deduplicatedPrebuiltsCount
    }

    public init(
        project: DetectedProject,
        sourcePackagesPaths: [String],
        existingCacheBytes: UInt64,
        hasExistingCache: Bool,
        harvestedCheckoutsCount: Int,
        harvestedArtifactsCount: Int,
        harvestedPrebuiltsCount: Int,
        deduplicatedCheckoutsCount: Int,
        deduplicatedArtifactsCount: Int,
        deduplicatedPrebuiltsCount: Int,
        skippedLocallyModifiedCount: Int,
        estimatedReclaimedBytes: UInt64,
        recordedFlutterResolved: Bool,
        installedRepoHook: Bool,
        skippedReason: String? = nil
    ) {
        self.project = project
        self.sourcePackagesPaths = sourcePackagesPaths
        self.existingCacheBytes = existingCacheBytes
        self.hasExistingCache = hasExistingCache
        self.harvestedCheckoutsCount = harvestedCheckoutsCount
        self.harvestedArtifactsCount = harvestedArtifactsCount
        self.harvestedPrebuiltsCount = harvestedPrebuiltsCount
        self.deduplicatedCheckoutsCount = deduplicatedCheckoutsCount
        self.deduplicatedArtifactsCount = deduplicatedArtifactsCount
        self.deduplicatedPrebuiltsCount = deduplicatedPrebuiltsCount
        self.skippedLocallyModifiedCount = skippedLocallyModifiedCount
        self.estimatedReclaimedBytes = estimatedReclaimedBytes
        self.recordedFlutterResolved = recordedFlutterResolved
        self.installedRepoHook = installedRepoHook
        self.skippedReason = skippedReason
    }
}

/// Live progress notifications emitted by ``MigrationManager/migrate(options:progressObserver:)``.
public enum MigrationProgressEvent: Sendable, Equatable {
    case scanning(root: String)
    case discovered(projectRoot: String, type: ProjectType)
    case processing(projectRoot: String, type: ProjectType)
    case stage(projectRoot: String, type: ProjectType, detail: String)
    case completed(MigratedProjectOutcome)
}

/// Aggregate summary returned by ``MigrationManager/migrate(options:progressObserver:)``.
public struct MigrationReport: Sendable, Equatable {
    public let scannedRoots: [String]
    public let dryRun: Bool
    public let deduplicate: Bool
    public let outcomes: [MigratedProjectOutcome]

    public var discoveredCount: Int { outcomes.count }
    public var projectsWithExistingCacheCount: Int { outcomes.filter(\.hasExistingCache).count }
    public var migratedCount: Int {
        outcomes.filter { $0.hasExistingCache || $0.recordedFlutterResolved || $0.installedRepoHook }.count
    }
    public var totalExistingCacheBytes: UInt64 {
        outcomes.reduce(0) { $0 + $1.existingCacheBytes }
    }
    public var totalHarvestedItemsCount: Int {
        outcomes.reduce(0) { $0 + $1.totalHarvestedItemsCount }
    }
    public var totalDeduplicatedItemsCount: Int {
        outcomes.reduce(0) { $0 + $1.totalDeduplicatedItemsCount }
    }
    public var totalEstimatedReclaimedBytes: UInt64 {
        outcomes.reduce(0) { $0 + $1.estimatedReclaimedBytes }
    }

    public init(
        scannedRoots: [String],
        dryRun: Bool,
        deduplicate: Bool,
        outcomes: [MigratedProjectOutcome]
    ) {
        self.scannedRoots = scannedRoots
        self.dryRun = dryRun
        self.deduplicate = deduplicate
        self.outcomes = outcomes
    }
}

/// Scans directory trees and Git worktrees for existing Flutter, Xcode, and SwiftPM projects,
/// harvesting their package caches into ``GlobalStore`` and optionally deduplicating via APFS CoW clones.
public struct MigrationManager: Sendable {
    public typealias ActiveCommandsProvider = @Sendable () -> [String]

    private struct SendableFileManager: @unchecked Sendable {
        let value: FileManager
    }

    private static let alwaysIgnoredDirectoryNames: Set<String> = [
        "DerivedData", "node_modules", "Pods", "ephemeral", "Carthage",
        "SourcePackages", "checkouts", "artifacts", "prebuilts", "build", "dist", "target",
        "__pycache__", "venv"
    ]

    private static let homeTopLevelIgnoredNames: Set<String> = [
        "Library", "Movies", "Music", "Pictures", "Photos", "Public", "Applications",
        "CloudStorage", "Parallels", "Virtual Machines.localized"
    ]

    private static let bundleExtensionsToSkip: Set<String> = [
        "xcworkspace", "xcodeproj", "app", "framework", "xcframework",
        "bundle", "playground", "doccarchive", "pkg", "dmg"
    ]

    private static let activeBuildExecutables: Set<String> = [
        "xcodebuild", "swift-build", "swift-package", "swift-test", "flutter_tools.snapshot"
    ]

    public let store: GlobalStore
    private let syncEngine: PackageSyncEngine
    private let homeDirectory: URL
    private let fileManagerBox: SendableFileManager
    private let activeCommandsProvider: ActiveCommandsProvider

    private var fileManager: FileManager {
        fileManagerBox.value
    }

    public init(
        store: GlobalStore = GlobalStore(),
        toolchainProvider: @escaping PackageSyncEngine.ToolchainProvider = { try ToolchainFingerprint.current() },
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        activeCommandsProvider: @escaping ActiveCommandsProvider = MigrationManager.defaultActiveCommands
    ) {
        self.store = store
        self.syncEngine = PackageSyncEngine(
            store: store,
            toolchainProvider: toolchainProvider,
            fileManager: fileManager
        )
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.fileManagerBox = SendableFileManager(value: fileManager)
        self.activeCommandsProvider = activeCommandsProvider
    }

    /// Scans `options.searchRoots` (and linked Git worktrees) and migrates discovered projects.
    public func migrate(
        options: MigrationOptions = MigrationOptions(),
        progressObserver: (@Sendable (MigrationProgressEvent) -> Void)? = nil
    ) throws -> MigrationReport {
        let rawRoots = options.searchRoots.isEmpty
            ? [fileManager.currentDirectoryPath]
            : options.searchRoots
        let canonicalRoots = rawRoots.map {
            DerivedDataPathCalculator.canonicalizePath($0, currentDirectory: fileManager.currentDirectoryPath)
        }

        let discoveredProjects = discoverProjects(
            in: canonicalRoots,
            maxDepth: max(0, options.maxDepth),
            excludePatterns: options.excludePatterns,
            includeGitWorktrees: options.includeGitWorktreeDiscovery,
            commandTimeout: options.commandTimeout,
            verboseLogger: options.verboseLogger,
            progressObserver: progressObserver
        )

        let activeCommands = activeCommandsProvider()
        var outcomes: [MigratedProjectOutcome] = []
        outcomes.reserveCapacity(discoveredProjects.count)

        for project in discoveredProjects {
            progressObserver?(.processing(projectRoot: project.rootPath, type: project.type))
            let outcome = processProject(
                project,
                options: options,
                activeCommands: activeCommands,
                progressObserver: progressObserver
            )
            outcomes.append(outcome)
            progressObserver?(.completed(outcome))
        }

        return MigrationReport(
            scannedRoots: canonicalRoots,
            dryRun: options.dryRun,
            deduplicate: options.deduplicate,
            outcomes: outcomes
        )
    }

    /// Discovers Flutter, Xcode, and SwiftPM projects within the specified root paths.
    public func discoverProjects(
        in roots: [String],
        maxDepth: Int = 6,
        excludePatterns: [String] = [],
        includeGitWorktrees: Bool = true,
        commandTimeout: TimeInterval? = CommandExecutor.resolveDefaultTimeout(),
        verboseLogger: (@Sendable (String) -> Void)? = nil,
        progressObserver: (@Sendable (MigrationProgressEvent) -> Void)? = nil
    ) -> [DetectedProject] {
        var discoveredByRoot: [String: DetectedProject] = [:]
        var orderedRoots: [String] = []
        var inspectedGitDirs: Set<String> = []
        var pendingGitWorktreeRoots: [String] = []

        func record(_ project: DetectedProject) {
            let key = URL(fileURLWithPath: project.rootPath).standardizedFileURL.resolvingSymlinksInPath().path
            guard discoveredByRoot[key] == nil else { return }
            discoveredByRoot[key] = project
            orderedRoots.append(key)
            progressObserver?(.discovered(projectRoot: project.rootPath, type: project.type))
        }

        for root in roots {
            let rootURL = URL(fileURLWithPath: root).standardizedFileURL
            guard DiagnosticsSupport.isDirectory(atPath: rootURL.path, fileManager: fileManager) else {
                verboseLogger?("Skipping non-existent or non-directory root: \(rootURL.path)")
                continue
            }

            progressObserver?(.scanning(root: rootURL.path))
            let scanningHomeRoot = rootURL.resolvingSymlinksInPath().path == homeDirectory.resolvingSymlinksInPath().path
            let baseDepth = rootURL.pathComponents.count

            // Inspect the root directory itself before enumerating children.
            if let detected = detectProjectIfMarkersPresent(in: rootURL) {
                record(detected)
            }
            if includeGitWorktrees {
                collectGitWorktreeRoots(
                    at: rootURL,
                    commandTimeout: commandTimeout,
                    verboseLogger: verboseLogger,
                    inspectedGitDirs: &inspectedGitDirs,
                    discoveredWorktrees: &pendingGitWorktreeRoots
                )
            }

            if detectedSkipsDescendants(discoveredByRoot[rootURL.resolvingSymlinksInPath().path]?.type) || maxDepth == 0 {
                continue
            }

            let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [],
                errorHandler: { url, error in
                    verboseLogger?("Skipping unreadable path \(url.path): \(error.localizedDescription)")
                    return true
                }
            )

            while let itemURL = enumerator?.nextObject() as? URL {
                guard let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
                    continue
                }
                if values.isSymbolicLink == true {
                    enumerator?.skipDescendants()
                    continue
                }
                guard values.isDirectory == true else {
                    continue
                }

                if itemURL.lastPathComponent == ".git" {
                    if includeGitWorktrees {
                        collectGitWorktreeRoots(
                            at: itemURL.deletingLastPathComponent(),
                            commandTimeout: commandTimeout,
                            verboseLogger: verboseLogger,
                            inspectedGitDirs: &inspectedGitDirs,
                            discoveredWorktrees: &pendingGitWorktreeRoots
                        )
                    }
                    enumerator?.skipDescendants()
                    continue
                }

                if shouldExclude(
                    url: itemURL,
                    relativeTo: rootURL,
                    scanningHomeRoot: scanningHomeRoot,
                    excludePatterns: excludePatterns
                ) {
                    enumerator?.skipDescendants()
                    continue
                }

                let depth = itemURL.pathComponents.count - baseDepth
                if depth > maxDepth {
                    enumerator?.skipDescendants()
                    continue
                }

                if Self.bundleExtensionsToSkip.contains(itemURL.pathExtension.lowercased()) {
                    enumerator?.skipDescendants()
                    continue
                }

                if includeGitWorktrees, fileManager.fileExists(atPath: itemURL.appendingPathComponent(".git").path) {
                    collectGitWorktreeRoots(
                        at: itemURL,
                        commandTimeout: commandTimeout,
                        verboseLogger: verboseLogger,
                        inspectedGitDirs: &inspectedGitDirs,
                        discoveredWorktrees: &pendingGitWorktreeRoots
                    )
                }

                if let detected = detectProjectIfMarkersPresent(in: itemURL) {
                    record(detected)
                    if detectedSkipsDescendants(detected.type) {
                        enumerator?.skipDescendants()
                        continue
                    }
                }

                if depth == maxDepth {
                    enumerator?.skipDescendants()
                }
            }
        }

        // Also detect any linked Git worktrees located outside the scanned subtree.
        for worktreePath in pendingGitWorktreeRoots {
            let worktreeURL = URL(fileURLWithPath: worktreePath).standardizedFileURL
            let resolvedKey = worktreeURL.resolvingSymlinksInPath().path
            guard discoveredByRoot[resolvedKey] == nil else { continue }
            guard !matchesUserExcludes(url: worktreeURL, excludePatterns: excludePatterns) else { continue }
            if let detected = detectProjectIfMarkersPresent(in: worktreeURL) {
                record(detected)
            }
        }

        return orderedRoots.compactMap { discoveredByRoot[$0] }
    }

    // MARK: - Project Processing

    private func processProject(
        _ project: DetectedProject,
        options: MigrationOptions,
        activeCommands: [String],
        progressObserver: (@Sendable (MigrationProgressEvent) -> Void)? = nil
    ) -> MigratedProjectOutcome {
        let targets = expandedTargets(for: project)
        var targetAndSPPairs: [(target: DetectedProject, spURL: URL)] = []
        var seenSPPaths: Set<String> = []

        for target in targets {
            let candidates = (try? syncEngine.resolveCandidateSourcePackagesURLs(for: target)) ?? []
            for spURL in candidates where seenSPPaths.insert(spURL.path).inserted {
                targetAndSPPairs.append((target: target, spURL: spURL))
            }
        }
        let resolvedSourcePackagesURLs = targetAndSPPairs.map(\.spURL)

        progressObserver?(.stage(projectRoot: project.rootPath, type: project.type, detail: "measuring cache size"))
        let existingCacheBytes = resolvedSourcePackagesURLs.reduce(UInt64(0)) { total, url in
            total + cacheSubdirectoriesSizeBytes(at: url)
        }
        let hasExistingCache = existingCacheBytes > 0

        if isProjectActivelyBuilding(project, sourcePackagesURLs: resolvedSourcePackagesURLs, activeCommands: activeCommands) {
            return MigratedProjectOutcome(
                project: project,
                sourcePackagesPaths: resolvedSourcePackagesURLs.map(\.path),
                existingCacheBytes: existingCacheBytes,
                hasExistingCache: hasExistingCache,
                harvestedCheckoutsCount: 0,
                harvestedArtifactsCount: 0,
                harvestedPrebuiltsCount: 0,
                deduplicatedCheckoutsCount: 0,
                deduplicatedArtifactsCount: 0,
                deduplicatedPrebuiltsCount: 0,
                skippedLocallyModifiedCount: 0,
                estimatedReclaimedBytes: 0,
                recordedFlutterResolved: false,
                installedRepoHook: false,
                skippedReason: "active build detected"
            )
        }

        if options.dryRun {
            let estimatedReclaimed = options.deduplicate ? existingCacheBytes : 0
            return MigratedProjectOutcome(
                project: project,
                sourcePackagesPaths: resolvedSourcePackagesURLs.map(\.path),
                existingCacheBytes: existingCacheBytes,
                hasExistingCache: hasExistingCache,
                harvestedCheckoutsCount: 0,
                harvestedArtifactsCount: 0,
                harvestedPrebuiltsCount: 0,
                deduplicatedCheckoutsCount: 0,
                deduplicatedArtifactsCount: 0,
                deduplicatedPrebuiltsCount: 0,
                skippedLocallyModifiedCount: 0,
                estimatedReclaimedBytes: estimatedReclaimed,
                recordedFlutterResolved: false,
                installedRepoHook: false
            )
        }

        var harvestedCheckouts = 0
        var harvestedArtifacts = 0
        var harvestedPrebuilts = 0
        var deduplicatedCheckouts = 0
        var deduplicatedArtifacts = 0
        var deduplicatedPrebuilts = 0
        var skippedModified = 0
        var estimatedReclaimed: UInt64 = 0
        var warningNotes: [String] = []

        let stageReporter: (@Sendable (String) -> Void)? = progressObserver.map { observer in
            let rootPath = project.rootPath
            let projectType = project.type
            return { detail in
                observer(.stage(projectRoot: rootPath, type: projectType, detail: detail))
            }
        }

        for (target, spURL) in targetAndSPPairs {
            guard cacheSubdirectoriesSizeBytes(at: spURL) > 0 else {
                continue
            }

            do {
                stageReporter?("harvesting cache")
                let harvestResult = try syncEngine.harvest(
                    project: target,
                    options: HarvestOptions(
                        sourcePackagesOverride: spURL.path,
                        commandTimeout: options.commandTimeout,
                        progressHandler: stageReporter,
                        verboseLogger: options.verboseLogger
                    )
                )
                harvestedCheckouts += harvestResult.harvestedCheckouts.count
                harvestedArtifacts += harvestResult.harvestedArtifacts.count
                harvestedPrebuilts += harvestResult.harvestedPrebuilts.count

                if options.deduplicate,
                   (target.packageResolvedPath ?? target.allPackageResolvedPaths.first) != nil {
                    stageReporter?("deduplicating via CoW")
                    let dedupResult = try syncEngine.hydrate(
                        project: target,
                        options: HydrateOptions(
                            sourcePackagesOverride: spURL.path,
                            force: false,
                            deduplicateCleanEntries: true,
                            rewriteWorkspaceState: false,
                            registerProject: false,
                            commandTimeout: options.commandTimeout,
                            progressHandler: stageReporter,
                            verboseLogger: options.verboseLogger
                        )
                    )
                    deduplicatedCheckouts += dedupResult.hydratedCheckouts.count
                    deduplicatedArtifacts += dedupResult.hydratedArtifacts.count
                    deduplicatedPrebuilts += dedupResult.hydratedPrebuilts.count
                    skippedModified += dedupResult.skippedCheckouts.filter { $0.reason == .locallyModified }.count
                    let timedOutCheckouts = dedupResult.skippedCheckouts.filter { $0.reason == .timedOut }
                    if !timedOutCheckouts.isEmpty {
                        warningNotes.append("git status timed out for \(timedOutCheckouts.count) checkout(s)")
                    }

                    stageReporter?("calculating reclaimed space")
                    for item in dedupResult.hydratedCheckouts {
                        estimatedReclaimed += DiagnosticsSupport.directorySizeBytes(at: item.destinationURL, fileManager: fileManager)
                    }
                    for item in dedupResult.hydratedArtifacts {
                        estimatedReclaimed += DiagnosticsSupport.directorySizeBytes(at: item.destinationURL, fileManager: fileManager)
                    }
                    for item in dedupResult.hydratedPrebuilts {
                        estimatedReclaimed += DiagnosticsSupport.directorySizeBytes(at: item.destinationURL, fileManager: fileManager)
                    }
                }
            } catch {
                warningNotes.append(error.localizedDescription)
                options.verboseLogger?("Migration warning for \(project.rootPath): \(error.localizedDescription)")
            }
        }

        var recordedFlutter = false
        if project.type == .flutter {
            stageReporter?("caching Flutter Package.resolved")
            let integrator = FlutterSPMIntegrator(
                store: store,
                commandRunner: ProcessFlutterCommandRunner(timeout: options.commandTimeout)
            )
            if integrator.isFlutterSPMProject(project),
               let recorded = try? integrator.recordResolvedDependencies(project: project),
               !recorded.isEmpty {
                recordedFlutter = true
            }
        }

        var installedHook = false
        if options.installRepoHooks,
           fileManager.fileExists(atPath: URL(fileURLWithPath: project.rootPath).appendingPathComponent(".git").path) {
            stageReporter?("installing repo Git hook")
            let hooksManager = GitHooksManager(
                gitRunner: SystemGitRunner(timeout: options.commandTimeout),
                homeDirectory: homeDirectory
            )
            if (try? hooksManager.enable(scope: .repo, workingDirectory: project.rootPath)) != nil {
                installedHook = true
            }
        }

        return MigratedProjectOutcome(
            project: project,
            sourcePackagesPaths: resolvedSourcePackagesURLs.map(\.path),
            existingCacheBytes: existingCacheBytes,
            hasExistingCache: hasExistingCache,
            harvestedCheckoutsCount: harvestedCheckouts,
            harvestedArtifactsCount: harvestedArtifacts,
            harvestedPrebuiltsCount: harvestedPrebuilts,
            deduplicatedCheckoutsCount: deduplicatedCheckouts,
            deduplicatedArtifactsCount: deduplicatedArtifacts,
            deduplicatedPrebuiltsCount: deduplicatedPrebuilts,
            skippedLocallyModifiedCount: skippedModified,
            estimatedReclaimedBytes: estimatedReclaimed,
            recordedFlutterResolved: recordedFlutter,
            installedRepoHook: installedHook,
            skippedReason: warningNotes.isEmpty ? nil : warningNotes.joined(separator: "; ")
        )
    }

    private func expandedTargets(for project: DetectedProject) -> [DetectedProject] {
        guard project.type == .flutter, let flutterInfo = project.flutterInfo else {
            return [project]
        }

        var targets: [DetectedProject] = []
        var seenContainers: Set<String> = []
        for target in flutterInfo.targets {
            guard let container = target.preferredContainerPath,
                  seenContainers.insert(container).inserted else {
                continue
            }
            if let specific = try? ProjectDetector.detect(in: project.rootPath, workspacePath: container, fileManager: fileManager) {
                targets.append(specific)
            }
        }
        return targets.isEmpty ? [project] : targets
    }

    private func cacheSubdirectoriesSizeBytes(at sourcePackagesURL: URL) -> UInt64 {
        ["checkouts", "artifacts", "prebuilts"].reduce(UInt64(0)) { sum, folder in
            let subURL = sourcePackagesURL.appendingPathComponent(folder)
            return sum + DiagnosticsSupport.directorySizeBytes(at: subURL, fileManager: fileManager)
        }
    }

    // MARK: - Discovery & Filtering Helpers

    private func detectProjectIfMarkersPresent(in directoryURL: URL) -> DetectedProject? {
        guard let contents = try? fileManager.contentsOfDirectory(
            atPath: directoryURL.path
        ) else {
            return nil
        }

        let hasMarker = contents.contains { name in
            name == "pubspec.yaml"
                || name == "Package.swift"
                || name.hasSuffix(".xcworkspace")
                || name.hasSuffix(".xcodeproj")
        }
        guard hasMarker else { return nil }

        return try? ProjectDetector.detect(in: directoryURL.path, fileManager: fileManager)
    }

    private func detectedSkipsDescendants(_ type: ProjectType?) -> Bool {
        guard let type else { return false }
        // Flutter apps contain nested ios/ and macos/ containers already represented by the Flutter root.
        return type == .flutter
    }

    private func shouldExclude(
        url: URL,
        relativeTo rootURL: URL,
        scanningHomeRoot: Bool,
        excludePatterns: [String]
    ) -> Bool {
        let name = url.lastPathComponent
        if name.hasPrefix(".") {
            return true
        }
        if Self.alwaysIgnoredDirectoryNames.contains(name) {
            return true
        }
        if scanningHomeRoot,
           url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path == rootURL.resolvingSymlinksInPath().path,
           Self.homeTopLevelIgnoredNames.contains(name) {
            return true
        }
        return matchesUserExcludes(url: url, excludePatterns: excludePatterns)
    }

    private func matchesUserExcludes(url: URL, excludePatterns: [String]) -> Bool {
        guard !excludePatterns.isEmpty else { return false }
        let name = url.lastPathComponent
        let fullPath = url.path

        for rawPattern in excludePatterns {
            let pattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pattern.isEmpty else { continue }
            if name == pattern || fullPath.contains(pattern) {
                return true
            }
            if fnmatch(pattern, name, 0) == 0 || fnmatch(pattern, fullPath, 0) == 0 {
                return true
            }
        }
        return false
    }

    private func collectGitWorktreeRoots(
        at repositoryDirectory: URL,
        commandTimeout: TimeInterval?,
        verboseLogger: (@Sendable (String) -> Void)?,
        inspectedGitDirs: inout Set<String>,
        discoveredWorktrees: inout [String]
    ) {
        let resolvedRepo = repositoryDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        guard inspectedGitDirs.insert(resolvedRepo).inserted else { return }

        var env = ProcessInfo.processInfo.environment
        if env["GIT_TERMINAL_PROMPT"] == nil {
            env["GIT_TERMINAL_PROMPT"] = "0"
        }

        do {
            let result = try CommandExecutor.run(
                executablePath: "/usr/bin/git",
                arguments: ["-C", resolvedRepo, "worktree", "list", "--porcelain"],
                environment: env,
                timeout: commandTimeout
            )
            guard result.exitCode == 0 else { return }
            for line in result.stdout.split(separator: "\n") where line.hasPrefix("worktree ") {
                let path = String(line.dropFirst("worktree ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty {
                    discoveredWorktrees.append(path)
                }
            }
        } catch let error as CommandExecutionError {
            if case .timedOut(_, _, let seconds) = error {
                verboseLogger?("Warning: git worktree discovery timed out after \(Int(seconds))s at '\(resolvedRepo)'")
            }
            return
        } catch {
            return
        }
    }

    private func isProjectActivelyBuilding(
        _ project: DetectedProject,
        sourcePackagesURLs: [URL],
        activeCommands: [String]
    ) -> Bool {
        let lockPaths = sourcePackagesURLs.map { $0.appendingPathComponent(".lock").path }
        if lockPaths.contains(where: { FileLock.isLocked(atPath: $0) }) {
            return true
        }

        var indicators: Set<String> = []
        for rawPath in [project.rootPath] + (project.containerPath.map { [$0] } ?? []) {
            let url = URL(fileURLWithPath: rawPath).standardizedFileURL
            indicators.insert(url.path)
            indicators.insert(url.resolvingSymlinksInPath().path)
        }
        for cmd in activeCommands {
            let isBuildTool = Self.activeBuildExecutables.contains { cmd.contains($0) }
            if isBuildTool && indicators.contains(where: { cmd.contains($0) }) {
                return true
            }
        }
        return false
    }

    public static func defaultActiveCommands() -> [String] {
        do {
            let result = try CommandExecutor.run(
                executablePath: "/bin/ps",
                arguments: ["-ax", "-o", "command="]
            )
            guard result.exitCode == 0 else { return [] }
            return result.stdout.split(separator: "\n").map(String.init)
        } catch {
            return []
        }
    }
}

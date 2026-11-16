import CryptoKit
import Foundation

/// Resolves the real `flutter` executable on `PATH` while excluding `spmx` shim directories.
public protocol FlutterExecutableResolving: Sendable {
    func resolveFlutterExecutable(environment: [String: String]) throws -> String
    func sanitizedEnvironment(from environment: [String: String]) -> [String: String]
}

/// Default `PATH` resolver for locating the real `flutter` binary without entering a shim loop.
public struct FlutterExecutableResolver: FlutterExecutableResolving, Sendable {
    public static let shimsDirectoryEnvironmentKey = "SPMX_SHIMS_DIR"
    public static let flutterShimActiveEnvironmentKey = "SPMX_FLUTTER_SHIM_ACTIVE"

    public let homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    /// Returns the default `spmx` shims directory (`~/.spmx/shims`).
    public static func defaultShimsDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent(".spmx")
            .appendingPathComponent("shims")
            .standardizedFileURL
    }

    /// Returns canonical paths of shim directories that must be excluded from `PATH` resolution.
    public func excludedShimDirectories(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        var rawPaths: [String] = [Self.defaultShimsDirectory(homeDirectory: homeDirectory).path]

        if let customShims = environment[Self.shimsDirectoryEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !customShims.isEmpty {
            let expanded = (customShims as NSString).expandingTildeInPath
            rawPaths.append(expanded)
        }

        var normalized: Set<String> = []
        for raw in rawPaths {
            let url = URL(fileURLWithPath: raw).standardizedFileURL
            normalized.insert(trimTrailingSlashes(url.path))
            normalized.insert(trimTrailingSlashes(url.resolvingSymlinksInPath().path))
        }
        return normalized.sorted()
    }

    /// Filters `PATH` entries, removing `~/.spmx/shims` and `SPMX_SHIMS_DIR`.
    public func filteredPathEntries(
        from pathValue: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        let excluded = Set(excludedShimDirectories(environment: environment))
        return pathValue
            .split(separator: ":", omittingEmptySubsequences: true)
            .compactMap { segment in
                let raw = String(segment).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { return nil }
                let expanded = (raw as NSString).expandingTildeInPath
                let url = URL(fileURLWithPath: expanded).standardizedFileURL
                let standardized = trimTrailingSlashes(url.path)
                let resolved = trimTrailingSlashes(url.resolvingSymlinksInPath().path)
                if excluded.contains(standardized) || excluded.contains(resolved) {
                    return nil
                }
                return expanded
            }
    }

    /// Locates the first real `flutter` executable on `PATH` outside `spmx` shim directories.
    public func resolveFlutterExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> String {
        let fileManager = FileManager.default
        let excluded = Set(excludedShimDirectories(environment: environment))
        let searchPaths = filteredPathEntries(
            from: environment["PATH"] ?? "",
            environment: environment
        )

        for directory in searchPaths {
            let candidate = URL(fileURLWithPath: directory)
                .appendingPathComponent("flutter")
                .standardizedFileURL

            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDir),
                  !isDir.boolValue,
                  fileManager.isExecutableFile(atPath: candidate.path)
            else {
                continue
            }

            // Guard against symlinks in other directories pointing back to `spmx` or a shim directory.
            let resolved = candidate.resolvingSymlinksInPath()
            let resolvedParent = trimTrailingSlashes(resolved.deletingLastPathComponent().path)
            if excluded.contains(resolvedParent) || resolved.lastPathComponent == "spmx" {
                continue
            }

            return candidate.path
        }

        throw FlutterSPMIntegratorError.flutterExecutableNotFound(searchedPaths: searchPaths)
    }

    /// Builds a child environment with shim directories removed from `PATH` and `SPMX_FLUTTER_SHIM_ACTIVE=1`.
    public func sanitizedEnvironment(from environment: [String: String]) -> [String: String] {
        var sanitized = environment
        let filteredPath = filteredPathEntries(
            from: environment["PATH"] ?? "",
            environment: environment
        ).joined(separator: ":")
        sanitized["PATH"] = filteredPath
        sanitized[Self.flutterShimActiveEnvironmentKey] = "1"
        return sanitized
    }

    private func trimTrailingSlashes(_ path: String) -> String {
        var trimmed = path
        while trimmed.count > 1 && trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }
}

/// Executes external `flutter` commands so callers and tests can inject process execution.
public protocol FlutterCommandRunning: Sendable {
    func run(
        executablePath: String,
        arguments: [String],
        workingDirectory: String,
        environment: [String: String]
    ) throws -> CommandResult
}

/// Default runner for `flutter` CLI invocations backed by ``CommandExecutor``.
/// Resets the execution timeout whenever `flutter` emits stdout or stderr activity.
public struct ProcessFlutterCommandRunner: FlutterCommandRunning, Sendable {
    public let timeout: TimeInterval?

    public init(timeout: TimeInterval? = CommandExecutor.resolveDefaultTimeout()) {
        self.timeout = timeout
    }

    public func run(
        executablePath: String,
        arguments: [String],
        workingDirectory: String,
        environment: [String: String]
    ) throws -> CommandResult {
        let result = try CommandExecutor.run(
            executablePath: executablePath,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            timeout: timeout,
            resetTimeoutOnOutput: true
        )
        return CommandResult(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr
        )
    }
}

/// Errors thrown by ``FlutterSPMIntegrator``.
public enum FlutterSPMIntegratorError: Error, LocalizedError, Equatable, Sendable {
    case notAFlutterProject(String)
    case flutterExecutableNotFound(searchedPaths: [String])
    case pubGetFailed(exitCode: Int32, stderr: String, stdout: String)
    case missingDependencyMetadata(rootPath: String)

    public var errorDescription: String? {
        switch self {
        case .notAFlutterProject(let path):
            return "Project at '\(path)' is not a Flutter Apple/SwiftPM project."
        case .flutterExecutableNotFound(let searchedPaths):
            let joined = searchedPaths.isEmpty ? "<empty PATH>" : searchedPaths.joined(separator: ":")
            return "Could not locate real 'flutter' executable outside spmx shims in PATH: \(joined)"
        case .pubGetFailed(let exitCode, let stderr, let stdout):
            let details = stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if details.isEmpty {
                return "'flutter pub get' failed with exit code \(exitCode)."
            }
            return "'flutter pub get' failed with exit code \(exitCode): \(details)"
        case .missingDependencyMetadata(let rootPath):
            return "No '.flutter-plugins-dependencies' or 'FlutterGeneratedPluginSwiftPackage/Package.swift' found in '\(rootPath)'."
        }
    }
}

/// Outcome of preparing a Flutter project before `SourcePackages` hydration.
public struct FlutterPrepareResult: Equatable, Sendable {
    public let project: DetectedProject
    public let didRunPubGet: Bool
    public let executedFlutterPath: String?
    public let dependencyHashes: [FlutterPlatform: String]
    public let restoredPackageResolvedPaths: [FlutterPlatform: String]

    public init(
        project: DetectedProject,
        didRunPubGet: Bool,
        executedFlutterPath: String?,
        dependencyHashes: [FlutterPlatform: String],
        restoredPackageResolvedPaths: [FlutterPlatform: String]
    ) {
        self.project = project
        self.didRunPubGet = didRunPubGet
        self.executedFlutterPath = executedFlutterPath
        self.dependencyHashes = dependencyHashes
        self.restoredPackageResolvedPaths = restoredPackageResolvedPaths
    }
}

/// Integrates Flutter's ephemeral `FlutterGeneratedPluginSwiftPackage` lifecycle and
/// `Package.resolved` caching with ``GlobalStore``.
public struct FlutterSPMIntegrator: Sendable {
    public let store: GlobalStore
    public let executableResolver: any FlutterExecutableResolving
    public let commandRunner: any FlutterCommandRunning

    public init(
        store: GlobalStore = GlobalStore(),
        executableResolver: any FlutterExecutableResolving = FlutterExecutableResolver(),
        commandRunner: any FlutterCommandRunning = ProcessFlutterCommandRunner()
    ) {
        self.store = store
        self.executableResolver = executableResolver
        self.commandRunner = commandRunner
    }

    /// Returns `true` when the detected project is a Flutter project with Apple/SwiftPM configuration.
    public func isFlutterSPMProject(_ project: DetectedProject) -> Bool {
        guard project.type == .flutter, let info = project.flutterInfo else {
            return false
        }
        return info.hasGeneratedSwiftPackage || info.pluginDependenciesPath != nil || !info.targets.isEmpty
    }

    /// Computes a deterministic SHA-256 hash from `.flutter-plugins-dependencies` and any existing
    /// `FlutterGeneratedPluginSwiftPackage/Package.swift` manifests.
    ///
    /// Pass `platform` to scope the hash to a specific Apple target (`ios` or `macos`), preventing
    /// multiplatform projects with differing plugin graphs from colliding in `GlobalStore`.
    public func computeDependencyHash(
        for project: DetectedProject,
        platform: FlutterPlatform? = nil
    ) throws -> String {
        guard project.type == .flutter, let flutterInfo = project.flutterInfo else {
            throw FlutterSPMIntegratorError.notAFlutterProject(project.rootPath)
        }

        let fileManager = FileManager.default
        var hasher = SHA256()
        var hasAnyInput = false

        if let platform {
            hasher.update(data: Data("platform:\(platform.rawValue)\n".utf8))
        }

        if let depsPath = flutterInfo.pluginDependenciesPath,
           fileManager.fileExists(atPath: depsPath) {
            let rawData = try Data(contentsOf: URL(fileURLWithPath: depsPath))
            let canonicalDeps = canonicalizePluginDependenciesData(
                rawData,
                projectRootPath: project.rootPath,
                platform: platform
            )
            hasher.update(data: Data("flutter-plugins-dependencies:\n".utf8))
            hasher.update(data: canonicalDeps)
            hasher.update(data: Data("\n".utf8))
            hasAnyInput = true
        }

        let relevantTargets = flutterInfo.targets
            .filter { platform == nil || $0.platform == platform }
            .sorted { $0.platform.rawValue < $1.platform.rawValue }

        for target in relevantTargets {
            let manifestURL = URL(fileURLWithPath: target.generatedPackagePath)
                .appendingPathComponent("Package.swift")
            guard fileManager.fileExists(atPath: manifestURL.path) else {
                continue
            }
            let manifestData = try Data(contentsOf: manifestURL)
            let normalizedManifest = normalizeTextData(manifestData, projectRootPath: project.rootPath)
            hasher.update(data: Data("manifest:\(target.platform.rawValue):\n".utf8))
            hasher.update(data: normalizedManifest)
            hasher.update(data: Data("\n".utf8))
            hasAnyInput = true
        }

        guard hasAnyInput else {
            throw FlutterSPMIntegratorError.missingDependencyMetadata(rootPath: project.rootPath)
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Prepares a Flutter worktree before `SourcePackages` hydration:
    /// 1. Runs `flutter pub get` (via the real `flutter` binary with `SPMX_FLUTTER_SHIM_ACTIVE=1`)
    ///    if `FlutterGeneratedPluginSwiftPackage/Package.swift` does not exist yet and `runPubGetIfMissing` is `true`.
    /// 2. Computes the native dependency hash per target and restores any cached `Package.resolved`
    ///    from ``GlobalStore`` into `<workspace>/xcshareddata/swiftpm/Package.resolved` when missing.
    public func prepareForHydration(
        project: DetectedProject,
        runPubGetIfMissing: Bool = true,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> FlutterPrepareResult {
        guard project.type == .flutter, let initialFlutterInfo = project.flutterInfo else {
            throw FlutterSPMIntegratorError.notAFlutterProject(project.rootPath)
        }

        var workingProject = project
        var didRunPubGet = false
        var executedFlutterPath: String?

        if !initialFlutterInfo.hasGeneratedSwiftPackage && runPubGetIfMissing {
            let flutterPath = try executableResolver.resolveFlutterExecutable(environment: environment)
            let sanitizedEnv = executableResolver.sanitizedEnvironment(from: environment)
            let commandResult = try commandRunner.run(
                executablePath: flutterPath,
                arguments: ["pub", "get"],
                workingDirectory: project.rootPath,
                environment: sanitizedEnv
            )

            guard commandResult.exitCode == 0 else {
                throw FlutterSPMIntegratorError.pubGetFailed(
                    exitCode: commandResult.exitCode,
                    stderr: commandResult.stderr,
                    stdout: commandResult.stdout
                )
            }

            didRunPubGet = true
            executedFlutterPath = flutterPath
            workingProject = try redetectProject(from: project)
        }

        let fileManager = FileManager.default
        let targets = workingProject.flutterInfo?.targets ?? []
        var dependencyHashes: [FlutterPlatform: String] = [:]
        var restoredPaths: [FlutterPlatform: String] = [:]
        let projectWideHash = try? computeDependencyHash(for: workingProject, platform: nil)

        for target in targets {
            let platformHash: String
            do {
                platformHash = try computeDependencyHash(for: workingProject, platform: target.platform)
            } catch FlutterSPMIntegratorError.missingDependencyMetadata {
                continue
            }

            dependencyHashes[target.platform] = platformHash

            guard let destinationURL = destinationPackageResolvedURL(for: target),
                  target.packageResolvedPath == nil,
                  !fileManager.fileExists(atPath: destinationURL.path)
            else {
                continue
            }

            var cachedEntry = try store.cachedFlutterPackageResolved(forDependencyHash: platformHash)
            if cachedEntry == nil, let projectWideHash {
                cachedEntry = try store.cachedFlutterPackageResolved(forDependencyHash: projectWideHash)
            }

            guard let entry = cachedEntry else {
                continue
            }

            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try entry.packageResolvedContents.write(
                to: destinationURL,
                atomically: true,
                encoding: .utf8
            )
            restoredPaths[target.platform] = destinationURL.path
        }

        if !restoredPaths.isEmpty {
            workingProject = try redetectProject(from: workingProject)
        }

        return FlutterPrepareResult(
            project: workingProject,
            didRunPubGet: didRunPubGet,
            executedFlutterPath: executedFlutterPath,
            dependencyHashes: dependencyHashes,
            restoredPackageResolvedPaths: restoredPaths
        )
    }

    /// Computes each target's native dependency hash and caches its existing `Package.resolved`
    /// in ``GlobalStore`` for reuse across worktrees.
    @discardableResult
    public func recordResolvedDependencies(
        project: DetectedProject,
        toolchainHash: String? = nil
    ) throws -> [FlutterPlatform: String] {
        guard project.type == .flutter, project.flutterInfo != nil else {
            throw FlutterSPMIntegratorError.notAFlutterProject(project.rootPath)
        }

        let freshProject = try redetectProject(from: project)
        let targets = freshProject.flutterInfo?.targets ?? []
        var recorded: [FlutterPlatform: String] = [:]

        for target in targets {
            guard let resolvedPath = target.packageResolvedPath else {
                continue
            }

            let contents = try String(contentsOfFile: resolvedPath, encoding: .utf8)
            guard !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            let hash = try computeDependencyHash(for: freshProject, platform: target.platform)
            try store.cacheFlutterPackageResolved(
                contents,
                forDependencyHash: hash,
                toolchainHash: toolchainHash
            )
            recorded[target.platform] = hash
        }

        return recorded
    }

    // MARK: - Private Helpers

    private func redetectProject(from project: DetectedProject) throws -> DetectedProject {
        if let containerPath = project.containerPath {
            if containerPath.hasSuffix(".xcworkspace") {
                return try ProjectDetector.detect(workspacePath: containerPath)
            }
            if containerPath.hasSuffix(".xcodeproj") {
                return try ProjectDetector.detect(projectPath: containerPath)
            }
        }
        return try ProjectDetector.detect(in: project.rootPath)
    }

    private func destinationPackageResolvedURL(for target: FlutterSPMTarget) -> URL? {
        if let workspacePath = target.workspacePath {
            return URL(fileURLWithPath: workspacePath)
                .appendingPathComponent("xcshareddata")
                .appendingPathComponent("swiftpm")
                .appendingPathComponent("Package.resolved")
        }
        if let projectPath = target.projectPath {
            return URL(fileURLWithPath: projectPath)
                .appendingPathComponent("project.xcworkspace")
                .appendingPathComponent("xcshareddata")
                .appendingPathComponent("swiftpm")
                .appendingPathComponent("Package.resolved")
        }
        return nil
    }

    private func canonicalizePluginDependenciesData(
        _ data: Data,
        projectRootPath: String,
        platform: FlutterPlatform?
    ) -> Data {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []),
              var dict = object as? [String: Any]
        else {
            return normalizeTextData(data, projectRootPath: projectRootPath)
        }

        // Ignore volatile generation timestamps emitted by `flutter pub get`.
        dict.removeValue(forKey: "date_created")

        if let platform, let plugins = dict["plugins"] as? [String: Any] {
            if let platformPlugins = plugins[platform.rawValue] {
                dict["plugins"] = [platform.rawValue: platformPlugins]
            } else {
                dict["plugins"] = [String: Any]()
            }
        }

        let normalizedObject = normalizeJSONValue(dict, projectRootPath: projectRootPath)
        if let serialized = try? JSONSerialization.data(
            withJSONObject: normalizedObject,
            options: [.sortedKeys]
        ) {
            return serialized
        }

        return normalizeTextData(data, projectRootPath: projectRootPath)
    }

    private func normalizeJSONValue(_ value: Any, projectRootPath: String) -> Any {
        if let str = value as? String {
            return normalizeString(str, projectRootPath: projectRootPath)
        }
        if let array = value as? [Any] {
            return array.map { normalizeJSONValue($0, projectRootPath: projectRootPath) }
        }
        if let dict = value as? [String: Any] {
            var normalized: [String: Any] = [:]
            for (key, item) in dict {
                normalized[key] = normalizeJSONValue(item, projectRootPath: projectRootPath)
            }
            return normalized
        }
        return value
    }

    private func normalizeTextData(_ data: Data, projectRootPath: String) -> Data {
        guard let text = String(data: data, encoding: .utf8) else {
            return data
        }
        let normalized = normalizeString(
            text.replacingOccurrences(of: "\r\n", with: "\n"),
            projectRootPath: projectRootPath
        )
        return Data(normalized.utf8)
    }

    private func normalizeString(_ value: String, projectRootPath: String) -> String {
        guard !projectRootPath.isEmpty else { return value }
        return value.replacingOccurrences(of: projectRootPath, with: "${PROJECT_ROOT}")
    }
}

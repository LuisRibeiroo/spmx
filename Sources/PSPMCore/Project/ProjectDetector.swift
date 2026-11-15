import Foundation

/// High-level classification of a project detected by `pspm`.
public enum ProjectType: String, Sendable, Equatable, Codable {
    case flutter
    case xcode
    case swiftPackage
}

/// Supported Apple target platforms inside a Flutter project.
public enum FlutterPlatform: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case ios
    case macos
}

/// Details about a single Apple platform target inside a Flutter project.
public struct FlutterSPMTarget: Sendable, Equatable {
    public let platform: FlutterPlatform
    public let workspacePath: String?
    public let projectPath: String?
    public let generatedPackagePath: String
    public let generatedPackageManifestExists: Bool
    public let packageResolvedPath: String?

    public init(
        platform: FlutterPlatform,
        workspacePath: String?,
        projectPath: String?,
        generatedPackagePath: String,
        generatedPackageManifestExists: Bool,
        packageResolvedPath: String?
    ) {
        self.platform = platform
        self.workspacePath = workspacePath
        self.projectPath = projectPath
        self.generatedPackagePath = generatedPackagePath
        self.generatedPackageManifestExists = generatedPackageManifestExists
        self.packageResolvedPath = packageResolvedPath
    }

    /// Preferred Xcode container for this target (`.xcworkspace` prioritized over `.xcodeproj`).
    public var preferredContainerPath: String? {
        workspacePath ?? projectPath
    }
}

/// Metadata extracted from a Flutter project's Apple/SwiftPM configuration.
public struct FlutterProjectInfo: Sendable, Equatable {
    public let pubspecPath: String
    public let pluginDependenciesPath: String?
    public let pluginNamesByPlatform: [FlutterPlatform: [String]]
    public let targets: [FlutterSPMTarget]

    public init(
        pubspecPath: String,
        pluginDependenciesPath: String?,
        pluginNamesByPlatform: [FlutterPlatform: [String]],
        targets: [FlutterSPMTarget]
    ) {
        self.pubspecPath = pubspecPath
        self.pluginDependenciesPath = pluginDependenciesPath
        self.pluginNamesByPlatform = pluginNamesByPlatform
        self.targets = targets
    }

    /// Returns `true` when at least one Flutter target has generated `FlutterGeneratedPluginSwiftPackage/Package.swift`.
    public var hasGeneratedSwiftPackage: Bool {
        targets.contains { $0.generatedPackageManifestExists }
    }
}

/// Result of auto-detecting a project root, type, Xcode container, and `Package.resolved` locations.
public struct DetectedProject: Sendable, Equatable {
    public let type: ProjectType
    public let rootPath: String
    public let containerPath: String?
    public let packageManifestPath: String?
    public let packageResolvedPath: String?
    public let allPackageResolvedPaths: [String]
    public let flutterInfo: FlutterProjectInfo?

    public init(
        type: ProjectType,
        rootPath: String,
        containerPath: String?,
        packageManifestPath: String?,
        packageResolvedPath: String?,
        allPackageResolvedPaths: [String],
        flutterInfo: FlutterProjectInfo?
    ) {
        self.type = type
        self.rootPath = rootPath
        self.containerPath = containerPath
        self.packageManifestPath = packageManifestPath
        self.packageResolvedPath = packageResolvedPath
        self.allPackageResolvedPaths = allPackageResolvedPaths
        self.flutterInfo = flutterInfo
    }
}

public enum ProjectDetectionError: Error, LocalizedError, Equatable, Sendable {
    case directoryNotFound(String)
    case explicitPathNotFound(String)
    case invalidExplicitPath(String)
    case projectNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .directoryNotFound(let path):
            return "Directory not found at '\(path)'."
        case .explicitPathNotFound(let path):
            return "Explicit project or workspace path not found at '\(path)'."
        case .invalidExplicitPath(let path):
            return "Path '\(path)' is not a supported .xcworkspace, .xcodeproj, Package.swift, or project directory."
        case .projectNotFound(let path):
            return "No Flutter, Xcode, or SwiftPM project detected in '\(path)'."
        }
    }
}

/// Auto-detects Flutter, Xcode, and pure SwiftPM projects and locates `Package.resolved`.
public struct ProjectDetector: Sendable {
    public init() {}

    /// Detects the project type, root, primary Xcode container, and `Package.resolved` paths.
    ///
    /// Precedence when `workspacePath` / `projectPath` are omitted:
    /// 1. Flutter (`pubspec.yaml` + `ios/` or `macos/` Apple container or generated SPM package)
    /// 2. Xcode (`*.xcworkspace` prioritized over `*.xcodeproj`, ignoring `project.xcworkspace`)
    /// 3. Pure SwiftPM (`Package.swift`)
    public static func detect(
        in directoryPath: String? = nil,
        projectPath: String? = nil,
        workspacePath: String? = nil,
        currentDirectory: String = FileManager.default.currentDirectoryPath,
        fileManager: FileManager = .default
    ) throws -> DetectedProject {
        if let workspacePath, !workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try detectFromExplicitPath(
                workspacePath,
                expectWorkspaceOnly: true,
                currentDirectory: currentDirectory,
                fileManager: fileManager
            )
        }

        if let projectPath, !projectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try detectFromExplicitPath(
                projectPath,
                expectWorkspaceOnly: false,
                currentDirectory: currentDirectory,
                fileManager: fileManager
            )
        }

        let targetPath = directoryPath ?? currentDirectory
        let canonical = DerivedDataPathCalculator.canonicalizePath(targetPath, currentDirectory: currentDirectory)

        if canonical.hasSuffix(".xcworkspace") || canonical.hasSuffix(".xcodeproj") {
            return try detectFromExplicitPath(
                canonical,
                expectWorkspaceOnly: false,
                currentDirectory: currentDirectory,
                fileManager: fileManager
            )
        }

        return try detectInDirectory(canonical, fileManager: fileManager)
    }

    /// Returns existing `Package.resolved` paths ordered by priority for the given project configuration.
    public static func locatePackageResolved(
        for type: ProjectType,
        rootPath: String,
        containerPath: String?,
        flutterTargets: [FlutterSPMTarget] = [],
        fileManager: FileManager = .default
    ) -> [String] {
        let candidates = candidatePackageResolvedPaths(
            for: type,
            rootPath: rootPath,
            containerPath: containerPath,
            flutterTargets: flutterTargets,
            fileManager: fileManager
        )
        return candidates.filter { fileManager.isRegularFile(atPath: $0) }
    }

    /// Returns ordered, deduplicated candidate `Package.resolved` paths (whether or not they exist yet).
    public static func candidatePackageResolvedPaths(
        for type: ProjectType,
        rootPath: String,
        containerPath: String?,
        flutterTargets: [FlutterSPMTarget] = [],
        fileManager: FileManager = .default
    ) -> [String] {
        var candidates: [String] = []
        let rootURL = URL(fileURLWithPath: rootPath)

        switch type {
        case .flutter:
            // Prioritize the selected container's Package.resolved first.
            if let containerPath {
                candidates.append(contentsOf: containerPackageResolvedCandidates(
                    forContainerPath: containerPath,
                    fileManager: fileManager
                ))
            }
            for target in flutterTargets {
                if let workspacePath = target.workspacePath {
                    candidates.append(contentsOf: containerPackageResolvedCandidates(
                        forContainerPath: workspacePath,
                        fileManager: fileManager
                    ))
                }
                if let projectPath = target.projectPath {
                    candidates.append(contentsOf: containerPackageResolvedCandidates(
                        forContainerPath: projectPath,
                        fileManager: fileManager
                    ))
                }
                candidates.append(
                    URL(fileURLWithPath: target.generatedPackagePath)
                        .appendingPathComponent("Package.resolved").path
                )
                candidates.append(
                    rootURL.appendingPathComponent(target.platform.rawValue)
                        .appendingPathComponent("Package.resolved").path
                )
            }
            candidates.append(rootURL.appendingPathComponent("Package.resolved").path)

        case .xcode:
            if let containerPath {
                candidates.append(contentsOf: containerPackageResolvedCandidates(
                    forContainerPath: containerPath,
                    fileManager: fileManager
                ))
            }
            candidates.append(rootURL.appendingPathComponent("Package.resolved").path)

        case .swiftPackage:
            candidates.append(rootURL.appendingPathComponent("Package.resolved").path)
        }

        return deduplicatePreservingOrder(candidates)
    }

    // MARK: - Private Detection Helpers

    private static func detectFromExplicitPath(
        _ rawPath: String,
        expectWorkspaceOnly: Bool,
        currentDirectory: String,
        fileManager: FileManager
    ) throws -> DetectedProject {
        let canonical = DerivedDataPathCalculator.canonicalizePath(rawPath, currentDirectory: currentDirectory)
        guard fileManager.fileExists(atPath: canonical) else {
            throw ProjectDetectionError.explicitPathNotFound(canonical)
        }

        let url = URL(fileURLWithPath: canonical)
        let ext = url.pathExtension

        if ext == "xcworkspace" || (!expectWorkspaceOnly && ext == "xcodeproj") {
            let normalizedContainer = normalizeContainerURL(url)
            return buildContainerProject(containerURL: normalizedContainer, fileManager: fileManager)
        }

        if !expectWorkspaceOnly && url.lastPathComponent == "Package.swift" && fileManager.isRegularFile(atPath: canonical) {
            let rootPath = url.deletingLastPathComponent().path
            let resolved = locatePackageResolved(
                for: .swiftPackage,
                rootPath: rootPath,
                containerPath: nil,
                fileManager: fileManager
            )
            return DetectedProject(
                type: .swiftPackage,
                rootPath: rootPath,
                containerPath: nil,
                packageManifestPath: canonical,
                packageResolvedPath: resolved.first,
                allPackageResolvedPaths: resolved,
                flutterInfo: nil
            )
        }

        if fileManager.isDirectory(atPath: canonical) {
            if expectWorkspaceOnly {
                if let workspace = findWorkspaces(in: url, fileManager: fileManager).first {
                    return buildContainerProject(containerURL: workspace, fileManager: fileManager)
                }
                throw ProjectDetectionError.invalidExplicitPath(canonical)
            }
            return try detectInDirectory(canonical, fileManager: fileManager)
        }

        throw ProjectDetectionError.invalidExplicitPath(canonical)
    }

    private static func detectInDirectory(_ dirPath: String, fileManager: FileManager) throws -> DetectedProject {
        guard fileManager.isDirectory(atPath: dirPath) else {
            throw ProjectDetectionError.directoryNotFound(dirPath)
        }

        let dirURL = URL(fileURLWithPath: dirPath)

        // 1. Flutter project detection
        let pubspecURL = dirURL.appendingPathComponent("pubspec.yaml")
        if fileManager.isRegularFile(atPath: pubspecURL.path) {
            let flutterTargets = inspectFlutterTargets(in: dirURL, fileManager: fileManager)
            if !flutterTargets.isEmpty {
                let flutterInfo = buildFlutterInfo(
                    rootURL: dirURL,
                    pubspecPath: pubspecURL.path,
                    targets: flutterTargets,
                    fileManager: fileManager
                )
                let primaryContainer = flutterTargets.compactMap(\.workspacePath).first
                    ?? flutterTargets.compactMap(\.projectPath).first
                let manifestPath = flutterTargets.first(where: { $0.generatedPackageManifestExists })
                    .map { URL(fileURLWithPath: $0.generatedPackagePath).appendingPathComponent("Package.swift").path }
                let resolvedPaths = locatePackageResolved(
                    for: .flutter,
                    rootPath: dirPath,
                    containerPath: primaryContainer,
                    flutterTargets: flutterTargets,
                    fileManager: fileManager
                )
                return DetectedProject(
                    type: .flutter,
                    rootPath: dirPath,
                    containerPath: primaryContainer,
                    packageManifestPath: manifestPath,
                    packageResolvedPath: resolvedPaths.first,
                    allPackageResolvedPaths: resolvedPaths,
                    flutterInfo: flutterInfo
                )
            }
        }

        // 2. Xcode workspace / project detection (.xcworkspace prioritized, ignoring project.xcworkspace)
        let workspaces = findWorkspaces(in: dirURL, fileManager: fileManager)
        let projects = findProjects(in: dirURL, fileManager: fileManager)
        if let containerURL = workspaces.first ?? projects.first {
            let packageSwiftURL = dirURL.appendingPathComponent("Package.swift")
            let manifestPath = fileManager.isRegularFile(atPath: packageSwiftURL.path) ? packageSwiftURL.path : nil
            let resolvedPaths = locatePackageResolved(
                for: .xcode,
                rootPath: dirPath,
                containerPath: containerURL.path,
                fileManager: fileManager
            )
            return DetectedProject(
                type: .xcode,
                rootPath: dirPath,
                containerPath: containerURL.path,
                packageManifestPath: manifestPath,
                packageResolvedPath: resolvedPaths.first,
                allPackageResolvedPaths: resolvedPaths,
                flutterInfo: nil
            )
        }

        // 3. Pure SwiftPM package detection
        let packageSwiftURL = dirURL.appendingPathComponent("Package.swift")
        if fileManager.isRegularFile(atPath: packageSwiftURL.path) {
            let resolvedPaths = locatePackageResolved(
                for: .swiftPackage,
                rootPath: dirPath,
                containerPath: nil,
                fileManager: fileManager
            )
            return DetectedProject(
                type: .swiftPackage,
                rootPath: dirPath,
                containerPath: nil,
                packageManifestPath: packageSwiftURL.path,
                packageResolvedPath: resolvedPaths.first,
                allPackageResolvedPaths: resolvedPaths,
                flutterInfo: nil
            )
        }

        throw ProjectDetectionError.projectNotFound(dirPath)
    }

    private static func buildContainerProject(
        containerURL: URL,
        fileManager: FileManager
    ) -> DetectedProject {
        let parentURL = containerURL.deletingLastPathComponent()
        let parentName = parentURL.lastPathComponent
        let grandParentURL = parentURL.deletingLastPathComponent()
        let pubspecURL = grandParentURL.appendingPathComponent("pubspec.yaml")

        if FlutterPlatform(rawValue: parentName) != nil,
           fileManager.isRegularFile(atPath: pubspecURL.path) {
            let targets = inspectFlutterTargets(in: grandParentURL, fileManager: fileManager)
            let flutterInfo = buildFlutterInfo(
                rootURL: grandParentURL,
                pubspecPath: pubspecURL.path,
                targets: targets,
                fileManager: fileManager
            )
            let manifestPath = targets.first(where: { $0.generatedPackageManifestExists })
                .map { URL(fileURLWithPath: $0.generatedPackagePath).appendingPathComponent("Package.swift").path }
            let resolvedPaths = locatePackageResolved(
                for: .flutter,
                rootPath: grandParentURL.path,
                containerPath: containerURL.path,
                flutterTargets: targets,
                fileManager: fileManager
            )
            return DetectedProject(
                type: .flutter,
                rootPath: grandParentURL.path,
                containerPath: containerURL.path,
                packageManifestPath: manifestPath,
                packageResolvedPath: resolvedPaths.first,
                allPackageResolvedPaths: resolvedPaths,
                flutterInfo: flutterInfo
            )
        }

        let packageSwiftURL = parentURL.appendingPathComponent("Package.swift")
        let manifestPath = fileManager.isRegularFile(atPath: packageSwiftURL.path) ? packageSwiftURL.path : nil
        let resolvedPaths = locatePackageResolved(
            for: .xcode,
            rootPath: parentURL.path,
            containerPath: containerURL.path,
            fileManager: fileManager
        )
        return DetectedProject(
            type: .xcode,
            rootPath: parentURL.path,
            containerPath: containerURL.path,
            packageManifestPath: manifestPath,
            packageResolvedPath: resolvedPaths.first,
            allPackageResolvedPaths: resolvedPaths,
            flutterInfo: nil
        )
    }

    private static func normalizeContainerURL(_ url: URL) -> URL {
        if url.lastPathComponent == "project.xcworkspace" {
            let parent = url.deletingLastPathComponent()
            if parent.pathExtension == "xcodeproj" {
                return parent
            }
        }
        return url
    }

    private static func inspectFlutterTargets(
        in rootURL: URL,
        fileManager: FileManager
    ) -> [FlutterSPMTarget] {
        var targets: [FlutterSPMTarget] = []

        for platform in FlutterPlatform.allCases {
            let platformDir = rootURL.appendingPathComponent(platform.rawValue)
            guard fileManager.isDirectory(atPath: platformDir.path) else { continue }

            let runnerWorkspace = platformDir.appendingPathComponent("Runner.xcworkspace")
            let workspaceURL = fileManager.fileExists(atPath: runnerWorkspace.path)
                ? runnerWorkspace
                : findWorkspaces(in: platformDir, fileManager: fileManager).first

            let runnerProject = platformDir.appendingPathComponent("Runner.xcodeproj")
            let projectURL = fileManager.fileExists(atPath: runnerProject.path)
                ? runnerProject
                : findProjects(in: platformDir, fileManager: fileManager).first

            let generatedPkgDir = platformDir
                .appendingPathComponent("Flutter")
                .appendingPathComponent("ephemeral")
                .appendingPathComponent("Packages")
                .appendingPathComponent("FlutterGeneratedPluginSwiftPackage")
            let generatedManifest = generatedPkgDir.appendingPathComponent("Package.swift")
            let manifestExists = fileManager.isRegularFile(atPath: generatedManifest.path)

            guard workspaceURL != nil || projectURL != nil || fileManager.fileExists(atPath: generatedPkgDir.path) else {
                continue
            }

            var targetCandidates: [String] = []
            if let workspaceURL {
                targetCandidates.append(contentsOf: containerPackageResolvedCandidates(
                    forContainerPath: workspaceURL.path,
                    fileManager: fileManager
                ))
            }
            if let projectURL {
                targetCandidates.append(contentsOf: containerPackageResolvedCandidates(
                    forContainerPath: projectURL.path,
                    fileManager: fileManager
                ))
            }
            targetCandidates.append(generatedPkgDir.appendingPathComponent("Package.resolved").path)
            targetCandidates.append(platformDir.appendingPathComponent("Package.resolved").path)

            let resolvedForTarget = deduplicatePreservingOrder(targetCandidates)
                .first { fileManager.isRegularFile(atPath: $0) }

            targets.append(FlutterSPMTarget(
                platform: platform,
                workspacePath: workspaceURL?.path,
                projectPath: projectURL?.path,
                generatedPackagePath: generatedPkgDir.path,
                generatedPackageManifestExists: manifestExists,
                packageResolvedPath: resolvedForTarget
            ))
        }

        return targets
    }

    private static func buildFlutterInfo(
        rootURL: URL,
        pubspecPath: String,
        targets: [FlutterSPMTarget],
        fileManager: FileManager
    ) -> FlutterProjectInfo {
        let depsURL = rootURL.appendingPathComponent(".flutter-plugins-dependencies")
        let depsExist = fileManager.isRegularFile(atPath: depsURL.path)
        let pluginNames = depsExist ? parseFlutterPluginDependencies(at: depsURL) : [:]
        return FlutterProjectInfo(
            pubspecPath: pubspecPath,
            pluginDependenciesPath: depsExist ? depsURL.path : nil,
            pluginNamesByPlatform: pluginNames,
            targets: targets
        )
    }

    private static func parseFlutterPluginDependencies(at url: URL) -> [FlutterPlatform: [String]] {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = json["plugins"] as? [String: Any]
        else {
            return [:]
        }

        var result: [FlutterPlatform: [String]] = [:]
        for platform in FlutterPlatform.allCases {
            guard let entries = plugins[platform.rawValue] as? [[String: Any]] else { continue }
            let names = entries.compactMap { $0["name"] as? String }
            if !names.isEmpty {
                result[platform] = names
            }
        }
        return result
    }

    private static func containerPackageResolvedCandidates(
        forContainerPath containerPath: String,
        fileManager: FileManager
    ) -> [String] {
        let containerURL = URL(fileURLWithPath: containerPath)
        let parentURL = containerURL.deletingLastPathComponent()
        var candidates: [String] = []

        if containerURL.pathExtension == "xcworkspace" {
            candidates.append(
                containerURL
                    .appendingPathComponent("xcshareddata")
                    .appendingPathComponent("swiftpm")
                    .appendingPathComponent("Package.resolved").path
            )

            // Check matching <Name>.xcodeproj first, then any sibling *.xcodeproj.
            let baseName = containerURL.deletingPathExtension().lastPathComponent
            let matchingProj = parentURL.appendingPathComponent("\(baseName).xcodeproj")
            if fileManager.fileExists(atPath: matchingProj.path) {
                candidates.append(
                    matchingProj
                        .appendingPathComponent("project.xcworkspace")
                        .appendingPathComponent("xcshareddata")
                        .appendingPathComponent("swiftpm")
                        .appendingPathComponent("Package.resolved").path
                )
            }
            for siblingProj in findProjects(in: parentURL, fileManager: fileManager) where siblingProj.path != matchingProj.path {
                candidates.append(
                    siblingProj
                        .appendingPathComponent("project.xcworkspace")
                        .appendingPathComponent("xcshareddata")
                        .appendingPathComponent("swiftpm")
                        .appendingPathComponent("Package.resolved").path
                )
            }
        } else if containerURL.pathExtension == "xcodeproj" {
            candidates.append(
                containerURL
                    .appendingPathComponent("project.xcworkspace")
                    .appendingPathComponent("xcshareddata")
                    .appendingPathComponent("swiftpm")
                    .appendingPathComponent("Package.resolved").path
            )
            candidates.append(
                containerURL
                    .appendingPathComponent("xcshareddata")
                    .appendingPathComponent("swiftpm")
                    .appendingPathComponent("Package.resolved").path
            )
        }

        return candidates
    }

    private static func findWorkspaces(in directory: URL, fileManager: FileManager) -> [URL] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries
            .filter { $0.pathExtension == "xcworkspace" && $0.lastPathComponent != "project.xcworkspace" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { directory.appendingPathComponent($0.lastPathComponent).standardized }
    }

    private static func findProjects(in directory: URL, fileManager: FileManager) -> [URL] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries
            .filter { $0.pathExtension == "xcodeproj" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { directory.appendingPathComponent($0.lastPathComponent).standardized }
    }

    private static func deduplicatePreservingOrder(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for path in paths where seen.insert(path).inserted {
            result.append(path)
        }
        return result
    }
}

private extension FileManager {
    func isDirectory(atPath path: String) -> Bool {
        var isDir: ObjCBool = false
        return fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    func isRegularFile(atPath path: String) -> Bool {
        var isDir: ObjCBool = false
        return fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue
    }
}

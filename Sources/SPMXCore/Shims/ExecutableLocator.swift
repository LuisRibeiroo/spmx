import Foundation

/// Errors thrown by ``ExecutableLocator`` when a real tool binary cannot be resolved on `PATH`.
public enum ExecutableLocatorError: Error, LocalizedError, Equatable, Sendable {
    case executableNotFound(name: String, searchedPaths: [String])

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let name, let searchedPaths):
            let joined = searchedPaths.isEmpty ? "<empty PATH>" : searchedPaths.joined(separator: ":")
            return "Could not locate real '\(name)' executable outside spmx shims in PATH: \(joined)"
        }
    }
}

/// Resolves real tool executables (`flutter`, `xcodebuild`, `swift`) on `PATH` without entering a shim loop.
public protocol ExecutableLocating: Sendable {
    func resolveExecutable(named name: String, environment: [String: String]) throws -> String
    func sanitizedEnvironment(
        from environment: [String: String],
        additionalEnvironment: [String: String]
    ) -> [String: String]
}

public extension ExecutableLocating {
    func sanitizedEnvironment(from environment: [String: String]) -> [String: String] {
        sanitizedEnvironment(from: environment, additionalEnvironment: [:])
    }
}

/// Resolves the real `flutter`, `xcodebuild`, and `swift` executables on `PATH`, filtering out
/// `~/.spmx/shims` and `SPMX_SHIMS_DIR` and skipping symlinks that resolve to `spmx` or shim directories.
///
/// Preserves `PATH` ordering for version managers such as `puro`, `fvm`, `asdf`, `mise`, `xcodes`,
/// and system tools such as `/usr/bin/xcodebuild`.
public struct ExecutableLocator: ExecutableLocating, Sendable {
    public static let shimsDirectoryEnvironmentKey = "SPMX_SHIMS_DIR"
    public static let disableEnvironmentKey = "SPMX_DISABLE"
    public static let flutterShimActiveEnvironmentKey = "SPMX_FLUTTER_SHIM_ACTIVE"
    public static let spmxBinaryNames: Set<String> = ["spmx"]

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
            normalized.insert(Self.trimTrailingSlashes(url.path))
            normalized.insert(Self.trimTrailingSlashes(url.resolvingSymlinksInPath().path))
        }
        return normalized.sorted()
    }

    /// Filters `PATH` entries, removing `~/.spmx/shims` and `SPMX_SHIMS_DIR` while preserving order.
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
                let standardized = Self.trimTrailingSlashes(url.path)
                let resolved = Self.trimTrailingSlashes(url.resolvingSymlinksInPath().path)
                if excluded.contains(standardized) || excluded.contains(resolved) {
                    return nil
                }
                return expanded
            }
    }

    /// Locates the first real executable named `name` on `PATH` outside `spmx` shim directories.
    public func resolveExecutable(
        named name: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ExecutableLocatorError.executableNotFound(name: name, searchedPaths: [])
        }

        let fileManager = FileManager.default
        let excluded = Set(excludedShimDirectories(environment: environment))

        if trimmedName.contains("/") {
            let candidate = URL(fileURLWithPath: (trimmedName as NSString).expandingTildeInPath).standardizedFileURL
            if isValidRealExecutable(candidate, excludedDirectories: excluded, fileManager: fileManager) {
                return candidate.path
            }
            throw ExecutableLocatorError.executableNotFound(name: trimmedName, searchedPaths: [candidate.deletingLastPathComponent().path])
        }

        let searchPaths = filteredPathEntries(
            from: environment["PATH"] ?? "",
            environment: environment
        )

        for directory in searchPaths {
            let candidate = URL(fileURLWithPath: directory)
                .appendingPathComponent(trimmedName)
                .standardizedFileURL

            if isValidRealExecutable(candidate, excludedDirectories: excluded, fileManager: fileManager) {
                return candidate.path
            }
        }

        throw ExecutableLocatorError.executableNotFound(name: trimmedName, searchedPaths: searchPaths)
    }

    /// Convenience helper for resolving the real `flutter` executable.
    public func resolveFlutter(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> String {
        try resolveExecutable(named: "flutter", environment: environment)
    }

    /// Convenience helper for resolving the real `xcodebuild` executable.
    public func resolveXcodebuild(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> String {
        try resolveExecutable(named: "xcodebuild", environment: environment)
    }

    /// Convenience helper for resolving the real `swift` executable.
    public func resolveSwift(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> String {
        try resolveExecutable(named: "swift", environment: environment)
    }

    /// Builds a child environment with shim directories removed from `PATH` and optional extra variables applied.
    public func sanitizedEnvironment(
        from environment: [String: String],
        additionalEnvironment: [String: String] = [:]
    ) -> [String: String] {
        var sanitized = environment
        let filteredPath = filteredPathEntries(
            from: environment["PATH"] ?? "",
            environment: environment
        ).joined(separator: ":")
        sanitized["PATH"] = filteredPath
        for (key, value) in additionalEnvironment {
            sanitized[key] = value
        }
        return sanitized
    }

    // MARK: - Private Helpers

    private func isValidRealExecutable(
        _ candidate: URL,
        excludedDirectories: Set<String>,
        fileManager: FileManager
    ) -> Bool {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDir),
              !isDir.boolValue,
              fileManager.isExecutableFile(atPath: candidate.path)
        else {
            return false
        }

        let candidateParent = Self.trimTrailingSlashes(candidate.deletingLastPathComponent().path)
        if excludedDirectories.contains(candidateParent) {
            return false
        }

        if let immediateDestination = try? fileManager.destinationOfSymbolicLink(atPath: candidate.path) {
            let resolvedImmediate = immediateDestination.hasPrefix("/")
                ? URL(fileURLWithPath: immediateDestination).standardizedFileURL
                : candidate.deletingLastPathComponent().appendingPathComponent(immediateDestination).standardizedFileURL
            let immediateParent = Self.trimTrailingSlashes(resolvedImmediate.deletingLastPathComponent().path)
            if excludedDirectories.contains(immediateParent)
                || Self.spmxBinaryNames.contains(resolvedImmediate.lastPathComponent) {
                return false
            }
        }

        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        let resolvedParent = Self.trimTrailingSlashes(resolved.deletingLastPathComponent().path)
        if excludedDirectories.contains(resolvedParent)
            || Self.spmxBinaryNames.contains(resolved.lastPathComponent) {
            return false
        }

        return true
    }

    private static func trimTrailingSlashes(_ path: String) -> String {
        var trimmed = path
        while trimmed.count > 1 && trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }
}

import Foundation

/// Package reference inside SwiftPM `workspace-state.json`.
public struct WorkspacePackageRef: Sendable, Equatable, Hashable, Codable {
    public let identity: String
    public let kind: String
    public let location: String
    public let name: String?

    public init(identity: String, kind: String, location: String, name: String? = nil) {
        self.identity = identity
        self.kind = kind
        self.location = location
        self.name = name
    }
}

/// Checkout revision/version/branch metadata for a dependency or prebuilt.
public struct WorkspaceCheckoutState: Sendable, Equatable, Hashable, Codable {
    public let revision: String?
    public let version: String?
    public let branch: String?

    public init(revision: String? = nil, version: String? = nil, branch: String? = nil) {
        self.revision = revision
        self.version = version
        self.branch = branch
    }
}

/// Dependency state inside `workspace-state.json`.
public struct WorkspaceDependencyState: Sendable, Equatable, Hashable, Codable {
    public let name: String
    public let checkoutState: WorkspaceCheckoutState?
    public let path: String?
    public let version: String?

    public init(
        name: String,
        checkoutState: WorkspaceCheckoutState? = nil,
        path: String? = nil,
        version: String? = nil
    ) {
        self.name = name
        self.checkoutState = checkoutState
        self.path = path
        self.version = version
    }
}

/// A resolved dependency entry inside `workspace-state.json` (`object.dependencies`).
public struct WorkspaceDependency: Sendable, Equatable, Codable {
    public let packageRef: WorkspacePackageRef
    public let state: WorkspaceDependencyState
    public let subpath: String?

    public init(
        packageRef: WorkspacePackageRef,
        state: WorkspaceDependencyState,
        subpath: String? = nil
    ) {
        self.packageRef = packageRef
        self.state = state
        self.subpath = subpath
    }
}

/// Source origin for a binary artifact (`binaryTarget` / `.xcframework`).
public enum WorkspaceArtifactSource: Sendable, Equatable, Hashable, Codable {
    case remote(url: String, checksum: String)
    case local(checksum: String?)
    case unknown(type: String, checksum: String?)
}

/// A binary artifact entry inside `workspace-state.json` (`object.artifacts`).
public struct WorkspaceArtifact: Sendable, Equatable, Codable {
    public let packageRef: WorkspacePackageRef
    public let targetName: String
    public let path: String
    public let kind: String?
    public let source: WorkspaceArtifactSource?
    public let checksum: String?

    public init(
        packageRef: WorkspacePackageRef,
        targetName: String,
        path: String,
        kind: String? = nil,
        source: WorkspaceArtifactSource? = nil,
        checksum: String? = nil
    ) {
        self.packageRef = packageRef
        self.targetName = targetName
        self.path = path
        self.kind = kind
        self.source = source
        if let checksum {
            self.checksum = checksum
        } else {
            switch source {
            case .remote(_, let sourceChecksum):
                self.checksum = sourceChecksum
            case .local(let sourceChecksum), .unknown(_, let sourceChecksum):
                self.checksum = sourceChecksum
            case .none:
                self.checksum = nil
            }
        }
    }
}

/// A prebuilt Swift macro/package binary entry inside `workspace-state.json` (`object.prebuilts`).
public struct WorkspacePrebuilt: Sendable, Equatable, Codable {
    public let identity: String
    public let packageRef: WorkspacePackageRef?
    public let version: String?
    public let checksum: String?
    public let libraryName: String?
    public let path: String?
    public let subpath: String?
    public let products: [String]
    public let cModules: [String]
    public let includePaths: [String]
    public let checkoutState: WorkspaceCheckoutState?

    public init(
        identity: String,
        packageRef: WorkspacePackageRef? = nil,
        version: String? = nil,
        checksum: String? = nil,
        libraryName: String? = nil,
        path: String? = nil,
        subpath: String? = nil,
        products: [String] = [],
        cModules: [String] = [],
        includePaths: [String] = [],
        checkoutState: WorkspaceCheckoutState? = nil
    ) {
        self.identity = identity
        self.packageRef = packageRef
        self.version = version
        self.checksum = checksum
        self.libraryName = libraryName
        self.path = path
        self.subpath = subpath
        self.products = products
        self.cModules = cModules
        self.includePaths = includePaths
        self.checkoutState = checkoutState
    }
}

/// Parsed representation of SwiftPM's `workspace-state.json`.
public struct WorkspaceState: Sendable, Equatable, Codable {
    public let version: Int
    public let dependencies: [WorkspaceDependency]
    public let artifacts: [WorkspaceArtifact]
    public let prebuilts: [WorkspacePrebuilt]

    public init(
        version: Int,
        dependencies: [WorkspaceDependency],
        artifacts: [WorkspaceArtifact],
        prebuilts: [WorkspacePrebuilt]
    ) {
        self.version = version
        self.dependencies = dependencies
        self.artifacts = artifacts
        self.prebuilts = prebuilts
    }
}

public enum WorkspaceStateError: Error, LocalizedError, Equatable, Sendable {
    case fileNotFound(String)
    case invalidFormat(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "workspace-state.json not found at '\(path)'."
        case .invalidFormat(let details):
            return "Invalid workspace-state.json format: \(details)"
        }
    }
}

/// Parser and lossless path-rewriter for SwiftPM's `workspace-state.json`.
public struct WorkspaceStateParser: Sendable {
    public init() {}

    /// Parses a `workspace-state.json` file from disk.
    public static func parse(fileAt path: String, fileManager: FileManager = .default) throws -> WorkspaceState {
        guard fileManager.fileExists(atPath: path) else {
            throw WorkspaceStateError.fileNotFound(path)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try parse(data: data)
    }

    /// Parses a `workspace-state.json` file from a file `URL`.
    public static func parse(url: URL) throws -> WorkspaceState {
        try parse(fileAt: url.path)
    }

    /// Parses raw JSON data of a `workspace-state.json` document.
    public static func parse(data: Data) throws -> WorkspaceState {
        let jsonObject = try parseJSONDictionary(data: data)

        guard let version = jsonObject["version"] as? Int else {
            throw WorkspaceStateError.invalidFormat("Missing integer 'version' field.")
        }

        guard let object = jsonObject["object"] as? [String: Any] else {
            throw WorkspaceStateError.invalidFormat("Missing 'object' dictionary.")
        }

        let rawDependencies = object["dependencies"] as? [[String: Any]] ?? []
        let rawArtifacts = object["artifacts"] as? [[String: Any]] ?? []
        let rawPrebuilts = object["prebuilts"] as? [[String: Any]] ?? []

        let dependencies = try rawDependencies.enumerated().map { index, raw in
            try parseDependency(raw, index: index)
        }
        let artifacts = try rawArtifacts.enumerated().map { index, raw in
            try parseArtifact(raw, index: index)
        }
        let prebuilts = try rawPrebuilts.enumerated().map { index, raw in
            try parsePrebuilt(raw, index: index)
        }

        return WorkspaceState(
            version: version,
            dependencies: dependencies,
            artifacts: artifacts,
            prebuilts: prebuilts
        )
    }

    /// Losslessly rewrites absolute `artifacts` and `prebuilts` paths inside `workspace-state.json`
    /// to point to `newRoot` (e.g. the target worktree's `SourcePackages` or `.build` directory),
    /// preserving all unknown fields and formatting cleanly.
    ///
    /// - Parameters:
    ///   - data: Raw `workspace-state.json` bytes.
    ///   - newRoot: Target `SourcePackages` or `.build` absolute directory path.
    ///   - oldRoot: Optional explicit source root to replace. When `nil`, anchors on
    ///     `/SourcePackages/(artifacts|prebuilts|checkouts)`, `/.build/(artifacts|prebuilts|checkouts)`,
    ///     or `/(artifacts|prebuilts)`.
    ///   - rewriteLocalDependencies: When `true` and `oldRoot` is provided, also rewrites
    ///     matching local paths inside `dependencies`.
    public static func rewritingPaths(
        in data: Data,
        toNewSourcePackagesPath newRoot: String,
        replacingOldSourcePackagesPath oldRoot: String? = nil,
        rewriteLocalDependencies: Bool = false
    ) throws -> Data {
        var root = try parseJSONDictionary(data: data)

        guard var object = root["object"] as? [String: Any] else {
            throw WorkspaceStateError.invalidFormat("Missing 'object' dictionary.")
        }

        let normalizedNewRoot = stripTrailingSlashes(newRoot)
        let normalizedOldRoot = oldRoot.map(stripTrailingSlashes)

        if let rawArtifacts = object["artifacts"] as? [Any] {
            object["artifacts"] = rawArtifacts.map { entry in
                rewriteJSONValue(
                    entry,
                    section: .artifacts,
                    oldRoot: normalizedOldRoot,
                    newRoot: normalizedNewRoot
                )
            }
        }

        if let rawPrebuilts = object["prebuilts"] as? [Any] {
            object["prebuilts"] = rawPrebuilts.map { entry in
                rewriteJSONValue(
                    entry,
                    section: .prebuilts,
                    oldRoot: normalizedOldRoot,
                    newRoot: normalizedNewRoot
                )
            }
        }

        if rewriteLocalDependencies,
           let normalizedOldRoot,
           let rawDependencies = object["dependencies"] as? [Any] {
            object["dependencies"] = rawDependencies.map { entry in
                rewriteDependencyEntry(
                    entry,
                    oldRoot: normalizedOldRoot,
                    newRoot: normalizedNewRoot
                )
            }
        }

        root["object"] = object

        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    /// Reads `workspace-state.json` from `sourcePath`, rewrites paths to `newRoot`, and writes
    /// atomically to `destinationPath` (defaults to `sourcePath`).
    public static func rewritePaths(
        inFileAt sourcePath: String,
        writingTo destinationPath: String? = nil,
        toNewSourcePackagesPath newRoot: String,
        replacingOldSourcePackagesPath oldRoot: String? = nil,
        rewriteLocalDependencies: Bool = false,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: sourcePath) else {
            throw WorkspaceStateError.fileNotFound(sourcePath)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
        let rewritten = try rewritingPaths(
            in: data,
            toNewSourcePackagesPath: newRoot,
            replacingOldSourcePackagesPath: oldRoot,
            rewriteLocalDependencies: rewriteLocalDependencies
        )
        let targetURL = URL(fileURLWithPath: destinationPath ?? sourcePath)
        try rewritten.write(to: targetURL, options: .atomic)
    }

    // MARK: - Private Parsing Helpers

    private static func parseJSONDictionary(data: Data) throws -> [String: Any] {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw WorkspaceStateError.invalidFormat("Malformed JSON (\(error.localizedDescription)).")
        }

        guard let dictionary = jsonObject as? [String: Any] else {
            throw WorkspaceStateError.invalidFormat("Top-level JSON value must be an object.")
        }
        return dictionary
    }

    private static func parseDependency(_ raw: [String: Any], index: Int) throws -> WorkspaceDependency {
        guard let rawRef = raw["packageRef"] as? [String: Any] else {
            throw WorkspaceStateError.invalidFormat("Dependency at index \(index) is missing 'packageRef'.")
        }
        let packageRef = try parsePackageRef(rawRef, context: "dependency[\(index)]")

        guard let rawState = raw["state"] as? [String: Any],
              let stateName = optionalString(rawState["name"])
        else {
            throw WorkspaceStateError.invalidFormat("Dependency '\(packageRef.identity)' is missing 'state.name'.")
        }

        let checkoutState = (rawState["checkoutState"] as? [String: Any]).map(parseCheckoutState)
        let depState = WorkspaceDependencyState(
            name: stateName,
            checkoutState: checkoutState,
            path: optionalString(rawState["path"]),
            version: optionalString(rawState["version"])
        )

        return WorkspaceDependency(
            packageRef: packageRef,
            state: depState,
            subpath: optionalString(raw["subpath"])
        )
    }

    private static func parseArtifact(_ raw: [String: Any], index: Int) throws -> WorkspaceArtifact {
        guard let rawRef = raw["packageRef"] as? [String: Any] else {
            throw WorkspaceStateError.invalidFormat("Artifact at index \(index) is missing 'packageRef'.")
        }
        let packageRef = try parsePackageRef(rawRef, context: "artifact[\(index)]")

        guard let targetName = optionalString(raw["targetName"]) else {
            throw WorkspaceStateError.invalidFormat("Artifact at index \(index) is missing 'targetName'.")
        }
        guard let path = optionalString(raw["path"]) else {
            throw WorkspaceStateError.invalidFormat("Artifact '\(targetName)' is missing 'path'.")
        }

        let kind = parseArtifactKind(raw["kind"])
        let source = parseArtifactSource(raw["source"])
        let directChecksum = optionalString(raw["checksum"])

        return WorkspaceArtifact(
            packageRef: packageRef,
            targetName: targetName,
            path: path,
            kind: kind,
            source: source,
            checksum: directChecksum
        )
    }

    private static func parsePrebuilt(_ raw: [String: Any], index: Int) throws -> WorkspacePrebuilt {
        let packageRef = try (raw["packageRef"] as? [String: Any]).map {
            try parsePackageRef($0, context: "prebuilt[\(index)]")
        }
        let identity = optionalString(raw["identity"]) ?? packageRef?.identity
        guard let identity else {
            throw WorkspaceStateError.invalidFormat("Prebuilt at index \(index) is missing 'identity' or 'packageRef.identity'.")
        }

        let checkoutState = (raw["checkoutState"] as? [String: Any]).map(parseCheckoutState)
        let version = optionalString(raw["version"]) ?? checkoutState?.version
        let includePaths: [String]
        if let array = raw["includePath"] as? [String] {
            includePaths = array
        } else if let single = optionalString(raw["includePath"]) {
            includePaths = [single]
        } else if let array = raw["includePaths"] as? [String] {
            includePaths = array
        } else {
            includePaths = []
        }

        return WorkspacePrebuilt(
            identity: identity,
            packageRef: packageRef,
            version: version,
            checksum: optionalString(raw["checksum"]),
            libraryName: optionalString(raw["libraryName"]),
            path: optionalString(raw["path"]),
            subpath: optionalString(raw["subpath"]),
            products: raw["products"] as? [String] ?? [],
            cModules: raw["cModules"] as? [String] ?? [],
            includePaths: includePaths,
            checkoutState: checkoutState
        )
    }

    private static func parsePackageRef(_ raw: [String: Any], context: String) throws -> WorkspacePackageRef {
        guard let identity = optionalString(raw["identity"]) else {
            throw WorkspaceStateError.invalidFormat("\(context) packageRef is missing 'identity'.")
        }
        let kind = optionalString(raw["kind"]) ?? "remoteSourceControl"
        let location = optionalString(raw["location"]) ?? optionalString(raw["path"]) ?? ""
        let name = optionalString(raw["name"])
        return WorkspacePackageRef(identity: identity, kind: kind, location: location, name: name)
    }

    private static func parseCheckoutState(_ raw: [String: Any]) -> WorkspaceCheckoutState {
        WorkspaceCheckoutState(
            revision: optionalString(raw["revision"]),
            version: optionalString(raw["version"]),
            branch: optionalString(raw["branch"])
        )
    }

    private static func parseArtifactKind(_ raw: Any?) -> String? {
        if let str = optionalString(raw) {
            return str
        }
        if let dict = raw as? [String: Any] {
            return dict.keys.sorted().first
        }
        return nil
    }

    private static func parseArtifactSource(_ raw: Any?) -> WorkspaceArtifactSource? {
        guard let dict = raw as? [String: Any] else { return nil }

        if let type = optionalString(dict["type"]) {
            let checksum = optionalString(dict["checksum"])
            switch type {
            case "remote":
                let url = optionalString(dict["url"]) ?? ""
                return .remote(url: url, checksum: checksum ?? "")
            case "local":
                return .local(checksum: checksum)
            default:
                return .unknown(type: type, checksum: checksum)
            }
        }

        if let remoteDict = dict["remote"] as? [String: Any] {
            let url = optionalString(remoteDict["url"]) ?? ""
            let checksum = optionalString(remoteDict["checksum"]) ?? ""
            return .remote(url: url, checksum: checksum)
        }

        if let localDict = dict["local"] as? [String: Any] {
            return .local(checksum: optionalString(localDict["checksum"]))
        }

        return nil
    }

    private static func optionalString(_ value: Any?) -> String? {
        guard let str = value as? String, !str.isEmpty else {
            return nil
        }
        return str
    }

    // MARK: - Private Path Rewriting Helpers

    private enum RewriteSection {
        case artifacts
        case prebuilts

        var anchorMarkers: [String] {
            switch self {
            case .artifacts:
                return [
                    "/SourcePackages/artifacts/",
                    "/.build/artifacts/",
                    "/SourcePackages/prebuilts/",
                    "/.build/prebuilts/",
                    "/SourcePackages/checkouts/",
                    "/.build/checkouts/",
                    "/artifacts/"
                ]
            case .prebuilts:
                return [
                    "/SourcePackages/prebuilts/",
                    "/.build/prebuilts/",
                    "/SourcePackages/checkouts/",
                    "/.build/checkouts/",
                    "/SourcePackages/artifacts/",
                    "/.build/artifacts/",
                    "/prebuilts/"
                ]
            }
        }

        var exactDirectoryMarkers: [String] {
            switch self {
            case .artifacts:
                return ["/SourcePackages/artifacts", "/.build/artifacts", "/artifacts"]
            case .prebuilts:
                return ["/SourcePackages/prebuilts", "/.build/prebuilts", "/prebuilts"]
            }
        }
    }

    private static func rewriteJSONValue(
        _ value: Any,
        section: RewriteSection,
        oldRoot: String?,
        newRoot: String
    ) -> Any {
        if let str = value as? String {
            return rewriteAbsolutePath(str, section: section, oldRoot: oldRoot, newRoot: newRoot)
        }
        if let array = value as? [Any] {
            return array.map { rewriteJSONValue($0, section: section, oldRoot: oldRoot, newRoot: newRoot) }
        }
        if let dict = value as? [String: Any] {
            var updated: [String: Any] = [:]
            updated.reserveCapacity(dict.count)
            for (key, nested) in dict {
                updated[key] = rewriteJSONValue(nested, section: section, oldRoot: oldRoot, newRoot: newRoot)
            }
            return updated
        }
        return value
    }

    private static func rewriteDependencyEntry(
        _ entry: Any,
        oldRoot: String,
        newRoot: String
    ) -> Any {
        guard var dict = entry as? [String: Any] else { return entry }
        if var packageRef = dict["packageRef"] as? [String: Any] {
            if let location = packageRef["location"] as? String {
                packageRef["location"] = replacePrefix(location, oldRoot: oldRoot, newRoot: newRoot)
            }
            if let path = packageRef["path"] as? String {
                packageRef["path"] = replacePrefix(path, oldRoot: oldRoot, newRoot: newRoot)
            }
            dict["packageRef"] = packageRef
        }
        if var state = dict["state"] as? [String: Any],
           let path = state["path"] as? String {
            state["path"] = replacePrefix(path, oldRoot: oldRoot, newRoot: newRoot)
            dict["state"] = state
        }
        return dict
    }

    private static func rewriteAbsolutePath(
        _ path: String,
        section: RewriteSection,
        oldRoot: String?,
        newRoot: String
    ) -> String {
        guard path.hasPrefix("/") else { return path }

        if let oldRoot {
            return replacePrefix(path, oldRoot: oldRoot, newRoot: newRoot)
        }

        // Infer boundary from `/SourcePackages/<subdir>/...`, `/.build/<subdir>/...`, or `/<subdir>/...`.
        for marker in section.anchorMarkers {
            if let range = path.range(of: marker) {
                let subdirPrefix: String
                if marker.hasPrefix("/SourcePackages/") {
                    subdirPrefix = String(marker.dropFirst("/SourcePackages".count))
                } else if marker.hasPrefix("/.build/") {
                    subdirPrefix = String(marker.dropFirst("/.build".count))
                } else {
                    subdirPrefix = marker
                }
                let remainder = String(path[range.upperBound...])
                return "\(newRoot)\(subdirPrefix)\(remainder)"
            }
        }

        for marker in section.exactDirectoryMarkers where path.hasSuffix(marker) {
            let subdir: String
            if marker.hasPrefix("/SourcePackages/") {
                subdir = String(marker.dropFirst("/SourcePackages".count))
            } else if marker.hasPrefix("/.build/") {
                subdir = String(marker.dropFirst("/.build".count))
            } else {
                subdir = marker
            }
            return "\(newRoot)\(subdir)"
        }

        return path
    }

    private static func replacePrefix(_ path: String, oldRoot: String, newRoot: String) -> String {
        if path == oldRoot {
            return newRoot
        }
        if path.hasPrefix(oldRoot + "/") {
            let suffix = path.dropFirst(oldRoot.count)
            return newRoot + suffix
        }
        return path
    }

    private static func stripTrailingSlashes(_ path: String) -> String {
        var result = path
        while result.count > 1 && result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}

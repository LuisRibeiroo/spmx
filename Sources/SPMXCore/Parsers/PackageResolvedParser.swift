import Foundation

/// Dependency source kind in SwiftPM `Package.resolved`.
public enum PinKind: Sendable, Equatable, Hashable, Codable {
    case remoteSourceControl
    case registry
    case localSourceControl
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "remoteSourceControl":
            self = .remoteSourceControl
        case "registry":
            self = .registry
        case "localSourceControl":
            self = .localSourceControl
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .remoteSourceControl:
            return "remoteSourceControl"
        case .registry:
            return "registry"
        case .localSourceControl:
            return "localSourceControl"
        case .unknown(let value):
            return value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self.init(rawValue: value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Normalized representation of a single pinned dependency from `Package.resolved` v1, v2, or v3.
public struct PackagePin: Sendable, Equatable, Hashable, Codable {
    public let identity: String
    public let kind: PinKind
    public let location: String
    public let revision: String?
    public let version: String?
    public let branch: String?
    public let packageName: String?

    public init(
        identity: String,
        kind: PinKind,
        location: String,
        revision: String?,
        version: String?,
        branch: String?,
        packageName: String? = nil
    ) {
        self.identity = identity
        self.kind = kind
        self.location = location
        self.revision = revision
        self.version = version
        self.branch = branch
        self.packageName = packageName
    }
}

/// Parsed `Package.resolved` document (supports schema versions 1, 2, and 3).
public struct PackageResolved: Sendable, Equatable, Codable {
    public let version: Int
    public let originHash: String?
    public let pins: [PackagePin]

    public init(version: Int, originHash: String? = nil, pins: [PackagePin]) {
        self.version = version
        self.originHash = originHash
        self.pins = pins
    }
}

public enum PackageResolvedError: Error, LocalizedError, Equatable, Sendable {
    case fileNotFound(String)
    case unsupportedVersion(Int)
    case invalidFormat(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Package.resolved not found at '\(path)'."
        case .unsupportedVersion(let version):
            return "Unsupported Package.resolved schema version: \(version)."
        case .invalidFormat(let details):
            return "Invalid Package.resolved format: \(details)"
        }
    }
}

/// Parser for SwiftPM `Package.resolved` schema versions 1, 2, and 3.
public struct PackageResolvedParser: Sendable {
    public init() {}

    /// Parses a `Package.resolved` file from disk.
    public static func parse(fileAt path: String, fileManager: FileManager = .default) throws -> PackageResolved {
        guard fileManager.fileExists(atPath: path) else {
            throw PackageResolvedError.fileNotFound(path)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try parse(data: data)
    }

    /// Parses a `Package.resolved` file from a file `URL`.
    public static func parse(url: URL) throws -> PackageResolved {
        try parse(fileAt: url.path)
    }

    /// Parses raw JSON bytes from a `Package.resolved` v1, v2, or v3 document.
    public static func parse(data: Data) throws -> PackageResolved {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw PackageResolvedError.invalidFormat("Malformed JSON (\(error.localizedDescription)).")
        }

        guard let root = jsonObject as? [String: Any] else {
            throw PackageResolvedError.invalidFormat("Top-level JSON value must be an object.")
        }

        guard let version = root["version"] as? Int else {
            throw PackageResolvedError.invalidFormat("Missing integer 'version' field.")
        }

        switch version {
        case 1:
            return try parseV1(root: root)
        case 2, 3:
            return try parseV2OrV3(root: root, version: version)
        default:
            throw PackageResolvedError.unsupportedVersion(version)
        }
    }

    /// Derives a lowercase SwiftPM package identity from a repository URL or local path,
    /// falling back to the v1 `package` name when the location does not yield a stem.
    public static func deriveIdentity(fromLocation location: String, fallbackPackageName: String? = nil) -> String {
        var trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        if let queryOrFragment = trimmed.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            trimmed = String(trimmed[..<queryOrFragment])
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        var candidate: String?
        if let schemeRange = trimmed.range(of: "://") {
            let afterScheme = trimmed[schemeRange.upperBound...]
            if trimmed.lowercased().hasPrefix("file://") {
                let pathPart = String(afterScheme)
                candidate = pathPart.split(separator: "/").last.map(String.init)
            } else if let slashIndex = afterScheme.firstIndex(of: "/") {
                let pathPart = String(afterScheme[slashIndex...])
                candidate = pathPart.split(separator: "/").last.map(String.init)
            }
        } else {
            // Handles both local paths (`/a/b/Pkg`) and SCP-style SSH URLs (`git@github.com:org/Pkg.git` or `git@host:Pkg.git`).
            let lastSlashComponent = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
            if let colonIndex = lastSlashComponent.lastIndex(of: ":") {
                let afterColon = String(lastSlashComponent[lastSlashComponent.index(after: colonIndex)...])
                candidate = afterColon.isEmpty ? nil : afterColon
            } else if !lastSlashComponent.isEmpty {
                candidate = lastSlashComponent
            }
        }

        if var stem = candidate, !stem.isEmpty {
            if stem.lowercased().hasSuffix(".git") {
                stem = String(stem.dropLast(4))
            }
            if !stem.isEmpty {
                return stem.lowercased()
            }
        }

        if let fallback = fallbackPackageName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fallback.isEmpty {
            return fallback.lowercased()
        }

        return ""
    }

    // MARK: - Schema Parsers

    private static func parseV1(root: [String: Any]) throws -> PackageResolved {
        guard let object = root["object"] as? [String: Any],
              let rawPins = object["pins"] as? [[String: Any]]
        else {
            throw PackageResolvedError.invalidFormat("Schema v1 requires 'object.pins' array.")
        }

        let pins: [PackagePin] = try rawPins.enumerated().map { index, rawPin in
            let packageName = optionalString(rawPin["package"])
            let repositoryURL = optionalString(rawPin["repositoryURL"]) ?? ""
            let explicitIdentity = optionalString(rawPin["identity"])

            if repositoryURL.isEmpty && packageName == nil && explicitIdentity == nil {
                throw PackageResolvedError.invalidFormat("Pin at index \(index) is missing 'repositoryURL' and 'package'.")
            }

            let identity = explicitIdentity ?? deriveIdentity(
                fromLocation: repositoryURL,
                fallbackPackageName: packageName
            )
            guard !identity.isEmpty else {
                throw PackageResolvedError.invalidFormat("Unable to derive identity for v1 pin at index \(index).")
            }

            let kind: PinKind
            if let explicitKind = optionalString(rawPin["kind"]) {
                kind = PinKind(rawValue: explicitKind)
            } else if repositoryURL.hasPrefix("/") || repositoryURL.lowercased().hasPrefix("file://") {
                kind = .localSourceControl
            } else {
                kind = .remoteSourceControl
            }

            guard let state = rawPin["state"] as? [String: Any] else {
                throw PackageResolvedError.invalidFormat("Pin '\(identity)' is missing 'state' object.")
            }

            return PackagePin(
                identity: identity,
                kind: kind,
                location: repositoryURL,
                revision: optionalString(state["revision"]),
                version: optionalString(state["version"]),
                branch: optionalString(state["branch"]),
                packageName: packageName
            )
        }

        return PackageResolved(version: 1, originHash: nil, pins: pins)
    }

    private static func parseV2OrV3(root: [String: Any], version: Int) throws -> PackageResolved {
        guard let rawPins = root["pins"] as? [[String: Any]] else {
            throw PackageResolvedError.invalidFormat("Schema v\(version) requires top-level 'pins' array.")
        }

        let originHash = optionalString(root["originHash"])

        let pins: [PackagePin] = try rawPins.enumerated().map { index, rawPin in
            let location = optionalString(rawPin["location"]) ?? ""
            let explicitIdentity = optionalString(rawPin["identity"])
            let identity = explicitIdentity ?? deriveIdentity(fromLocation: location, fallbackPackageName: nil)

            guard !identity.isEmpty else {
                throw PackageResolvedError.invalidFormat("Pin at index \(index) is missing 'identity'.")
            }

            guard let rawKind = optionalString(rawPin["kind"]) else {
                throw PackageResolvedError.invalidFormat("Pin '\(identity)' is missing 'kind'.")
            }

            guard let state = rawPin["state"] as? [String: Any] else {
                throw PackageResolvedError.invalidFormat("Pin '\(identity)' is missing 'state' object.")
            }

            return PackagePin(
                identity: identity,
                kind: PinKind(rawValue: rawKind),
                location: location,
                revision: optionalString(state["revision"]),
                version: optionalString(state["version"]),
                branch: optionalString(state["branch"]),
                packageName: nil
            )
        }

        return PackageResolved(version: version, originHash: originHash, pins: pins)
    }

    private static func optionalString(_ value: Any?) -> String? {
        guard let str = value as? String, !str.isEmpty else {
            return nil
        }
        return str
    }
}

import Foundation

/// Errors thrown during `hydrate` or `harvest` operations.
public enum SyncError: Error, LocalizedError, Equatable, Sendable {
    case missingContainerPath(projectRoot: String)
    case packageResolvedNotFound(projectRoot: String)
    case workspaceStateNotFound(sourcePackagesPath: String)
    case invalidWorkspaceState(path: String, message: String)
    case toolchainUnavailable(String)
    case ioFailed(operation: String, path: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .missingContainerPath(let projectRoot):
            return "Unable to resolve Xcode container path for project at '\(projectRoot)'."
        case .packageResolvedNotFound(let projectRoot):
            return "No Package.resolved found for project at '\(projectRoot)'."
        case .workspaceStateNotFound(let sourcePackagesPath):
            return "No workspace-state.json found at '\(sourcePackagesPath)'."
        case .invalidWorkspaceState(let path, let message):
            return "Invalid workspace-state.json at '\(path)': \(message)."
        case .toolchainUnavailable(let details):
            return "Unable to determine active Swift/Xcode toolchain: \(details)."
        case .ioFailed(let operation, let path, let message):
            return "Failed to \(operation) at '\(path)': \(message)."
        }
    }
}

/// Configuration options for ``PackageSyncEngine/hydrate(project:options:)``.
public struct HydrateOptions: Sendable {
    public var sourcePackagesOverride: String?
    public var force: Bool
    public var deduplicateCleanEntries: Bool
    public var includeArtifacts: Bool
    public var includePrebuilts: Bool
    public var rewriteWorkspaceState: Bool
    public var registerProject: Bool
    public var verboseLogger: (@Sendable (String) -> Void)?

    public init(
        sourcePackagesOverride: String? = nil,
        force: Bool = false,
        deduplicateCleanEntries: Bool = false,
        includeArtifacts: Bool = true,
        includePrebuilts: Bool = true,
        rewriteWorkspaceState: Bool = true,
        registerProject: Bool = true,
        verboseLogger: (@Sendable (String) -> Void)? = nil
    ) {
        self.sourcePackagesOverride = sourcePackagesOverride
        self.force = force
        self.deduplicateCleanEntries = deduplicateCleanEntries
        self.includeArtifacts = includeArtifacts
        self.includePrebuilts = includePrebuilts
        self.rewriteWorkspaceState = rewriteWorkspaceState
        self.registerProject = registerProject
        self.verboseLogger = verboseLogger
    }
}

/// Configuration options for ``PackageSyncEngine/harvest(project:options:)``.
public struct HarvestOptions: Sendable {
    public var sourcePackagesOverride: String?
    public var overwriteStore: Bool
    public var registerProject: Bool
    public var verboseLogger: (@Sendable (String) -> Void)?

    public init(
        sourcePackagesOverride: String? = nil,
        overwriteStore: Bool = false,
        registerProject: Bool = true,
        verboseLogger: (@Sendable (String) -> Void)? = nil
    ) {
        self.sourcePackagesOverride = sourcePackagesOverride
        self.overwriteStore = overwriteStore
        self.registerProject = registerProject
        self.verboseLogger = verboseLogger
    }
}

/// Reason a checkout was skipped during `hydrate`.
public enum SkippedCheckoutReason: String, Sendable, Equatable, Codable {
    case locallyModified
    case alreadyExists
    case missingRevision
    case notInStore
}

/// Details of a checkout materialized into a project's `SourcePackages/checkouts` (or `.build/checkouts`).
public struct HydratedCheckout: Sendable, Equatable {
    public let identity: String
    public let revision: String
    public let destinationURL: URL
    public let cloneMethod: CloneMethod

    public init(
        identity: String,
        revision: String,
        destinationURL: URL,
        cloneMethod: CloneMethod
    ) {
        self.identity = identity
        self.revision = revision
        self.destinationURL = destinationURL
        self.cloneMethod = cloneMethod
    }
}

/// Details of a checkout skipped during `hydrate`.
public struct SkippedCheckout: Sendable, Equatable {
    public let identity: String
    public let revision: String?
    public let destinationURL: URL?
    public let reason: SkippedCheckoutReason

    public init(
        identity: String,
        revision: String?,
        destinationURL: URL?,
        reason: SkippedCheckoutReason
    ) {
        self.identity = identity
        self.revision = revision
        self.destinationURL = destinationURL
        self.reason = reason
    }
}

/// Details of a binary artifact materialized into `SourcePackages/artifacts` (or `.build/artifacts`).
public struct HydratedArtifact: Sendable, Equatable {
    public let identity: String
    public let targetName: String
    public let checksum: String
    public let destinationURL: URL
    public let cloneMethod: CloneMethod

    public init(
        identity: String,
        targetName: String,
        checksum: String,
        destinationURL: URL,
        cloneMethod: CloneMethod
    ) {
        self.identity = identity
        self.targetName = targetName
        self.checksum = checksum
        self.destinationURL = destinationURL
        self.cloneMethod = cloneMethod
    }
}

/// Details of a toolchain-matched prebuilt materialized into `SourcePackages/prebuilts` (or `.build/prebuilts`).
public struct HydratedPrebuilt: Sendable, Equatable {
    public let identity: String
    public let versionOrChecksum: String
    public let toolchainHash: String
    public let destinationURL: URL
    public let cloneMethod: CloneMethod

    public init(
        identity: String,
        versionOrChecksum: String,
        toolchainHash: String,
        destinationURL: URL,
        cloneMethod: CloneMethod
    ) {
        self.identity = identity
        self.versionOrChecksum = versionOrChecksum
        self.toolchainHash = toolchainHash
        self.destinationURL = destinationURL
        self.cloneMethod = cloneMethod
    }
}

/// Summary returned by ``PackageSyncEngine/hydrate(project:options:)``.
public struct HydrateResult: Sendable, Equatable {
    public let project: DetectedProject
    public let sourcePackagesURL: URL
    public let packageResolvedPath: String
    public let toolchainHash: String?
    public let hydratedCheckouts: [HydratedCheckout]
    public let skippedCheckouts: [SkippedCheckout]
    public let hydratedArtifacts: [HydratedArtifact]
    public let hydratedPrebuilts: [HydratedPrebuilt]
    public let workspaceStateURL: URL?
    public let didUpdateWorkspaceState: Bool

    public init(
        project: DetectedProject,
        sourcePackagesURL: URL,
        packageResolvedPath: String,
        toolchainHash: String?,
        hydratedCheckouts: [HydratedCheckout],
        skippedCheckouts: [SkippedCheckout],
        hydratedArtifacts: [HydratedArtifact],
        hydratedPrebuilts: [HydratedPrebuilt],
        workspaceStateURL: URL?,
        didUpdateWorkspaceState: Bool
    ) {
        self.project = project
        self.sourcePackagesURL = sourcePackagesURL
        self.packageResolvedPath = packageResolvedPath
        self.toolchainHash = toolchainHash
        self.hydratedCheckouts = hydratedCheckouts
        self.skippedCheckouts = skippedCheckouts
        self.hydratedArtifacts = hydratedArtifacts
        self.hydratedPrebuilts = hydratedPrebuilts
        self.workspaceStateURL = workspaceStateURL
        self.didUpdateWorkspaceState = didUpdateWorkspaceState
    }
}

/// Details of a checkout harvested into ``GlobalStore``.
public struct HarvestedCheckout: Sendable, Equatable {
    public let identity: String
    public let revision: String
    public let sourceURL: URL
    public let storeURL: URL
    public let alreadyCached: Bool
    public let cloneMethod: CloneMethod?

    public init(
        identity: String,
        revision: String,
        sourceURL: URL,
        storeURL: URL,
        alreadyCached: Bool,
        cloneMethod: CloneMethod?
    ) {
        self.identity = identity
        self.revision = revision
        self.sourceURL = sourceURL
        self.storeURL = storeURL
        self.alreadyCached = alreadyCached
        self.cloneMethod = cloneMethod
    }
}

/// Details of a binary artifact harvested into ``GlobalStore``.
public struct HarvestedArtifact: Sendable, Equatable {
    public let identity: String
    public let targetName: String
    public let checksum: String
    public let sourceURL: URL
    public let storeURL: URL
    public let alreadyCached: Bool
    public let cloneMethod: CloneMethod?

    public init(
        identity: String,
        targetName: String,
        checksum: String,
        sourceURL: URL,
        storeURL: URL,
        alreadyCached: Bool,
        cloneMethod: CloneMethod?
    ) {
        self.identity = identity
        self.targetName = targetName
        self.checksum = checksum
        self.sourceURL = sourceURL
        self.storeURL = storeURL
        self.alreadyCached = alreadyCached
        self.cloneMethod = cloneMethod
    }
}

/// Details of a toolchain-keyed prebuilt harvested into ``GlobalStore``.
public struct HarvestedPrebuilt: Sendable, Equatable {
    public let identity: String
    public let versionOrChecksum: String
    public let toolchainHash: String
    public let sourceURL: URL
    public let storeURL: URL
    public let alreadyCached: Bool
    public let cloneMethod: CloneMethod?

    public init(
        identity: String,
        versionOrChecksum: String,
        toolchainHash: String,
        sourceURL: URL,
        storeURL: URL,
        alreadyCached: Bool,
        cloneMethod: CloneMethod?
    ) {
        self.identity = identity
        self.versionOrChecksum = versionOrChecksum
        self.toolchainHash = toolchainHash
        self.sourceURL = sourceURL
        self.storeURL = storeURL
        self.alreadyCached = alreadyCached
        self.cloneMethod = cloneMethod
    }
}

/// Describes an item ignored during `harvest` (e.g. `.partial` marker or missing revision/checksum).
public struct SkippedHarvestItem: Sendable, Equatable {
    public let kind: String
    public let identifier: String
    public let path: String
    public let reason: String

    public init(kind: String, identifier: String, path: String, reason: String) {
        self.kind = kind
        self.identifier = identifier
        self.path = path
        self.reason = reason
    }
}

/// Summary returned by ``PackageSyncEngine/harvest(project:options:)``.
public struct HarvestResult: Sendable, Equatable {
    public let project: DetectedProject
    public let sourcePackagesURL: URL
    public let toolchainHash: String?
    public let harvestedCheckouts: [HarvestedCheckout]
    public let harvestedArtifacts: [HarvestedArtifact]
    public let harvestedPrebuilts: [HarvestedPrebuilt]
    public let skippedItems: [SkippedHarvestItem]
    public let savedTemplateURL: URL?

    public init(
        project: DetectedProject,
        sourcePackagesURL: URL,
        toolchainHash: String?,
        harvestedCheckouts: [HarvestedCheckout],
        harvestedArtifacts: [HarvestedArtifact],
        harvestedPrebuilts: [HarvestedPrebuilt],
        skippedItems: [SkippedHarvestItem],
        savedTemplateURL: URL?
    ) {
        self.project = project
        self.sourcePackagesURL = sourcePackagesURL
        self.toolchainHash = toolchainHash
        self.harvestedCheckouts = harvestedCheckouts
        self.harvestedArtifacts = harvestedArtifacts
        self.harvestedPrebuilts = harvestedPrebuilts
        self.skippedItems = skippedItems
        self.savedTemplateURL = savedTemplateURL
    }
}

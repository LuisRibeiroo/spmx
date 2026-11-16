import CryptoKit
import Foundation

/// Errors thrown by ``GlobalStore`` during store layout, indexing, or entry operations.
public enum GlobalStoreError: Error, LocalizedError, Equatable, Sendable {
    case invalidPathComponent(String)
    case entryNotFound(String)
    case corruptedIndex(path: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidPathComponent(let component):
            return "Invalid store path component: '\(component)'."
        case .entryNotFound(let path):
            return "Store entry does not exist: '\(path)'."
        case .corruptedIndex(let path, let message):
            return "Corrupted store index at '\(path)': \(message)."
        }
    }
}

/// Metadata persisted in `~/.spmx/store/index.json`.
public struct StoreIndex: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    /// Registered project or Git worktree entry tracked for `prune` and `status`.
    public struct RegisteredProject: Codable, Equatable, Sendable {
        public let path: String
        public var registeredAt: Date
        public var lastAccessedAt: Date
        public var toolchainHash: String?
        public var packageIdentities: [String]

        public init(
            path: String,
            registeredAt: Date = Date(),
            lastAccessedAt: Date = Date(),
            toolchainHash: String? = nil,
            packageIdentities: [String] = []
        ) {
            self.path = path
            self.registeredAt = registeredAt
            self.lastAccessedAt = lastAccessedAt
            self.toolchainHash = toolchainHash
            self.packageIdentities = packageIdentities
        }
    }

    /// Toolchain metadata recorded for `prebuilts/` partitioning and diagnostics.
    public struct ToolchainRecord: Codable, Equatable, Sendable {
        public let fingerprint: ToolchainFingerprint
        public var lastSeenAt: Date

        public init(fingerprint: ToolchainFingerprint, lastSeenAt: Date = Date()) {
            self.fingerprint = fingerprint
            self.lastSeenAt = lastSeenAt
        }
    }

    /// Cached `Package.resolved` contents keyed by a Flutter native dependency hash.
    public struct FlutterResolvedCacheEntry: Codable, Equatable, Sendable {
        public let dependencyHash: String
        public let packageResolvedContents: String
        public var updatedAt: Date
        public var toolchainHash: String?

        public init(
            dependencyHash: String,
            packageResolvedContents: String,
            updatedAt: Date = Date(),
            toolchainHash: String? = nil
        ) {
            self.dependencyHash = dependencyHash
            self.packageResolvedContents = packageResolvedContents
            self.updatedAt = updatedAt
            self.toolchainHash = toolchainHash
        }
    }

    public var schemaVersion: Int
    public var projects: [String: RegisteredProject]
    public var toolchains: [String: ToolchainRecord]
    public var flutterResolvedCache: [String: FlutterResolvedCacheEntry]

    public init(
        schemaVersion: Int = StoreIndex.currentSchemaVersion,
        projects: [String: RegisteredProject] = [:],
        toolchains: [String: ToolchainRecord] = [:],
        flutterResolvedCache: [String: FlutterResolvedCacheEntry] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.projects = projects
        self.toolchains = toolchains
        self.flutterResolvedCache = flutterResolvedCache
    }
}

/// Outcome of storing an entry into ``GlobalStore``.
public struct StoreEntryResult: Equatable, Sendable {
    public let storeURL: URL
    public let alreadyCached: Bool
    public let cloneMethod: CloneMethod?

    public init(storeURL: URL, alreadyCached: Bool, cloneMethod: CloneMethod?) {
        self.storeURL = storeURL
        self.alreadyCached = alreadyCached
        self.cloneMethod = cloneMethod
    }
}

/// Manages the global content-addressable store at `~/.spmx/store` (or `SPMX_STORE_DIR`).
///
/// Layout:
/// - `checkouts/<identity>-<revision>/`
/// - `artifacts/<identity>/<targetName>-<checksum>/`
/// - `prebuilts/<swift-version-hash>/<package-identity>-<version-or-checksum>/`
/// - `index.json`
public struct GlobalStore: Sendable {
    public static let storeDirectoryEnvironmentKey = "SPMX_STORE_DIR"

    public let rootURL: URL
    public let cloner: APFSCloner
    public let lockTimeout: TimeInterval

    public var checkoutsDirectory: URL {
        rootURL.appendingPathComponent("checkouts")
    }

    public var artifactsDirectory: URL {
        rootURL.appendingPathComponent("artifacts")
    }

    public var prebuiltsDirectory: URL {
        rootURL.appendingPathComponent("prebuilts")
    }

    public var indexURL: URL {
        rootURL.appendingPathComponent("index.json")
    }

    public var locksDirectory: URL {
        rootURL.appendingPathComponent(".locks")
    }

    public init(
        rootURL: URL? = nil,
        cloner: APFSCloner = APFSCloner(),
        lockTimeout: TimeInterval = 30.0
    ) {
        self.rootURL = (rootURL ?? Self.defaultRootURL()).standardizedFileURL
        self.cloner = cloner
        self.lockTimeout = lockTimeout
    }

    /// Resolves the store root directory, honoring `SPMX_STORE_DIR` and defaulting to `~/.spmx/store`.
    public static func defaultRootURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let override = environment[storeDirectoryEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        return homeDirectory
            .appendingPathComponent(".spmx")
            .appendingPathComponent("store")
            .standardizedFileURL
    }

    /// Creates the store directory hierarchy (`checkouts/`, `artifacts/`, `prebuilts/`, `.locks/`).
    public func ensureLayout() throws {
        let fileManager = FileManager.default
        for directory in [
            rootURL,
            checkoutsDirectory,
            artifactsDirectory,
            prebuiltsDirectory,
            locksDirectory
        ] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Layout Path Helpers

    public func checkoutURL(identity: String, revision: String) throws -> URL {
        let safeIdentity = try sanitizeComponent(identity)
        let safeRevision = try sanitizeComponent(revision)
        return checkoutsDirectory.appendingPathComponent("\(safeIdentity)-\(safeRevision)")
    }

    public func artifactURL(identity: String, targetName: String, checksum: String) throws -> URL {
        let safeIdentity = try sanitizeComponent(identity)
        let safeTarget = try sanitizeComponent(targetName)
        let safeChecksum = try sanitizeComponent(checksum)
        return artifactsDirectory
            .appendingPathComponent(safeIdentity)
            .appendingPathComponent("\(safeTarget)-\(safeChecksum)")
    }

    public func prebuiltToolchainDirectory(toolchainHash: String) throws -> URL {
        let safeHash = try sanitizeComponent(toolchainHash)
        return prebuiltsDirectory.appendingPathComponent(safeHash)
    }

    public func prebuiltURL(
        toolchainHash: String,
        packageIdentity: String,
        versionOrChecksum: String
    ) throws -> URL {
        let toolchainDir = try prebuiltToolchainDirectory(toolchainHash: toolchainHash)
        let safeIdentity = try sanitizeComponent(packageIdentity)
        let safeVersionOrChecksum = try sanitizeComponent(versionOrChecksum)
        return toolchainDir.appendingPathComponent("\(safeIdentity)-\(safeVersionOrChecksum)")
    }

    // MARK: - Store Writes (Protected by FileLock + APFSCloner)

    @discardableResult
    public func storeCheckout(
        from sourceURL: URL,
        identity: String,
        revision: String,
        overwrite: Bool = false
    ) throws -> StoreEntryResult {
        let destination = try checkoutURL(identity: identity, revision: revision)
        let lockKey = "checkout:\(identity)-\(revision)"
        return try storeEntry(from: sourceURL, to: destination, lockKey: lockKey, overwrite: overwrite)
    }

    @discardableResult
    public func storeArtifact(
        from sourceURL: URL,
        identity: String,
        targetName: String,
        checksum: String,
        overwrite: Bool = false
    ) throws -> StoreEntryResult {
        let destination = try artifactURL(identity: identity, targetName: targetName, checksum: checksum)
        let lockKey = "artifact:\(identity)/\(targetName)-\(checksum)"
        return try storeEntry(from: sourceURL, to: destination, lockKey: lockKey, overwrite: overwrite)
    }

    @discardableResult
    public func storePrebuilt(
        from sourceURL: URL,
        toolchain: ToolchainFingerprint,
        packageIdentity: String,
        versionOrChecksum: String,
        overwrite: Bool = false
    ) throws -> StoreEntryResult {
        try storePrebuilt(
            from: sourceURL,
            toolchainHash: toolchain.hash,
            packageIdentity: packageIdentity,
            versionOrChecksum: versionOrChecksum,
            overwrite: overwrite
        )
    }

    @discardableResult
    public func storePrebuilt(
        from sourceURL: URL,
        toolchainHash: String,
        packageIdentity: String,
        versionOrChecksum: String,
        overwrite: Bool = false
    ) throws -> StoreEntryResult {
        let destination = try prebuiltURL(
            toolchainHash: toolchainHash,
            packageIdentity: packageIdentity,
            versionOrChecksum: versionOrChecksum
        )
        let lockKey = "prebuilt:\(toolchainHash)/\(packageIdentity)-\(versionOrChecksum)"
        return try storeEntry(from: sourceURL, to: destination, lockKey: lockKey, overwrite: overwrite)
    }

    // MARK: - Store Reads & Materialization

    public func hasCheckout(identity: String, revision: String) -> Bool {
        guard let url = try? checkoutURL(identity: identity, revision: revision) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    public func hasArtifact(identity: String, targetName: String, checksum: String) -> Bool {
        guard let url = try? artifactURL(identity: identity, targetName: targetName, checksum: checksum) else {
            return false
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    public func hasPrebuilt(
        toolchainHash: String,
        packageIdentity: String,
        versionOrChecksum: String
    ) -> Bool {
        guard let url = try? prebuiltURL(
            toolchainHash: toolchainHash,
            packageIdentity: packageIdentity,
            versionOrChecksum: versionOrChecksum
        ) else {
            return false
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    @discardableResult
    public func cloneCheckoutToWorktree(
        identity: String,
        revision: String,
        destinationURL: URL,
        overwrite: Bool = false
    ) throws -> CloneOutcome {
        let source = try checkoutURL(identity: identity, revision: revision)
        let lockKey = "checkout:\(identity)-\(revision)"
        return try cloneFromStore(at: source, to: destinationURL, lockKey: lockKey, overwrite: overwrite)
    }

    @discardableResult
    public func cloneArtifactToWorktree(
        identity: String,
        targetName: String,
        checksum: String,
        destinationURL: URL,
        overwrite: Bool = false
    ) throws -> CloneOutcome {
        let source = try artifactURL(identity: identity, targetName: targetName, checksum: checksum)
        let lockKey = "artifact:\(identity)/\(targetName)-\(checksum)"
        return try cloneFromStore(at: source, to: destinationURL, lockKey: lockKey, overwrite: overwrite)
    }

    @discardableResult
    public func clonePrebuiltToWorktree(
        toolchainHash: String,
        packageIdentity: String,
        versionOrChecksum: String,
        destinationURL: URL,
        overwrite: Bool = false
    ) throws -> CloneOutcome {
        let source = try prebuiltURL(
            toolchainHash: toolchainHash,
            packageIdentity: packageIdentity,
            versionOrChecksum: versionOrChecksum
        )
        let lockKey = "prebuilt:\(toolchainHash)/\(packageIdentity)-\(versionOrChecksum)"
        return try cloneFromStore(at: source, to: destinationURL, lockKey: lockKey, overwrite: overwrite)
    }

    // MARK: - Index Management (`index.json`)

    /// Reads the store index under the index file lock, returning an empty index if none exists yet.
    public func readIndex() throws -> StoreIndex {
        try ensureLayout()
        return try FileLock.withLock(at: indexLockURL(), timeout: lockTimeout) {
            try readIndexUnlocked()
        }
    }

    /// Atomically reads, mutates, and persists `index.json` under an exclusive `flock`.
    @discardableResult
    public func updateIndex(_ mutate: (inout StoreIndex) throws -> Void) throws -> StoreIndex {
        try ensureLayout()
        return try FileLock.withLock(at: indexLockURL(), timeout: lockTimeout) {
            var index = try readIndexUnlocked()
            try mutate(&index)
            try writeIndexUnlocked(index)
            return index
        }
    }

    /// Registers or refreshes a project/worktree entry in `index.json`.
    @discardableResult
    public func registerProject(
        at path: String,
        toolchain: ToolchainFingerprint? = nil,
        packageIdentities: [String]? = nil,
        timestamp: Date = Date()
    ) throws -> StoreIndex.RegisteredProject {
        let canonical = canonicalizeProjectPath(path)
        let updated = try updateIndex { index in
            if let toolchain {
                index.toolchains[toolchain.hash] = StoreIndex.ToolchainRecord(
                    fingerprint: toolchain,
                    lastSeenAt: timestamp
                )
            }

            if var existing = index.projects[canonical] {
                existing.lastAccessedAt = timestamp
                if let toolchain {
                    existing.toolchainHash = toolchain.hash
                }
                if let packageIdentities {
                    existing.packageIdentities = Array(Set(packageIdentities)).sorted()
                }
                index.projects[canonical] = existing
            } else {
                index.projects[canonical] = StoreIndex.RegisteredProject(
                    path: canonical,
                    registeredAt: timestamp,
                    lastAccessedAt: timestamp,
                    toolchainHash: toolchain?.hash,
                    packageIdentities: Array(Set(packageIdentities ?? [])).sorted()
                )
            }
        }
        return updated.projects[canonical]!
    }

    /// Records or refreshes a toolchain fingerprint in `index.json`.
    public func recordToolchain(
        _ fingerprint: ToolchainFingerprint,
        timestamp: Date = Date()
    ) throws {
        try updateIndex { index in
            index.toolchains[fingerprint.hash] = StoreIndex.ToolchainRecord(
                fingerprint: fingerprint,
                lastSeenAt: timestamp
            )
        }
    }

    /// Stores a Flutter native dependency hash -> `Package.resolved` contents mapping in `index.json`.
    public func cacheFlutterPackageResolved(
        _ packageResolvedContents: String,
        forDependencyHash dependencyHash: String,
        toolchainHash: String? = nil,
        timestamp: Date = Date()
    ) throws {
        try updateIndex { index in
            index.flutterResolvedCache[dependencyHash] = StoreIndex.FlutterResolvedCacheEntry(
                dependencyHash: dependencyHash,
                packageResolvedContents: packageResolvedContents,
                updatedAt: timestamp,
                toolchainHash: toolchainHash
            )
        }
    }

    /// Retrieves a cached `Package.resolved` entry for the given Flutter native dependency hash.
    public func cachedFlutterPackageResolved(
        forDependencyHash dependencyHash: String
    ) throws -> StoreIndex.FlutterResolvedCacheEntry? {
        let index = try readIndex()
        return index.flutterResolvedCache[dependencyHash]
    }

    // MARK: - Private Helpers

    private func storeEntry(
        from sourceURL: URL,
        to destinationURL: URL,
        lockKey: String,
        overwrite: Bool
    ) throws -> StoreEntryResult {
        try ensureLayout()
        return try FileLock.withLock(at: resourceLockURL(forKey: lockKey), timeout: lockTimeout) {
            if !overwrite, FileManager.default.fileExists(atPath: destinationURL.path) {
                return StoreEntryResult(
                    storeURL: destinationURL,
                    alreadyCached: true,
                    cloneMethod: nil
                )
            }
            let outcome = try cloner.clone(from: sourceURL, to: destinationURL, overwrite: overwrite)
            return StoreEntryResult(
                storeURL: outcome.destinationURL,
                alreadyCached: false,
                cloneMethod: outcome.method
            )
        }
    }

    private func cloneFromStore(
        at storeEntryURL: URL,
        to destinationURL: URL,
        lockKey: String,
        overwrite: Bool
    ) throws -> CloneOutcome {
        try ensureLayout()
        return try FileLock.withLock(at: resourceLockURL(forKey: lockKey), timeout: lockTimeout) {
            guard FileManager.default.fileExists(atPath: storeEntryURL.path) else {
                throw GlobalStoreError.entryNotFound(storeEntryURL.path)
            }
            return try cloner.clone(from: storeEntryURL, to: destinationURL, overwrite: overwrite)
        }
    }

    private func indexLockURL() -> URL {
        locksDirectory.appendingPathComponent("index.lock")
    }

    private func resourceLockURL(forKey key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return locksDirectory.appendingPathComponent("\(hex).lock")
    }

    private func readIndexUnlocked() throws -> StoreIndex {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return StoreIndex()
        }

        let data: Data
        do {
            data = try Data(contentsOf: indexURL)
        } catch {
            throw GlobalStoreError.corruptedIndex(path: indexURL.path, message: error.localizedDescription)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(StoreIndex.self, from: data)
        } catch {
            throw GlobalStoreError.corruptedIndex(path: indexURL.path, message: error.localizedDescription)
        }
    }

    private func writeIndexUnlocked(_ index: StoreIndex) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(index)

        let fileManager = FileManager.default
        let tempURL = rootURL.appendingPathComponent(".index.json.spmx-tmp-\(UUID().uuidString)")
        defer {
            if fileManager.fileExists(atPath: tempURL.path) {
                try? fileManager.removeItem(at: tempURL)
            }
        }

        try data.write(to: tempURL, options: [])
        if fileManager.fileExists(atPath: indexURL.path) {
            _ = try fileManager.replaceItemAt(indexURL, withItemAt: tempURL)
        } else {
            try fileManager.moveItem(at: tempURL, to: indexURL)
        }
    }

    private func sanitizeComponent(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", trimmed != ".." else {
            throw GlobalStoreError.invalidPathComponent(raw)
        }
        return trimmed
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
    }

    private func canonicalizeProjectPath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        var standardized = URL(fileURLWithPath: expanded).standardizedFileURL.path
        while standardized.count > 1 && standardized.hasSuffix("/") {
            standardized.removeLast()
        }
        return standardized
    }
}

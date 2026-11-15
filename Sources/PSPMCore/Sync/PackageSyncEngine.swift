import CryptoKit
import Foundation

/// Synchronizes SwiftPM `SourcePackages` (or `.build`) directories with ``GlobalStore``
/// via `hydrate` and `harvest` using APFS Copy-on-Write (`clonefile`).
public struct PackageSyncEngine: Sendable {
    public typealias ToolchainProvider = @Sendable () throws -> ToolchainFingerprint

    private struct SendableFileManager: @unchecked Sendable {
        let value: FileManager
    }

    private static let templateRootPlaceholder = "/__PSPM_SOURCE_PACKAGES__"

    public let store: GlobalStore
    private let toolchainProvider: ToolchainProvider
    private let fileManagerBox: SendableFileManager

    private var fileManager: FileManager {
        fileManagerBox.value
    }

    public init(
        store: GlobalStore = GlobalStore(),
        toolchainProvider: @escaping ToolchainProvider = { try ToolchainFingerprint.current() },
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.toolchainProvider = toolchainProvider
        self.fileManagerBox = SendableFileManager(value: fileManager)
    }

    public init(
        store: GlobalStore = GlobalStore(),
        toolchain: ToolchainFingerprint,
        fileManager: FileManager = .default
    ) {
        self.init(
            store: store,
            toolchainProvider: { toolchain },
            fileManager: fileManager
        )
    }

    // MARK: - Path Resolution

    /// Resolves the target `SourcePackages` (Xcode/Flutter) or `.build` (pure SwiftPM) directory URL.
    public func resolveSourcePackagesURL(
        for detectedProject: DetectedProject,
        overridePath: String? = nil
    ) throws -> URL {
        if let overridePath,
           !overridePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let canonical = DerivedDataPathCalculator.canonicalizePath(
                overridePath,
                currentDirectory: fileManager.currentDirectoryPath
            )
            return URL(fileURLWithPath: canonical).standardizedFileURL
        }

        switch detectedProject.type {
        case .swiftPackage:
            return URL(fileURLWithPath: detectedProject.rootPath)
                .appendingPathComponent(".build")
                .standardizedFileURL

        case .xcode, .flutter:
            guard let containerPath = detectedProject.containerPath else {
                throw SyncError.missingContainerPath(projectRoot: detectedProject.rootPath)
            }
            return DerivedDataPathCalculator.derivedDataURL(
                forContainerPath: containerPath,
                currentDirectory: fileManager.currentDirectoryPath,
                fileManager: fileManager
            )
            .appendingPathComponent("SourcePackages")
            .standardizedFileURL
        }
    }

    // MARK: - Hydrate

    /// Materializes cached `checkouts`, `artifacts`, toolchain-matched `prebuilts`, and a
    /// path-rewritten `workspace-state.json` from ``GlobalStore`` into the project's `SourcePackages` (or `.build`).
    public func hydrate(
        project: DetectedProject,
        options: HydrateOptions = HydrateOptions()
    ) throws -> HydrateResult {
        try store.ensureLayout()

        guard let packageResolvedPath = project.packageResolvedPath ?? project.allPackageResolvedPaths.first else {
            throw SyncError.packageResolvedNotFound(projectRoot: project.rootPath)
        }

        let resolved = try PackageResolvedParser.parse(fileAt: packageResolvedPath, fileManager: fileManager)
        let sourcePackagesURL = try resolveSourcePackagesURL(
            for: project,
            overridePath: options.sourcePackagesOverride
        )
        let toolchain = resolveToolchain(verboseLogger: options.verboseLogger)

        options.verboseLogger?("Hydrating '\(sourcePackagesURL.path)' from store '\(store.rootURL.path)'")

        try ensureDirectory(sourcePackagesURL)
        let checkoutsDir = sourcePackagesURL.appendingPathComponent("checkouts")
        try ensureDirectory(checkoutsDir)

        let pinSetHash = Self.computePinSetHash(pins: resolved.pins)
        let workspaceTemplate = try loadWorkspaceTemplate(
            pinSetHash: pinSetHash,
            toolchainHash: toolchain?.hash
        )

        var packageTemplatesByIdentity: [String: PackageTemplateRecord] = [:]
        for pin in resolved.pins {
            let identity = pin.identity.lowercased()
            if let revision = pin.revision, !revision.isEmpty,
               let record = try loadPackageTemplate(identity: identity, revision: revision) {
                packageTemplatesByIdentity[identity] = record
            }
        }

        // 1. Hydrate checkouts
        var hydratedCheckouts: [HydratedCheckout] = []
        var skippedCheckouts: [SkippedCheckout] = []

        for pin in resolved.pins {
            let identity = pin.identity.lowercased()
            guard let revision = pin.revision, !revision.isEmpty else {
                skippedCheckouts.append(SkippedCheckout(
                    identity: identity,
                    revision: nil,
                    destinationURL: nil,
                    reason: .missingRevision
                ))
                continue
            }

            guard store.hasCheckout(identity: identity, revision: revision) else {
                options.verboseLogger?("Checkout miss in store: \(identity)@\(revision)")
                skippedCheckouts.append(SkippedCheckout(
                    identity: identity,
                    revision: revision,
                    destinationURL: nil,
                    reason: .notInStore
                ))
                continue
            }

            let folderName = packageTemplatesByIdentity[identity]?.subpath ?? identity
            let destinationURL = checkoutsDir.appendingPathComponent(folderName)

            if itemExists(at: destinationURL) {
                let isEmpty = isDirectoryEmpty(at: destinationURL)
                if !isEmpty && !options.force {
                    let reason: SkippedCheckoutReason = isGitWorkingTreeDirty(at: destinationURL)
                        ? .locallyModified
                        : .alreadyExists
                    options.verboseLogger?("Preserving existing checkout '\(folderName)' (\(reason.rawValue))")
                    skippedCheckouts.append(SkippedCheckout(
                        identity: identity,
                        revision: revision,
                        destinationURL: destinationURL,
                        reason: reason
                    ))
                    continue
                }
            }

            let outcome = try store.cloneCheckoutToWorktree(
                identity: identity,
                revision: revision,
                destinationURL: destinationURL,
                overwrite: true
            )
            options.verboseLogger?("Hydrated checkout \(identity)@\(revision) (\(outcome.method.rawValue))")
            hydratedCheckouts.append(HydratedCheckout(
                identity: identity,
                revision: revision,
                destinationURL: outcome.destinationURL,
                cloneMethod: outcome.method
            ))
        }

        // 2. Hydrate artifacts
        var hydratedArtifacts: [HydratedArtifact] = []
        var availableArtifactEntries: [ArtifactTemplateEntry] = []

        if options.includeArtifacts {
            let candidateArtifacts = collectArtifactTemplates(
                pins: resolved.pins,
                workspaceTemplate: workspaceTemplate,
                packageTemplates: packageTemplatesByIdentity
            )

            for artifact in candidateArtifacts {
                let destinationURL = sourcePackagesURL
                    .appendingPathComponent("artifacts")
                    .appendingPathComponent(artifact.relativeSubpath)
                    .standardizedFileURL

                let hasInStore = store.hasArtifact(
                    identity: artifact.identity,
                    targetName: artifact.targetName,
                    checksum: artifact.checksum
                )

                if itemExists(at: destinationURL) && !isDirectoryEmpty(at: destinationURL) && !options.force {
                    availableArtifactEntries.append(artifact)
                    continue
                }

                guard hasInStore else {
                    options.verboseLogger?("Artifact miss in store: \(artifact.identity)/\(artifact.targetName) (\(artifact.checksum))")
                    continue
                }

                let outcome = try store.cloneArtifactToWorktree(
                    identity: artifact.identity,
                    targetName: artifact.targetName,
                    checksum: artifact.checksum,
                    destinationURL: destinationURL,
                    overwrite: true
                )
                options.verboseLogger?("Hydrated artifact \(artifact.identity)/\(artifact.targetName) (\(outcome.method.rawValue))")
                hydratedArtifacts.append(HydratedArtifact(
                    identity: artifact.identity,
                    targetName: artifact.targetName,
                    checksum: artifact.checksum,
                    destinationURL: outcome.destinationURL,
                    cloneMethod: outcome.method
                ))
                availableArtifactEntries.append(artifact)
            }
        }

        // 3. Hydrate toolchain-matched prebuilts
        var hydratedPrebuilts: [HydratedPrebuilt] = []
        var availablePrebuiltEntries: [PrebuiltTemplateEntry] = []

        if options.includePrebuilts, let toolchain {
            let candidatePrebuilts = try collectPrebuiltTemplates(
                pins: resolved.pins,
                toolchainHash: toolchain.hash,
                workspaceTemplate: workspaceTemplate
            )

            for prebuilt in candidatePrebuilts {
                let destinationURL = sourcePackagesURL
                    .appendingPathComponent("prebuilts")
                    .appendingPathComponent(prebuilt.relativeSubpath)
                    .standardizedFileURL

                let hasInStore = store.hasPrebuilt(
                    toolchainHash: toolchain.hash,
                    packageIdentity: prebuilt.identity,
                    versionOrChecksum: prebuilt.versionOrChecksum
                )

                if itemExists(at: destinationURL) && !isDirectoryEmpty(at: destinationURL) && !options.force {
                    availablePrebuiltEntries.append(prebuilt)
                    continue
                }

                guard hasInStore else {
                    options.verboseLogger?("Prebuilt miss in store: \(prebuilt.identity)@\(prebuilt.versionOrChecksum) [\(toolchain.hash)]")
                    continue
                }

                let outcome = try store.clonePrebuiltToWorktree(
                    toolchainHash: toolchain.hash,
                    packageIdentity: prebuilt.identity,
                    versionOrChecksum: prebuilt.versionOrChecksum,
                    destinationURL: destinationURL,
                    overwrite: true
                )
                options.verboseLogger?("Hydrated prebuilt \(prebuilt.identity)@\(prebuilt.versionOrChecksum) (\(outcome.method.rawValue))")
                hydratedPrebuilts.append(HydratedPrebuilt(
                    identity: prebuilt.identity,
                    versionOrChecksum: prebuilt.versionOrChecksum,
                    toolchainHash: toolchain.hash,
                    destinationURL: outcome.destinationURL,
                    cloneMethod: outcome.method
                ))
                availablePrebuiltEntries.append(prebuilt)
            }
        }

        // 4. Generate or update workspace-state.json
        let workspaceStateFileURL = sourcePackagesURL.appendingPathComponent("workspace-state.json")
        var didUpdateWorkspaceState = false

        if options.rewriteWorkspaceState {
            didUpdateWorkspaceState = try materializeWorkspaceState(
                at: workspaceStateFileURL,
                sourcePackagesURL: sourcePackagesURL,
                pins: resolved.pins,
                toolchainHash: toolchain?.hash,
                workspaceTemplate: workspaceTemplate,
                packageTemplates: packageTemplatesByIdentity,
                availableArtifacts: availableArtifactEntries,
                availablePrebuilts: availablePrebuiltEntries
            )
        }

        // 5. Register project in store index
        if options.registerProject {
            let identities = resolved.pins.map { $0.identity.lowercased() }
            try store.registerProject(
                at: project.rootPath,
                toolchain: toolchain,
                packageIdentities: identities
            )
        }

        return HydrateResult(
            project: project,
            sourcePackagesURL: sourcePackagesURL,
            packageResolvedPath: packageResolvedPath,
            toolchainHash: toolchain?.hash,
            hydratedCheckouts: hydratedCheckouts,
            skippedCheckouts: skippedCheckouts,
            hydratedArtifacts: hydratedArtifacts,
            hydratedPrebuilts: hydratedPrebuilts,
            workspaceStateURL: fileManager.fileExists(atPath: workspaceStateFileURL.path) ? workspaceStateFileURL : nil,
            didUpdateWorkspaceState: didUpdateWorkspaceState
        )
    }

    // MARK: - Harvest

    /// Inspects `<SourcePackages>` (or `.build`) and stores valid `checkouts`, `artifacts`,
    /// toolchain-keyed `prebuilts`, and sanitized workspace-state templates into ``GlobalStore``.
    public func harvest(
        project: DetectedProject,
        options: HarvestOptions = HarvestOptions()
    ) throws -> HarvestResult {
        try store.ensureLayout()

        let sourcePackagesURL = try resolveSourcePackagesURL(
            for: project,
            overridePath: options.sourcePackagesOverride
        )
        let toolchain = resolveToolchain(verboseLogger: options.verboseLogger)

        options.verboseLogger?("Harvesting '\(sourcePackagesURL.path)' into store '\(store.rootURL.path)'")

        let resolvedPins: [PackagePin]
        if let resolvedPath = project.packageResolvedPath ?? project.allPackageResolvedPaths.first,
           fileManager.fileExists(atPath: resolvedPath) {
            resolvedPins = (try? PackageResolvedParser.parse(fileAt: resolvedPath, fileManager: fileManager).pins) ?? []
        } else {
            resolvedPins = []
        }

        let workspaceStateFileURL = sourcePackagesURL.appendingPathComponent("workspace-state.json")
        let workspaceStateRawData = try? Data(contentsOf: workspaceStateFileURL)
        let workspaceState = try workspaceStateRawData.map { data -> WorkspaceState in
            do {
                return try WorkspaceStateParser.parse(data: data)
            } catch {
                throw SyncError.invalidWorkspaceState(
                    path: workspaceStateFileURL.path,
                    message: error.localizedDescription
                )
            }
        }

        let rawWorkspaceRoot: [String: Any]?
        if let workspaceStateRawData,
           let parsed = try? JSONSerialization.jsonObject(with: workspaceStateRawData, options: []) as? [String: Any] {
            rawWorkspaceRoot = parsed
        } else {
            rawWorkspaceRoot = nil
        }

        // Build lookup tables for revisions and dependency subpaths.
        var revisionByIdentity: [String: String] = [:]
        var identityBySubpath: [String: String] = [:]
        for pin in resolvedPins {
            let id = pin.identity.lowercased()
            if let rev = pin.revision, !rev.isEmpty {
                revisionByIdentity[id] = rev
            }
            identityBySubpath[id] = id
        }
        if let workspaceState {
            for dep in workspaceState.dependencies {
                let id = dep.packageRef.identity.lowercased()
                if let rev = dep.state.checkoutState?.revision, !rev.isEmpty {
                    revisionByIdentity[id] = rev
                }
                if let subpath = dep.subpath, !subpath.isEmpty {
                    identityBySubpath[subpath.lowercased()] = id
                }
                identityBySubpath[id] = id
            }
        }

        var harvestedCheckouts: [HarvestedCheckout] = []
        var harvestedArtifacts: [HarvestedArtifact] = []
        var harvestedPrebuilts: [HarvestedPrebuilt] = []
        var skippedItems: [SkippedHarvestItem] = []

        // 1. Harvest checkouts
        let checkoutsDir = sourcePackagesURL.appendingPathComponent("checkouts")
        var validCheckoutIdentities: Set<String> = []
        if isDirectory(at: checkoutsDir) {
            let entries = (try? fileManager.contentsOfDirectory(
                at: checkoutsDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for entryURL in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = entryURL.lastPathComponent
                if name.hasSuffix(".partial") {
                    skippedItems.append(SkippedHarvestItem(
                        kind: "checkout",
                        identifier: name,
                        path: entryURL.path,
                        reason: "partial marker suffix"
                    ))
                    continue
                }

                guard isDirectory(at: entryURL) else { continue }

                if containsPartialMarker(at: entryURL) {
                    options.verboseLogger?("Ignoring checkout '\(name)': contains .partial marker")
                    skippedItems.append(SkippedHarvestItem(
                        kind: "checkout",
                        identifier: name,
                        path: entryURL.path,
                        reason: "contains .partial marker"
                    ))
                    continue
                }

                if isDirectoryEmpty(at: entryURL) {
                    skippedItems.append(SkippedHarvestItem(
                        kind: "checkout",
                        identifier: name,
                        path: entryURL.path,
                        reason: "empty checkout directory"
                    ))
                    continue
                }

                let identity = identityBySubpath[name.lowercased()] ?? name.lowercased()
                guard let revision = revisionByIdentity[identity], !revision.isEmpty else {
                    options.verboseLogger?("Ignoring checkout '\(name)': missing revision metadata")
                    skippedItems.append(SkippedHarvestItem(
                        kind: "checkout",
                        identifier: identity,
                        path: entryURL.path,
                        reason: "missing revision"
                    ))
                    continue
                }

                let result = try store.storeCheckout(
                    from: entryURL,
                    identity: identity,
                    revision: revision,
                    overwrite: options.overwriteStore
                )
                validCheckoutIdentities.insert(identity)
                options.verboseLogger?(
                    result.alreadyCached
                        ? "Checkout already cached: \(identity)@\(revision)"
                        : "Harvested checkout: \(identity)@\(revision)"
                )
                harvestedCheckouts.append(HarvestedCheckout(
                    identity: identity,
                    revision: revision,
                    sourceURL: entryURL,
                    storeURL: result.storeURL,
                    alreadyCached: result.alreadyCached,
                    cloneMethod: result.cloneMethod
                ))
            }
        }

        // 2. Harvest artifacts
        var validArtifactTemplatesByIdentity: [String: [ArtifactTemplateEntry]] = [:]
        var validArtifactChecksums: Set<String> = []

        if let workspaceState {
            let rawArtifacts = (rawWorkspaceRoot?["object"] as? [String: Any])?["artifacts"] as? [[String: Any]] ?? []

            for (index, artifact) in workspaceState.artifacts.enumerated() {
                let identity = artifact.packageRef.identity.lowercased()
                let identifier = "\(identity)/\(artifact.targetName)"

                guard let checksum = artifact.checksum, !checksum.isEmpty else {
                    options.verboseLogger?("Ignoring artifact '\(identifier)': missing checksum")
                    skippedItems.append(SkippedHarvestItem(
                        kind: "artifact",
                        identifier: identifier,
                        path: artifact.path,
                        reason: "missing checksum"
                    ))
                    continue
                }

                if let resolvedSource = resolveArtifactSource(
                    artifact: artifact,
                    sourcePackagesURL: sourcePackagesURL
                ) {
                    if containsPartialMarker(at: resolvedSource.sourceURL) || isEmptyItem(at: resolvedSource.sourceURL) {
                        options.verboseLogger?("Ignoring artifact '\(identifier)': incomplete or .partial marker")
                        skippedItems.append(SkippedHarvestItem(
                            kind: "artifact",
                            identifier: identifier,
                            path: resolvedSource.sourceURL.path,
                            reason: "incomplete or contains .partial marker"
                        ))
                        continue
                    }

                    let storeResult = try store.storeArtifact(
                        from: resolvedSource.sourceURL,
                        identity: identity,
                        targetName: artifact.targetName,
                        checksum: checksum,
                        overwrite: options.overwriteStore
                    )

                    harvestedArtifacts.append(HarvestedArtifact(
                        identity: identity,
                        targetName: artifact.targetName,
                        checksum: checksum,
                        sourceURL: resolvedSource.sourceURL,
                        storeURL: storeResult.storeURL,
                        alreadyCached: storeResult.alreadyCached,
                        cloneMethod: storeResult.cloneMethod
                    ))
                    validArtifactChecksums.insert(artifactKey(identity: identity, targetName: artifact.targetName, checksum: checksum))

                    let rawArtifactDict = index < rawArtifacts.count ? rawArtifacts[index] : nil
                    let sanitizedRawArtifactData = rawArtifactDict.flatMap {
                        sanitizeRawEntry(
                            $0,
                            sectionKey: "artifacts",
                            sourcePackagesURL: sourcePackagesURL
                        )
                    }
                    let entry = ArtifactTemplateEntry(
                        identity: identity,
                        targetName: artifact.targetName,
                        checksum: checksum,
                        relativeSubpath: resolvedSource.relativeSubpath,
                        isDirectoryBundle: isDirectory(at: resolvedSource.sourceURL),
                        rawArtifactJSONBase64: sanitizedRawArtifactData?.base64EncodedString()
                    )
                    validArtifactTemplatesByIdentity[identity, default: []].append(entry)
                } else {
                    skippedItems.append(SkippedHarvestItem(
                        kind: "artifact",
                        identifier: identifier,
                        path: artifact.path,
                        reason: "artifact path missing on disk"
                    ))
                }
            }
        }

        // 3. Harvest toolchain-keyed prebuilts
        var validPrebuiltEntries: [PrebuiltTemplateEntry] = []
        var validPrebuiltKeys: Set<String> = []

        if let workspaceState, let toolchain {
            let rawPrebuilts = (rawWorkspaceRoot?["object"] as? [String: Any])?["prebuilts"] as? [[String: Any]] ?? []

            for (index, prebuilt) in workspaceState.prebuilts.enumerated() {
                let identity = prebuilt.identity.lowercased()
                let hasRevision = prebuilt.checkoutState?.revision?.isEmpty == false
                let hasChecksum = prebuilt.checksum?.isEmpty == false
                guard hasRevision || hasChecksum,
                      let versionOrChecksum = prebuilt.checksum ?? prebuilt.version,
                      !versionOrChecksum.isEmpty else {
                    options.verboseLogger?("Ignoring prebuilt '\(identity)': missing revision/checksum")
                    skippedItems.append(SkippedHarvestItem(
                        kind: "prebuilt",
                        identifier: identity,
                        path: prebuilt.path ?? "",
                        reason: "missing revision or checksum"
                    ))
                    continue
                }

                guard let resolvedPrebuilt = resolvePrebuiltSource(
                    prebuilt: prebuilt,
                    sourcePackagesURL: sourcePackagesURL
                ) else {
                    skippedItems.append(SkippedHarvestItem(
                        kind: "prebuilt",
                        identifier: identity,
                        path: prebuilt.path ?? "",
                        reason: "prebuilt path missing on disk"
                    ))
                    continue
                }

                if containsPartialMarker(at: resolvedPrebuilt.sourceURL) || isEmptyItem(at: resolvedPrebuilt.sourceURL) {
                    options.verboseLogger?("Ignoring prebuilt '\(identity)': incomplete or .partial marker")
                    skippedItems.append(SkippedHarvestItem(
                        kind: "prebuilt",
                        identifier: identity,
                        path: resolvedPrebuilt.sourceURL.path,
                        reason: "incomplete or contains .partial marker"
                    ))
                    continue
                }

                let storeResult = try store.storePrebuilt(
                    from: resolvedPrebuilt.sourceURL,
                    toolchain: toolchain,
                    packageIdentity: identity,
                    versionOrChecksum: versionOrChecksum,
                    overwrite: options.overwriteStore
                )

                harvestedPrebuilts.append(HarvestedPrebuilt(
                    identity: identity,
                    versionOrChecksum: versionOrChecksum,
                    toolchainHash: toolchain.hash,
                    sourceURL: resolvedPrebuilt.sourceURL,
                    storeURL: storeResult.storeURL,
                    alreadyCached: storeResult.alreadyCached,
                    cloneMethod: storeResult.cloneMethod
                ))
                validPrebuiltKeys.insert(prebuiltKey(identity: identity, versionOrChecksum: versionOrChecksum))

                let rawPrebuiltDict = index < rawPrebuilts.count ? rawPrebuilts[index] : nil
                let sanitizedRawPrebuiltData = rawPrebuiltDict.flatMap {
                    sanitizeRawEntry(
                        $0,
                        sectionKey: "prebuilts",
                        sourcePackagesURL: sourcePackagesURL
                    )
                }
                let entry = PrebuiltTemplateEntry(
                    identity: identity,
                    revision: prebuilt.checkoutState?.revision ?? revisionByIdentity[identity],
                    version: prebuilt.version ?? prebuilt.checkoutState?.version,
                    checksum: prebuilt.checksum,
                    versionOrChecksum: versionOrChecksum,
                    relativeSubpath: resolvedPrebuilt.relativeSubpath,
                    rawPrebuiltJSONBase64: sanitizedRawPrebuiltData?.base64EncodedString(),
                    updatedAt: Date()
                )
                validPrebuiltEntries.append(entry)
                try savePrebuiltTemplate(entry, toolchainHash: toolchain.hash)
            }
        }

        // 4. Save per-package templates and sanitized workspace-state template
        var savedTemplateURL: URL?

        if let workspaceState, let rawWorkspaceRoot {
            let rawDeps = (rawWorkspaceRoot["object"] as? [String: Any])?["dependencies"] as? [[String: Any]] ?? []
            for (index, dep) in workspaceState.dependencies.enumerated() {
                let identity = dep.packageRef.identity.lowercased()
                guard let revision = dep.state.checkoutState?.revision ?? revisionByIdentity[identity],
                      !revision.isEmpty else {
                    continue
                }
                let rawDepData = index < rawDeps.count
                    ? try? JSONSerialization.data(withJSONObject: rawDeps[index], options: [.sortedKeys, .withoutEscapingSlashes])
                    : nil
                let record = PackageTemplateRecord(
                    identity: identity,
                    revision: revision,
                    subpath: dep.subpath,
                    rawDependencyJSONBase64: rawDepData?.base64EncodedString(),
                    artifacts: validArtifactTemplatesByIdentity[identity] ?? [],
                    updatedAt: Date()
                )
                try savePackageTemplate(record)
            }

            // Build sanitized workspace-state JSON data
            if let sanitizedWorkspaceData = buildSanitizedWorkspaceStateData(
                rawRoot: rawWorkspaceRoot,
                workspaceState: workspaceState,
                sourcePackagesURL: sourcePackagesURL,
                revisionByIdentity: revisionByIdentity,
                validCheckoutIdentities: validCheckoutIdentities,
                validArtifactKeys: validArtifactChecksums,
                validPrebuiltKeys: validPrebuiltKeys
            ) {
                let allArtifactTemplates = validArtifactTemplatesByIdentity.values.flatMap { $0 }
                let pinsForHash: [PackagePin] = resolvedPins.isEmpty
                    ? workspaceState.dependencies.map { dep in
                        PackagePin(
                            identity: dep.packageRef.identity.lowercased(),
                            kind: PinKind(rawValue: dep.packageRef.kind),
                            location: dep.packageRef.location,
                            revision: dep.state.checkoutState?.revision,
                            version: dep.state.checkoutState?.version,
                            branch: dep.state.checkoutState?.branch,
                            packageName: dep.packageRef.name
                        )
                    }
                    : resolvedPins

                let pinSetHash = Self.computePinSetHash(pins: pinsForHash)
                let templateRecord = WorkspaceTemplateRecord(
                    schemaVersion: 1,
                    pinSetHash: pinSetHash,
                    toolchainHash: toolchain?.hash,
                    workspaceStateJSONBase64: sanitizedWorkspaceData.base64EncodedString(),
                    artifacts: allArtifactTemplates,
                    prebuilts: validPrebuiltEntries,
                    updatedAt: Date()
                )
                savedTemplateURL = try saveWorkspaceTemplate(templateRecord)
            }
        } else if !resolvedPins.isEmpty {
            // Save package templates for any harvested checkouts even if workspace-state.json wasn't present
            for checkout in harvestedCheckouts {
                let record = PackageTemplateRecord(
                    identity: checkout.identity,
                    revision: checkout.revision,
                    subpath: checkout.sourceURL.lastPathComponent,
                    rawDependencyJSONBase64: nil,
                    artifacts: [],
                    updatedAt: Date()
                )
                try savePackageTemplate(record)
            }
        }

        // 5. Register project in store index
        if options.registerProject {
            var identities = Set(harvestedCheckouts.map(\.identity))
            identities.formUnion(harvestedArtifacts.map(\.identity))
            identities.formUnion(harvestedPrebuilts.map(\.identity))
            identities.formUnion(resolvedPins.map { $0.identity.lowercased() })
            try store.registerProject(
                at: project.rootPath,
                toolchain: toolchain,
                packageIdentities: Array(identities)
            )
        }

        return HarvestResult(
            project: project,
            sourcePackagesURL: sourcePackagesURL,
            toolchainHash: toolchain?.hash,
            harvestedCheckouts: harvestedCheckouts,
            harvestedArtifacts: harvestedArtifacts,
            harvestedPrebuilts: harvestedPrebuilts,
            skippedItems: skippedItems,
            savedTemplateURL: savedTemplateURL
        )
    }

    // MARK: - Workspace State Materialization & Sanitization

    private func materializeWorkspaceState(
        at destinationURL: URL,
        sourcePackagesURL: URL,
        pins: [PackagePin],
        toolchainHash: String?,
        workspaceTemplate: WorkspaceTemplateRecord?,
        packageTemplates: [String: PackageTemplateRecord],
        availableArtifacts: [ArtifactTemplateEntry],
        availablePrebuilts: [PrebuiltTemplateEntry]
    ) throws -> Bool {
        let existingData = try? Data(contentsOf: destinationURL)

        if let existingData,
           var root = try? JSONSerialization.jsonObject(with: existingData, options: []) as? [String: Any],
           var object = root["object"] as? [String: Any] {
            mergeEntriesIntoWorkspaceObject(
                &object,
                pins: pins,
                packageTemplates: packageTemplates,
                availableArtifacts: availableArtifacts,
                availablePrebuilts: availablePrebuilts
            )
            root["object"] = object
            let mergedRaw = try JSONSerialization.data(withJSONObject: root, options: [])
            let rewritten = try rewriteWorkspaceStateToTarget(
                data: mergedRaw,
                targetSourcePackagesURL: sourcePackagesURL
            )
            try rewritten.write(to: destinationURL, options: .atomic)
            return true
        }

        if let workspaceTemplate,
           let templateData = Data(base64Encoded: workspaceTemplate.workspaceStateJSONBase64),
           var root = try? JSONSerialization.jsonObject(with: templateData, options: []) as? [String: Any],
           var object = root["object"] as? [String: Any] {
            let allowedArtifacts = Set(availableArtifacts.map {
                artifactKey(identity: $0.identity, targetName: $0.targetName, checksum: $0.checksum)
            })
            if let rawArtifacts = object["artifacts"] as? [[String: Any]] {
                object["artifacts"] = rawArtifacts.filter { raw in
                    guard let ref = raw["packageRef"] as? [String: Any],
                          let identity = (ref["identity"] as? String)?.lowercased(),
                          let targetName = raw["targetName"] as? String else {
                        return false
                    }
                    let checksum = extractChecksum(fromRawArtifact: raw) ?? ""
                    return allowedArtifacts.contains(artifactKey(identity: identity, targetName: targetName, checksum: checksum))
                }
            }

            if let toolchainHash, workspaceTemplate.toolchainHash == toolchainHash {
                let allowedPrebuilts = Set(availablePrebuilts.map {
                    prebuiltKey(identity: $0.identity, versionOrChecksum: $0.versionOrChecksum)
                })
                if let rawPrebuilts = object["prebuilts"] as? [[String: Any]] {
                    object["prebuilts"] = rawPrebuilts.filter { raw in
                        guard let identity = extractPrebuiltIdentity(fromRaw: raw),
                              let voc = (raw["checksum"] as? String) ?? (raw["version"] as? String) else {
                            return false
                        }
                        return allowedPrebuilts.contains(prebuiltKey(identity: identity, versionOrChecksum: voc))
                    }
                }
            } else {
                // Toolchain differs or no active toolchain: replace prebuilts with toolchain-matched entries only.
                object["prebuilts"] = availablePrebuilts.compactMap { entry -> [String: Any]? in
                    guard let base64 = entry.rawPrebuiltJSONBase64,
                          let data = Data(base64Encoded: base64),
                          let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                        return nil
                    }
                    return dict
                }
            }

            root["object"] = object
            let rawData = try JSONSerialization.data(withJSONObject: root, options: [])
            let rewritten = try rewriteWorkspaceStateToTarget(
                data: rawData,
                targetSourcePackagesURL: sourcePackagesURL
            )
            try rewritten.write(to: destinationURL, options: .atomic)
            return true
        }

        // Assemble from per-package and per-prebuilt templates if at least one template or hydrated entry exists.
        let hasAnyTemplate = !packageTemplates.isEmpty || !availableArtifacts.isEmpty || !availablePrebuilts.isEmpty
        guard hasAnyTemplate else {
            return false
        }

        var object: [String: Any] = [
            "artifacts": [],
            "dependencies": [],
            "prebuilts": []
        ]
        mergeEntriesIntoWorkspaceObject(
            &object,
            pins: pins,
            packageTemplates: packageTemplates,
            availableArtifacts: availableArtifacts,
            availablePrebuilts: availablePrebuilts
        )

        let root: [String: Any] = [
            "object": object,
            "version": 7
        ]
        let rawData = try JSONSerialization.data(withJSONObject: root, options: [])
        let rewritten = try rewriteWorkspaceStateToTarget(
            data: rawData,
            targetSourcePackagesURL: sourcePackagesURL
        )
        try rewritten.write(to: destinationURL, options: .atomic)
        return true
    }

    private func mergeEntriesIntoWorkspaceObject(
        _ object: inout [String: Any],
        pins: [PackagePin],
        packageTemplates: [String: PackageTemplateRecord],
        availableArtifacts: [ArtifactTemplateEntry],
        availablePrebuilts: [PrebuiltTemplateEntry]
    ) {
        // Dependencies
        var deps = object["dependencies"] as? [[String: Any]] ?? []
        var existingDepIdentities = Set(deps.compactMap {
            (($0["packageRef"] as? [String: Any])?["identity"] as? String)?.lowercased()
        })
        for pin in pins {
            let identity = pin.identity.lowercased()
            guard !existingDepIdentities.contains(identity) else { continue }
            if let template = packageTemplates[identity],
               let base64 = template.rawDependencyJSONBase64,
               let data = Data(base64Encoded: base64),
               let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                deps.append(dict)
                existingDepIdentities.insert(identity)
            } else if store.hasCheckout(identity: identity, revision: pin.revision ?? "") {
                deps.append(synthesizeDependencyDict(for: pin))
                existingDepIdentities.insert(identity)
            }
        }
        object["dependencies"] = deps

        // Artifacts
        var artifacts = object["artifacts"] as? [[String: Any]] ?? []
        var existingArtifactKeys = Set(artifacts.compactMap { raw -> String? in
            guard let ref = raw["packageRef"] as? [String: Any],
                  let id = (ref["identity"] as? String)?.lowercased(),
                  let target = raw["targetName"] as? String else {
                return nil
            }
            let checksum = extractChecksum(fromRawArtifact: raw) ?? ""
            return artifactKey(identity: id, targetName: target, checksum: checksum)
        })
        for entry in availableArtifacts {
            let key = artifactKey(identity: entry.identity, targetName: entry.targetName, checksum: entry.checksum)
            guard !existingArtifactKeys.contains(key),
                  let base64 = entry.rawArtifactJSONBase64,
                  let data = Data(base64Encoded: base64),
                  let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                continue
            }
            artifacts.append(dict)
            existingArtifactKeys.insert(key)
        }
        object["artifacts"] = artifacts

        // Prebuilts
        var prebuilts = object["prebuilts"] as? [[String: Any]] ?? []
        var existingPrebuiltKeys = Set(prebuilts.compactMap { raw -> String? in
            guard let id = extractPrebuiltIdentity(fromRaw: raw),
                  let voc = (raw["checksum"] as? String) ?? (raw["version"] as? String) else {
                return nil
            }
            return prebuiltKey(identity: id, versionOrChecksum: voc)
        })
        for entry in availablePrebuilts {
            let key = prebuiltKey(identity: entry.identity, versionOrChecksum: entry.versionOrChecksum)
            guard !existingPrebuiltKeys.contains(key),
                  let base64 = entry.rawPrebuiltJSONBase64,
                  let data = Data(base64Encoded: base64),
                  let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                continue
            }
            prebuilts.append(dict)
            existingPrebuiltKeys.insert(key)
        }
        object["prebuilts"] = prebuilts
    }

    private func rewriteWorkspaceStateToTarget(
        data: Data,
        targetSourcePackagesURL: URL
    ) throws -> Data {
        let targetPath = targetSourcePackagesURL.standardizedFileURL.path
        let firstPass = try WorkspaceStateParser.rewritingPaths(
            in: data,
            toNewSourcePackagesPath: targetPath,
            replacingOldSourcePackagesPath: Self.templateRootPlaceholder
        )
        return try WorkspaceStateParser.rewritingPaths(
            in: firstPass,
            toNewSourcePackagesPath: targetPath,
            replacingOldSourcePackagesPath: nil
        )
    }

    private func sanitizeDataToTemplatePlaceholder(
        data: Data,
        sourcePackagesURL: URL
    ) throws -> Data {
        let primaryPath = sourcePackagesURL.standardizedFileURL.path
        let resolvedPath = sourcePackagesURL.resolvingSymlinksInPath().standardizedFileURL.path

        var current = try WorkspaceStateParser.rewritingPaths(
            in: data,
            toNewSourcePackagesPath: Self.templateRootPlaceholder,
            replacingOldSourcePackagesPath: primaryPath
        )
        if resolvedPath != primaryPath {
            current = try WorkspaceStateParser.rewritingPaths(
                in: current,
                toNewSourcePackagesPath: Self.templateRootPlaceholder,
                replacingOldSourcePackagesPath: resolvedPath
            )
        }
        current = try WorkspaceStateParser.rewritingPaths(
            in: current,
            toNewSourcePackagesPath: Self.templateRootPlaceholder,
            replacingOldSourcePackagesPath: nil
        )
        return current
    }

    private func sanitizeRawEntry(
        _ entry: [String: Any],
        sectionKey: String,
        sourcePackagesURL: URL
    ) -> Data? {
        let wrapper: [String: Any] = [
            "version": 7,
            "object": [
                sectionKey: [entry]
            ]
        ]
        guard let rawData = try? JSONSerialization.data(withJSONObject: wrapper, options: []),
              let sanitized = try? sanitizeDataToTemplatePlaceholder(data: rawData, sourcePackagesURL: sourcePackagesURL),
              let sanitizedRoot = try? JSONSerialization.jsonObject(with: sanitized, options: []) as? [String: Any],
              let object = sanitizedRoot["object"] as? [String: Any],
              let list = object[sectionKey] as? [[String: Any]],
              let sanitizedEntry = list.first else {
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: sanitizedEntry, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private func buildSanitizedWorkspaceStateData(
        rawRoot: [String: Any],
        workspaceState: WorkspaceState,
        sourcePackagesURL: URL,
        revisionByIdentity: [String: String],
        validCheckoutIdentities: Set<String>,
        validArtifactKeys: Set<String>,
        validPrebuiltKeys: Set<String>
    ) -> Data? {
        var root = rawRoot
        guard var object = root["object"] as? [String: Any] else {
            return nil
        }

        if let rawDeps = object["dependencies"] as? [[String: Any]] {
            object["dependencies"] = rawDeps.enumerated().compactMap { index, raw -> [String: Any]? in
                guard index < workspaceState.dependencies.count else { return nil }
                let dep = workspaceState.dependencies[index]
                let id = dep.packageRef.identity.lowercased()
                let hasRevision = (dep.state.checkoutState?.revision?.isEmpty == false) || (revisionByIdentity[id]?.isEmpty == false)
                if dep.state.name == "sourceControlCheckout" && !hasRevision {
                    return nil
                }
                if dep.state.name == "sourceControlCheckout" && !validCheckoutIdentities.contains(id) && !store.hasCheckout(identity: id, revision: dep.state.checkoutState?.revision ?? revisionByIdentity[id] ?? "") {
                    return nil
                }
                return raw
            }
        }

        if let rawArtifacts = object["artifacts"] as? [[String: Any]] {
            object["artifacts"] = rawArtifacts.enumerated().compactMap { index, raw -> [String: Any]? in
                guard index < workspaceState.artifacts.count else { return nil }
                let artifact = workspaceState.artifacts[index]
                guard let checksum = artifact.checksum, !checksum.isEmpty else { return nil }
                let key = artifactKey(
                    identity: artifact.packageRef.identity.lowercased(),
                    targetName: artifact.targetName,
                    checksum: checksum
                )
                return validArtifactKeys.contains(key) ? raw : nil
            }
        }

        if let rawPrebuilts = object["prebuilts"] as? [[String: Any]] {
            object["prebuilts"] = rawPrebuilts.enumerated().compactMap { index, raw -> [String: Any]? in
                guard index < workspaceState.prebuilts.count else { return nil }
                let prebuilt = workspaceState.prebuilts[index]
                guard let voc = prebuilt.checksum ?? prebuilt.version, !voc.isEmpty else { return nil }
                let key = prebuiltKey(identity: prebuilt.identity.lowercased(), versionOrChecksum: voc)
                return validPrebuiltKeys.contains(key) ? raw : nil
            }
        }

        root["object"] = object
        guard let filteredData = try? JSONSerialization.data(withJSONObject: root, options: []) else {
            return nil
        }
        return try? sanitizeDataToTemplatePlaceholder(data: filteredData, sourcePackagesURL: sourcePackagesURL)
    }

    private func synthesizeDependencyDict(for pin: PackagePin) -> [String: Any] {
        var checkoutState: [String: Any] = [:]
        if let revision = pin.revision { checkoutState["revision"] = revision }
        if let version = pin.version { checkoutState["version"] = version }
        if let branch = pin.branch { checkoutState["branch"] = branch }

        var packageRef: [String: Any] = [
            "identity": pin.identity.lowercased(),
            "kind": pin.kind.rawValue,
            "location": pin.location
        ]
        if let name = pin.packageName {
            packageRef["name"] = name
        }

        return [
            "packageRef": packageRef,
            "state": [
                "checkoutState": checkoutState,
                "name": "sourceControlCheckout"
            ],
            "subpath": pin.identity.lowercased()
        ]
    }

    // MARK: - Source Resolution Helpers

    private struct ResolvedSourceLocation {
        let sourceURL: URL
        let relativeSubpath: String
    }

    private func resolveArtifactSource(
        artifact: WorkspaceArtifact,
        sourcePackagesURL: URL
    ) -> ResolvedSourceLocation? {
        let identity = artifact.packageRef.identity.lowercased()
        let artifactsRoot = sourcePackagesURL.appendingPathComponent("artifacts").standardizedFileURL

        // Prefer `<SourcePackages>/artifacts/<identity>/<targetName>` when it exists.
        let targetDir = artifactsRoot
            .appendingPathComponent(identity)
            .appendingPathComponent(artifact.targetName)
            .standardizedFileURL

        if itemExists(at: targetDir) {
            return ResolvedSourceLocation(
                sourceURL: targetDir,
                relativeSubpath: "\(identity)/\(artifact.targetName)"
            )
        }

        // Fall back to resolving `artifact.path` relative to `<SourcePackages>/artifacts/`.
        if let relative = extractRelativeSubpath(
            from: artifact.path,
            sectionName: "artifacts",
            sourcePackagesURL: sourcePackagesURL
        ) {
            let candidate = artifactsRoot.appendingPathComponent(relative).standardizedFileURL
            if itemExists(at: candidate) {
                return ResolvedSourceLocation(sourceURL: candidate, relativeSubpath: relative)
            }
        }

        let directURL = URL(fileURLWithPath: artifact.path).standardizedFileURL
        if itemExists(at: directURL) {
            return ResolvedSourceLocation(
                sourceURL: directURL,
                relativeSubpath: "\(identity)/\(directURL.lastPathComponent)"
            )
        }

        return nil
    }

    private func resolvePrebuiltSource(
        prebuilt: WorkspacePrebuilt,
        sourcePackagesURL: URL
    ) -> ResolvedSourceLocation? {
        let prebuiltsRoot = sourcePackagesURL.appendingPathComponent("prebuilts").standardizedFileURL

        if let rawPath = prebuilt.path, !rawPath.isEmpty {
            if let relative = extractRelativeSubpath(
                from: rawPath,
                sectionName: "prebuilts",
                sourcePackagesURL: sourcePackagesURL
            ) {
                let candidate = prebuiltsRoot.appendingPathComponent(relative).standardizedFileURL
                if itemExists(at: candidate) {
                    return ResolvedSourceLocation(sourceURL: candidate, relativeSubpath: relative)
                }
            }
            let directURL = URL(fileURLWithPath: rawPath).standardizedFileURL
            if itemExists(at: directURL) {
                let rel = prebuilt.subpath ?? prebuilt.identity.lowercased()
                return ResolvedSourceLocation(sourceURL: directURL, relativeSubpath: rel)
            }
        }

        let fallbackRelative = prebuilt.subpath ?? prebuilt.identity.lowercased()
        let fallbackURL = prebuiltsRoot.appendingPathComponent(fallbackRelative).standardizedFileURL
        if itemExists(at: fallbackURL) {
            return ResolvedSourceLocation(sourceURL: fallbackURL, relativeSubpath: fallbackRelative)
        }

        return nil
    }

    private func extractRelativeSubpath(
        from rawPath: String,
        sectionName: String,
        sourcePackagesURL: URL
    ) -> String? {
        let candidateRoots = [
            sourcePackagesURL.standardizedFileURL.appendingPathComponent(sectionName).path,
            sourcePackagesURL.resolvingSymlinksInPath().standardizedFileURL.appendingPathComponent(sectionName).path
        ]
        for root in candidateRoots {
            let prefix = root.hasSuffix("/") ? root : root + "/"
            if rawPath.hasPrefix(prefix) {
                let rel = String(rawPath.dropFirst(prefix.count))
                if !rel.isEmpty { return rel }
            }
        }

        for marker in ["/SourcePackages/\(sectionName)/", "/.build/\(sectionName)/", "/\(sectionName)/"] {
            if let range = rawPath.range(of: marker) {
                let rel = String(rawPath[range.upperBound...])
                if !rel.isEmpty { return rel }
            }
        }
        return nil
    }

    // MARK: - Template Storage (`~/.pspm/store/templates/`)

    private struct WorkspaceTemplateRecord: Codable, Sendable {
        let schemaVersion: Int
        let pinSetHash: String
        let toolchainHash: String?
        let workspaceStateJSONBase64: String
        let artifacts: [ArtifactTemplateEntry]
        let prebuilts: [PrebuiltTemplateEntry]
        let updatedAt: Date
    }

    private struct PackageTemplateRecord: Codable, Sendable {
        let identity: String
        let revision: String
        let subpath: String?
        let rawDependencyJSONBase64: String?
        let artifacts: [ArtifactTemplateEntry]
        let updatedAt: Date
    }

    private struct ArtifactTemplateEntry: Codable, Sendable {
        let identity: String
        let targetName: String
        let checksum: String
        let relativeSubpath: String
        let isDirectoryBundle: Bool
        let rawArtifactJSONBase64: String?
    }

    private struct PrebuiltTemplateEntry: Codable, Sendable {
        let identity: String
        let revision: String?
        let version: String?
        let checksum: String?
        let versionOrChecksum: String
        let relativeSubpath: String
        let rawPrebuiltJSONBase64: String?
        let updatedAt: Date
    }

    private var templatesDirectory: URL {
        store.rootURL.appendingPathComponent("templates")
    }

    private var templatesLockURL: URL {
        store.locksDirectory.appendingPathComponent("templates.lock")
    }

    @discardableResult
    private func saveWorkspaceTemplate(_ record: WorkspaceTemplateRecord) throws -> URL {
        try FileLock.withLock(at: templatesLockURL, timeout: store.lockTimeout) {
            let dir = templatesDirectory.appendingPathComponent("workspaces")
            try ensureDirectory(dir)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(record)

            let genericURL = dir.appendingPathComponent("\(record.pinSetHash).json")
            try data.write(to: genericURL, options: .atomic)

            if let toolchainHash = record.toolchainHash {
                let scopedURL = dir.appendingPathComponent("\(record.pinSetHash)-\(sanitizeFilename(toolchainHash)).json")
                try data.write(to: scopedURL, options: .atomic)
                return scopedURL
            }
            return genericURL
        }
    }

    private func loadWorkspaceTemplate(
        pinSetHash: String,
        toolchainHash: String?
    ) throws -> WorkspaceTemplateRecord? {
        try FileLock.withLock(at: templatesLockURL, timeout: store.lockTimeout) {
            let dir = templatesDirectory.appendingPathComponent("workspaces")
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            if let toolchainHash {
                let scopedURL = dir.appendingPathComponent("\(pinSetHash)-\(sanitizeFilename(toolchainHash)).json")
                if fileManager.fileExists(atPath: scopedURL.path),
                   let data = try? Data(contentsOf: scopedURL),
                   let decoded = try? decoder.decode(WorkspaceTemplateRecord.self, from: data) {
                    return decoded
                }
            }

            let genericURL = dir.appendingPathComponent("\(pinSetHash).json")
            if fileManager.fileExists(atPath: genericURL.path),
               let data = try? Data(contentsOf: genericURL),
               let decoded = try? decoder.decode(WorkspaceTemplateRecord.self, from: data) {
                return decoded
            }

            return nil
        }
    }

    private func savePackageTemplate(_ record: PackageTemplateRecord) throws {
        try FileLock.withLock(at: templatesLockURL, timeout: store.lockTimeout) {
            let dir = templatesDirectory.appendingPathComponent("packages")
            try ensureDirectory(dir)
            let filename = "\(sanitizeFilename(record.identity))-\(sanitizeFilename(record.revision)).json"
            let url = dir.appendingPathComponent(filename)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(record)
            try data.write(to: url, options: .atomic)
        }
    }

    private func loadPackageTemplate(identity: String, revision: String) throws -> PackageTemplateRecord? {
        try FileLock.withLock(at: templatesLockURL, timeout: store.lockTimeout) {
            let dir = templatesDirectory.appendingPathComponent("packages")
            let filename = "\(sanitizeFilename(identity.lowercased()))-\(sanitizeFilename(revision)).json"
            let url = dir.appendingPathComponent(filename)
            guard fileManager.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url) else {
                return nil
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(PackageTemplateRecord.self, from: data)
        }
    }

    private func savePrebuiltTemplate(_ entry: PrebuiltTemplateEntry, toolchainHash: String) throws {
        try FileLock.withLock(at: templatesLockURL, timeout: store.lockTimeout) {
            let dir = templatesDirectory
                .appendingPathComponent("prebuilts")
                .appendingPathComponent(sanitizeFilename(toolchainHash))
            try ensureDirectory(dir)
            let filename = "\(sanitizeFilename(entry.identity))-\(sanitizeFilename(entry.versionOrChecksum)).json"
            let url = dir.appendingPathComponent(filename)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entry)
            try data.write(to: url, options: .atomic)
        }
    }

    private func loadPrebuiltTemplates(toolchainHash: String) throws -> [PrebuiltTemplateEntry] {
        try FileLock.withLock(at: templatesLockURL, timeout: store.lockTimeout) {
            let dir = templatesDirectory
                .appendingPathComponent("prebuilts")
                .appendingPathComponent(sanitizeFilename(toolchainHash))
            guard isDirectory(at: dir),
                  let files = try? fileManager.contentsOfDirectory(
                      at: dir,
                      includingPropertiesForKeys: nil,
                      options: [.skipsHiddenFiles]
                  ) else {
                return []
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).compactMap { url in
                guard url.pathExtension == "json",
                      let data = try? Data(contentsOf: url) else {
                    return nil
                }
                return try? decoder.decode(PrebuiltTemplateEntry.self, from: data)
            }
        }
    }

    private func collectArtifactTemplates(
        pins: [PackagePin],
        workspaceTemplate: WorkspaceTemplateRecord?,
        packageTemplates: [String: PackageTemplateRecord]
    ) -> [ArtifactTemplateEntry] {
        var result: [ArtifactTemplateEntry] = []
        var seen: Set<String> = []

        if let workspaceTemplate {
            for artifact in workspaceTemplate.artifacts {
                let key = artifactKey(identity: artifact.identity, targetName: artifact.targetName, checksum: artifact.checksum)
                if seen.insert(key).inserted {
                    result.append(artifact)
                }
            }
        }

        for pin in pins {
            let identity = pin.identity.lowercased()
            if let pkgTemplate = packageTemplates[identity] {
                for artifact in pkgTemplate.artifacts {
                    let key = artifactKey(identity: artifact.identity, targetName: artifact.targetName, checksum: artifact.checksum)
                    if seen.insert(key).inserted {
                        result.append(artifact)
                    }
                }
            }
        }

        return result
    }

    private func collectPrebuiltTemplates(
        pins: [PackagePin],
        toolchainHash: String,
        workspaceTemplate: WorkspaceTemplateRecord?
    ) throws -> [PrebuiltTemplateEntry] {
        var result: [PrebuiltTemplateEntry] = []
        var seen: Set<String> = []

        if let workspaceTemplate, workspaceTemplate.toolchainHash == toolchainHash {
            for prebuilt in workspaceTemplate.prebuilts {
                let key = prebuiltKey(identity: prebuilt.identity, versionOrChecksum: prebuilt.versionOrChecksum)
                if seen.insert(key).inserted {
                    result.append(prebuilt)
                }
            }
        }

        let allToolchainPrebuilts = try loadPrebuiltTemplates(toolchainHash: toolchainHash)
        let pinsByIdentity = Dictionary(grouping: pins, by: { $0.identity.lowercased() })

        for entry in allToolchainPrebuilts {
            guard let matchingPins = pinsByIdentity[entry.identity.lowercased()] else { continue }
            let matchesPin = matchingPins.contains { pin in
                if let entryRev = entry.revision, let pinRev = pin.revision {
                    return entryRev == pinRev
                }
                if let entryVer = entry.version, let pinVer = pin.version {
                    return entryVer == pinVer
                }
                return entry.revision == nil && entry.version == nil
            }
            if matchesPin {
                let key = prebuiltKey(identity: entry.identity, versionOrChecksum: entry.versionOrChecksum)
                if seen.insert(key).inserted {
                    result.append(entry)
                }
            }
        }

        return result
    }

    // MARK: - Filesystem & Git Helpers

    private func resolveToolchain(verboseLogger: (@Sendable (String) -> Void)?) -> ToolchainFingerprint? {
        do {
            return try toolchainProvider()
        } catch {
            verboseLogger?("Toolchain fingerprint unavailable (\(error.localizedDescription)); skipping toolchain-specific prebuilts.")
            return nil
        }
    }

    private func ensureDirectory(_ url: URL) throws {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw SyncError.ioFailed(operation: "create directory", path: url.path, message: error.localizedDescription)
        }
    }

    private func itemExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    private func isDirectory(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func isDirectoryEmpty(at url: URL) -> Bool {
        guard isDirectory(at: url) else { return false }
        let contents = (try? fileManager.contentsOfDirectory(atPath: url.path)) ?? []
        return contents.isEmpty
    }

    private func isEmptyItem(at url: URL) -> Bool {
        if isDirectory(at: url) {
            return isDirectoryEmpty(at: url)
        }
        return !fileManager.fileExists(atPath: url.path)
    }

    private func containsPartialMarker(at url: URL) -> Bool {
        if url.lastPathComponent == ".partial" || url.lastPathComponent.hasSuffix(".partial") {
            return true
        }
        if fileManager.fileExists(atPath: url.path + ".partial") {
            return true
        }
        guard isDirectory(at: url) else {
            return false
        }
        if fileManager.fileExists(atPath: url.appendingPathComponent(".partial").path) {
            return true
        }
        if let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        ) {
            for case let itemURL as URL in enumerator {
                let name = itemURL.lastPathComponent
                if name == ".partial" || name.hasSuffix(".partial") {
                    return true
                }
            }
        }
        return false
    }

    private func isGitWorkingTreeDirty(at directoryURL: URL) -> Bool {
        let gitPath = directoryURL.appendingPathComponent(".git").path
        guard fileManager.fileExists(atPath: gitPath) else {
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directoryURL.path, "status", "--porcelain"]
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return false }
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !output.isEmpty
        } catch {
            return false
        }
    }

    private static func computePinSetHash(pins: [PackagePin]) -> String {
        let parts = pins
            .map { pin in
                let id = pin.identity.lowercased()
                let ref = pin.revision ?? pin.version ?? pin.branch ?? ""
                return "\(id):\(ref)"
            }
            .sorted()
        let payload = parts.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private func sanitizeFilename(_ raw: String) -> String {
        raw.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }

    private func artifactKey(identity: String, targetName: String, checksum: String) -> String {
        "\(identity.lowercased())|\(targetName)|\(checksum)"
    }

    private func prebuiltKey(identity: String, versionOrChecksum: String) -> String {
        "\(identity.lowercased())|\(versionOrChecksum)"
    }

    private func extractChecksum(fromRawArtifact raw: [String: Any]) -> String? {
        if let direct = raw["checksum"] as? String, !direct.isEmpty {
            return direct
        }
        if let source = raw["source"] as? [String: Any] {
            if let checksum = source["checksum"] as? String, !checksum.isEmpty {
                return checksum
            }
            if let remote = source["remote"] as? [String: Any],
               let checksum = remote["checksum"] as? String, !checksum.isEmpty {
                return checksum
            }
            if let local = source["local"] as? [String: Any],
               let checksum = local["checksum"] as? String, !checksum.isEmpty {
                return checksum
            }
        }
        return nil
    }

    private func extractPrebuiltIdentity(fromRaw raw: [String: Any]) -> String? {
        if let id = raw["identity"] as? String, !id.isEmpty {
            return id.lowercased()
        }
        if let ref = raw["packageRef"] as? [String: Any],
           let id = ref["identity"] as? String, !id.isEmpty {
            return id.lowercased()
        }
        return nil
    }
}

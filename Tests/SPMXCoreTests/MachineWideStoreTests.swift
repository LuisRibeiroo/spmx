import Foundation
import Testing
@testable import SPMXCore

@Suite("Machine-Wide Store (US-001 .. US-005)")
struct MachineWideStoreTests {
    @Test("US-001: Indexes semantic versions and maps Project A, B, C across shared and distinct versions")
    func multiProjectSemanticVersionIndexing() throws {
        let root = try makeTempDir(prefix: "spmx-us001")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = GlobalStore(rootURL: root.appendingPathComponent("store"))
        let engine = PackageSyncEngine(store: store)

        // Project A: firebase 1.0.0, stripe 3.4.5, xyz 4.0.0
        let projA = try createSwiftPMProject(
            at: root.appendingPathComponent("project-a"),
            pins: [
                ("firebase-ios-sdk", "1.0.0", "rev-fb-100", "https://github.com/firebase/firebase-ios-sdk.git"),
                ("stripe-ios", "3.4.5", "rev-stripe-345", "https://github.com/stripe/stripe-ios.git"),
                ("xyz", "4.0.0", "rev-xyz-400", "https://github.com/example/xyz.git")
            ],
            populateBuildCheckouts: true
        )
        _ = try engine.harvest(project: projA)

        // Project C: firebase 1.0.1, stripe 3.4.5
        let projC = try createSwiftPMProject(
            at: root.appendingPathComponent("project-c"),
            pins: [
                ("firebase-ios-sdk", "1.0.1", "rev-fb-101", "https://github.com/firebase/firebase-ios-sdk.git"),
                ("stripe-ios", "3.4.5", "rev-stripe-345", "https://github.com/stripe/stripe-ios.git")
            ],
            populateBuildCheckouts: true
        )
        _ = try engine.harvest(project: projC)

        // Project B: xyz 4.0.0 (cached), abc 1.0.0 (new)
        let projB = try createSwiftPMProject(
            at: root.appendingPathComponent("project-b"),
            pins: [
                ("xyz", "4.0.0", "rev-xyz-400", "https://github.com/example/xyz.git"),
                ("abc", "1.0.0", "rev-abc-100", "https://github.com/example/abc.git")
            ],
            populateBuildCheckouts: false
        )
        let hydrateB = try engine.hydrate(project: projB)
        #expect(hydrateB.hydratedCheckouts.map(\.identity) == ["xyz"])
        #expect(hydrateB.skippedCheckouts.count == 1)
        #expect(hydrateB.skippedCheckouts.first?.identity == "abc")
        #expect(hydrateB.skippedCheckouts.first?.reason == .notInStore)

        // Both firebase 1.0.0 and 1.0.1 coexist in store
        #expect(store.hasCheckout(identity: "firebase-ios-sdk", revision: "rev-fb-100"))
        #expect(store.hasCheckout(identity: "firebase-ios-sdk", revision: "rev-fb-101"))
        #expect(store.hasCheckout(identity: "stripe-ios", revision: "rev-stripe-345"))

        let listReport = try StoreManager(store: store).list()
        let fb100 = listReport.packages.first { $0.identity == "firebase-ios-sdk" && $0.version == "1.0.0" }
        let fb101 = listReport.packages.first { $0.identity == "firebase-ios-sdk" && $0.version == "1.0.1" }
        let stripe345 = listReport.packages.first { $0.identity == "stripe-ios" && $0.version == "3.4.5" }

        #expect(fb100?.linkedProjects.count == 1)
        #expect(fb101?.linkedProjects.count == 1)
        #expect(stripe345?.linkedProjects.count == 2)
    }

    @Test("US-001: Backwards-compatible decoding of legacy index.json without pinnedDependencies or excludedProjects")
    func legacyIndexMigration() throws {
        let root = try makeTempDir(prefix: "spmx-legacy-index")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = GlobalStore(rootURL: root.appendingPathComponent("store"))
        try store.ensureLayout()

        let legacyJSON = """
        {
          "schemaVersion": 1,
          "projects": {
            "/tmp/old-proj": {
              "path": "/tmp/old-proj",
              "registeredAt": "2026-01-01T00:00:00Z",
              "lastAccessedAt": "2026-01-01T00:00:00Z",
              "packageIdentities": ["stripe-ios"]
            }
          },
          "toolchains": {},
          "flutterResolvedCache": {}
        }
        """
        try Data(legacyJSON.utf8).write(to: store.indexURL)

        let index = try store.readIndex()
        #expect(index.projects["/tmp/old-proj"]?.packageIdentities == ["stripe-ios"])
        #expect(index.projects["/tmp/old-proj"]?.pinnedDependencies.isEmpty == true)
        #expect(index.excludedProjects.isEmpty)
    }

    @Test("US-002: Harvests & hydrates bare repositories/ and preserves workspace-state.json version on partial hydration")
    func repositoriesAndPartialHydration() throws {
        let root = try makeTempDir(prefix: "spmx-us002")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = GlobalStore(rootURL: root.appendingPathComponent("store"))
        let engine = PackageSyncEngine(store: store)

        // Create Project A with custom workspace-state version 8 and a bare repository in .build/repositories/xyz-12345678
        let projADir = root.appendingPathComponent("project-a")
        let projA = try createSwiftPMProject(
            at: projADir,
            pins: [
                ("xyz", "4.0.0", "rev-xyz-400", "https://github.com/example/xyz.git")
            ],
            populateBuildCheckouts: true,
            workspaceStateVersion: 8
        )
        let bareRepoA = projADir
            .appendingPathComponent(".build/repositories/xyz-12345678")
        try createBareGitRepo(at: bareRepoA)

        let harvestA = try engine.harvest(project: projA)
        #expect(harvestA.harvestedRepositories.map(\.identity) == ["xyz"])
        #expect(store.hasRepository(identity: "xyz"))

        // Create Project B with xyz (in store) and abc (missing) -> partial hydration
        let projBDir = root.appendingPathComponent("project-b")
        let projB = try createSwiftPMProject(
            at: projBDir,
            pins: [
                ("xyz", "4.0.0", "rev-xyz-400", "https://github.com/example/xyz.git"),
                ("abc", "1.0.0", "rev-abc-100", "https://github.com/example/abc.git")
            ],
            populateBuildCheckouts: false
        )
        let hydrateB = try engine.hydrate(project: projB)
        #expect(hydrateB.hydratedCheckouts.map(\.identity) == ["xyz"])
        #expect(hydrateB.hydratedRepositories.map(\.folderName) == ["xyz-12345678"])
        #expect(FileManager.default.fileExists(atPath: projBDir.appendingPathComponent(".build/repositories/xyz-12345678/HEAD").path))

        let wsData = try Data(contentsOf: projBDir.appendingPathComponent(".build/workspace-state.json"))
        let wsJSON = try JSONSerialization.jsonObject(with: wsData) as? [String: Any]
        #expect(wsJSON?["version"] as? Int == 8)
    }

    @Test("US-003: Harvest rejects dirty git checkouts and HEAD revision mismatches")
    func harvestRejectsDirtyAndMismatchedCheckouts() throws {
        let root = try makeTempDir(prefix: "spmx-us003-git")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = GlobalStore(rootURL: root.appendingPathComponent("store"))
        let engine = PackageSyncEngine(store: store)

        let projDir = root.appendingPathComponent("project-git")
        let checkoutDir = projDir.appendingPathComponent(".build/checkouts/stripe-ios")
        let actualRev = try createGitWorkingRepo(at: checkoutDir)

        // 1. Dirty working tree: modify a tracked file
        try Data("dirty".utf8).write(to: checkoutDir.appendingPathComponent("Package.swift"))
        let dirtyProj = try createSwiftPMProject(
            at: projDir,
            pins: [("stripe-ios", "3.4.5", actualRev, "https://github.com/stripe/stripe-ios.git")],
            populateBuildCheckouts: false
        )
        let dirtyHarvest = try engine.harvest(project: dirtyProj)
        #expect(dirtyHarvest.harvestedCheckouts.isEmpty)
        #expect(dirtyHarvest.skippedItems.contains { $0.reason == "locally modified working tree" })
        #expect(!store.hasCheckout(identity: "stripe-ios", revision: actualRev))

        // 2. Clean working tree, but HEAD != Package.resolved revision
        try runGit(["-C", checkoutDir.path, "checkout", "--", "Package.swift"])
        let mismatchedProj = try createSwiftPMProject(
            at: projDir,
            pins: [("stripe-ios", "3.4.5", "0000000000000000000000000000000000000000", "https://github.com/stripe/stripe-ios.git")],
            populateBuildCheckouts: false
        )
        let mismatchHarvest = try engine.harvest(project: mismatchedProj)
        #expect(mismatchHarvest.harvestedCheckouts.isEmpty)
        #expect(mismatchHarvest.skippedItems.contains { $0.reason == "HEAD revision mismatch" })
    }

    @Test("US-003: Flutter Project B pre-hydrates compatible packages from store despite different dependencyHash")
    func flutterCrossProjectPrehydration() throws {
        let root = try makeTempDir(prefix: "spmx-us003-flutter")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = GlobalStore(rootURL: root.appendingPathComponent("store"))
        let syncEngine = PackageSyncEngine(store: store)
        let integrator = FlutterSPMIntegrator(store: store)

        // Seed store with firebase-ios-sdk from Project A
        let seedProj = try createSwiftPMProject(
            at: root.appendingPathComponent("seed"),
            pins: [("firebase-ios-sdk", "1.0.0", "rev-fb-100", "https://github.com/firebase/firebase-ios-sdk.git")],
            populateBuildCheckouts: true
        )
        _ = try syncEngine.harvest(project: seedProj)

        // Create a local Flutter plugin with Package.swift referencing firebase-ios-sdk
        let pluginDir = root.appendingPathComponent("pub-cache/firebase_core")
        try FileManager.default.createDirectory(
            at: pluginDir.appendingPathComponent("ios/firebase_core"),
            withIntermediateDirectories: true
        )
        try Data("""
        // swift-tools-version: 5.9
        import PackageDescription
        let package = Package(name: "firebase_core", dependencies: [
            .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "1.0.0")
        ])
        """.utf8).write(to: pluginDir.appendingPathComponent("ios/firebase_core/Package.swift"))

        // Create Flutter Project B without Package.resolved, only .flutter-plugins-dependencies
        let flutterB = root.appendingPathComponent("flutter-app-b")
        try FileManager.default.createDirectory(at: flutterB.appendingPathComponent("ios/Runner.xcodeproj"), withIntermediateDirectories: true)
        try Data("name: flutter_app_b\n".utf8).write(to: flutterB.appendingPathComponent("pubspec.yaml"))
        let depsJSON = """
        {
          "plugins": {
            "ios": [
              { "name": "firebase_core", "path": "\(pluginDir.path)" }
            ]
          }
        }
        """
        try Data(depsJSON.utf8).write(to: flutterB.appendingPathComponent(".flutter-plugins-dependencies"))

        let detectedB = try ProjectDetector.detect(in: flutterB.path)
        let destSP = flutterB.appendingPathComponent("build/ios/SourcePackages")
        let result = try integrator.prehydrateCompatiblePackages(
            for: detectedB,
            destinationURL: destSP,
            syncEngine: syncEngine
        )
        #expect(result?.hydratedCheckouts.map(\.identity) == ["firebase-ios-sdk"])
        #expect(FileManager.default.fileExists(atPath: destSP.appendingPathComponent("checkouts/firebase-ios-sdk").path))
    }

    @Test("US-004 & US-005: Unlink excludes shims and MigrationManager, re-link restores, and status reports savings")
    func unlinkLinkAndSavingsReporting() throws {
        let root = try makeTempDir(prefix: "spmx-us004-005")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = GlobalStore(rootURL: root.appendingPathComponent("store"))
        let projDir = root.appendingPathComponent("my-swift-app")
        let project = try createSwiftPMProject(
            at: projDir,
            pins: [("stripe-ios", "3.4.5", "rev-stripe-345", "https://github.com/stripe/stripe-ios.git")],
            populateBuildCheckouts: true
        )

        // Harvest & hydrate so project is linked and has CoW clones
        let engine = PackageSyncEngine(store: store)
        _ = try engine.harvest(project: project)
        _ = try engine.hydrate(project: project, options: HydrateOptions(deduplicateCleanEntries: true))

        // Check ProjectStatusInspector when linked
        let inspector = ProjectStatusInspector(store: store)
        let linkedStatus = try inspector.inspect(in: projDir.path)
        #expect(linkedStatus.isLinked == true)
        #expect(linkedStatus.pinStatuses.first?.version == "3.4.5")
        #expect(linkedStatus.pinStatuses.first?.status == .hydrated)
        if APFSCloner.isAPFS(at: store.rootURL) {
            #expect(linkedStatus.projectSavedBytes > 0)
        }

        // Unlink project
        _ = try store.excludeProject(at: projDir.path, reason: "local debugging")
        #expect(store.isProjectExcluded(at: projDir.path))
        let unlinkedStatus = try inspector.inspect(in: projDir.path)
        #expect(unlinkedStatus.isLinked == false)
        #expect(unlinkedStatus.projectSavedBytes == 0)

        // MigrationManager skips excluded project unless includeExcluded: true
        let migrationManager = MigrationManager(store: store)
        let skippedDiscovery = migrationManager.discoverProjects(in: [root.path])
        #expect(!skippedDiscovery.contains { $0.rootPath == project.rootPath })

        let includedDiscovery = migrationManager.discoverProjects(in: [root.path], includeExcluded: true)
        #expect(includedDiscovery.contains {
            URL(fileURLWithPath: $0.rootPath).resolvingSymlinksInPath().path ==
                URL(fileURLWithPath: project.rootPath).resolvingSymlinksInPath().path
        })

        // ShimDispatcher passes through for unlinked project
        let fakeBin = root.appendingPathComponent("fake-bin")
        try FileManager.default.createDirectory(at: fakeBin, withIntermediateDirectories: true)
        let fakeSwift = fakeBin.appendingPathComponent("swift")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: fakeSwift)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeSwift.path)

        let dispatcher = ShimDispatcher(store: store)
        let outcome = try dispatcher.dispatch(
            role: .swift,
            arguments: ["build"],
            workingDirectory: projDir.path,
            environment: ["PATH": fakeBin.path]
        )
        #expect(outcome.bypassed == true)
        #expect(outcome.didHydrate == false)
        #expect(outcome.didHarvest == false)
        #expect(outcome.injectedCompilationCache == false)

        // Re-link project
        let wasExcluded = try store.includeProject(at: projDir.path)
        #expect(wasExcluded == true)
        #expect(!store.isProjectExcluded(at: projDir.path))
    }

    // MARK: - Helpers

    private func makeTempDir(prefix: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func createSwiftPMProject(
        at root: URL,
        pins: [(identity: String, version: String, revision: String, location: String)],
        populateBuildCheckouts: Bool,
        workspaceStateVersion: Int = 7
    ) throws -> DetectedProject {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("// swift-tools-version: 5.9\nimport PackageDescription\nlet package = Package(name: \"App\")\n".utf8)
            .write(to: root.appendingPathComponent("Package.swift"))

        let pinObjects: [[String: Any]] = pins.map { pin in
            [
                "identity": pin.identity,
                "kind": "remoteSourceControl",
                "location": pin.location,
                "state": [
                    "revision": pin.revision,
                    "version": pin.version
                ]
            ]
        }
        let resolvedJSON: [String: Any] = ["pins": pinObjects, "version": 2]
        let resolvedData = try JSONSerialization.data(withJSONObject: resolvedJSON, options: [.prettyPrinted])
        try resolvedData.write(to: root.appendingPathComponent("Package.resolved"))

        if populateBuildCheckouts {
            let checkoutsDir = root.appendingPathComponent(".build/checkouts")
            try fm.createDirectory(at: checkoutsDir, withIntermediateDirectories: true)
            var wsDeps: [[String: Any]] = []
            for pin in pins {
                let pkgDir = checkoutsDir.appendingPathComponent(pin.identity)
                try fm.createDirectory(at: pkgDir, withIntermediateDirectories: true)
                try Data(String(repeating: "x", count: 4096).utf8)
                    .write(to: pkgDir.appendingPathComponent("Source.swift"))
                wsDeps.append([
                    "packageRef": [
                        "identity": pin.identity,
                        "kind": "remoteSourceControl",
                        "location": pin.location,
                        "name": pin.identity
                    ],
                    "state": [
                        "checkoutState": [
                            "revision": pin.revision,
                            "version": pin.version
                        ],
                        "name": "sourceControlCheckout"
                    ],
                    "subpath": pin.identity
                ])
            }
            let wsRoot: [String: Any] = [
                "object": [
                    "artifacts": [],
                    "dependencies": wsDeps,
                    "prebuilts": []
                ],
                "version": workspaceStateVersion
            ]
            let wsData = try JSONSerialization.data(withJSONObject: wsRoot, options: [.prettyPrinted])
            try wsData.write(to: root.appendingPathComponent(".build/workspace-state.json"))
        }

        return try ProjectDetector.detect(in: root.path)
    }

    private func createBareGitRepo(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try runGit(["init", "--bare", url.path])
    }

    private func createGitWorkingRepo(at url: URL) throws -> String {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try runGit(["init", url.path])
        try runGit(["-C", url.path, "config", "user.email", "test@example.com"])
        try runGit(["-C", url.path, "config", "user.name", "Test"])
        try Data("// swift-tools-version: 5.9\n".utf8).write(to: url.appendingPathComponent("Package.swift"))
        try runGit(["-C", url.path, "add", "Package.swift"])
        try runGit(["-C", url.path, "commit", "-m", "init"])
        let res = try CommandExecutor.run(executablePath: "/usr/bin/git", arguments: ["-C", url.path, "rev-parse", "HEAD"])
        return res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    private func runGit(_ args: [String]) throws -> String {
        let res = try CommandExecutor.run(executablePath: "/usr/bin/git", arguments: args)
        return res.stdout
    }
}

import Foundation
import Testing
@testable import PSPMCore

@Suite("Store, Status, and Doctor Diagnostics")
struct StoreAndDoctorTests {
    // MARK: - StoreManager.status()

    @Test("store status groups prebuilts by toolchain and reports compilation-cache size and CoW savings")
    func storeStatusReportsPrebuiltsCacheAndCoWSavings() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let storeRoot = tmp.appendingPathComponent(".pspm/store")
        let cacheRoot = tmp.appendingPathComponent(".pspm/compilation-cache")
        let store = GlobalStore(rootURL: storeRoot)
        try store.ensureLayout()

        let tcSwift60 = ToolchainFingerprint(
            swiftVersion: "Apple Swift version 6.0.3 (swiftlang-6.0.3.1.10)",
            xcodeVersion: "Xcode 16.2\nBuild version 16C5032a"
        )
        let tcSwift61 = ToolchainFingerprint(
            swiftVersion: "Apple Swift version 6.1.0 (swiftlang-6.1.0.1.0)",
            xcodeVersion: "Xcode 16.3\nBuild version 16E140"
        )
        try store.recordToolchain(tcSwift60)
        try store.recordToolchain(tcSwift61)

        // Seed checkouts, artifacts, and prebuilts
        let checkoutSrc = try makePayloadDir(in: tmp, name: "src-checkout", bytes: 1024)
        let artifactSrc = try makePayloadDir(in: tmp, name: "src-artifact", bytes: 2048)
        let prebuiltSrcA = try makePayloadDir(in: tmp, name: "src-prebuilt-a", bytes: 512)
        let prebuiltSrcB = try makePayloadDir(in: tmp, name: "src-prebuilt-b", bytes: 768)

        try store.storeCheckout(from: checkoutSrc, identity: "alamofire", revision: "rev-111")
        try store.storeArtifact(from: artifactSrc, identity: "firebase-ios-sdk", targetName: "FirebaseAnalytics", checksum: "chk-1")
        try store.storePrebuilt(from: prebuiltSrcA, toolchain: tcSwift60, packageIdentity: "swift-syntax", versionOrChecksum: "600.0.1")
        try store.storePrebuilt(from: prebuiltSrcB, toolchain: tcSwift61, packageIdentity: "swift-syntax", versionOrChecksum: "601.0.0")

        // Seed compilation cache files
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 4096).write(to: cacheRoot.appendingPathComponent("cas-object-1"))

        // Register 2 active projects and 1 missing project
        let activeProject1 = tmp.appendingPathComponent("worktree-1")
        let activeProject2 = tmp.appendingPathComponent("worktree-2")
        let missingProject = tmp.appendingPathComponent("worktree-missing")
        try FileManager.default.createDirectory(at: activeProject1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: activeProject2, withIntermediateDirectories: true)

        try writePackageResolvedV2(
            at: activeProject1.appendingPathComponent("Package.resolved"),
            pins: [("alamofire", "https://github.com/Alamofire/Alamofire.git", "rev-111", "5.9.0")]
        )
        try writePackageResolvedV2(
            at: activeProject2.appendingPathComponent("Package.resolved"),
            pins: [("alamofire", "https://github.com/Alamofire/Alamofire.git", "rev-111", "5.9.0")]
        )

        try store.registerProject(at: activeProject1.path, toolchain: tcSwift60, packageIdentities: ["alamofire"])
        try store.registerProject(at: activeProject2.path, toolchain: tcSwift60, packageIdentities: ["alamofire"])
        try store.registerProject(at: missingProject.path, toolchain: tcSwift61, packageIdentities: ["alamofire"])

        let manager = StoreManager(store: store, compilationCacheURL: cacheRoot, homeDirectory: tmp)
        #expect(manager.storePath() == storeRoot.standardizedFileURL.path)

        let report = try manager.status()
        #expect(report.storePath == storeRoot.standardizedFileURL.path)
        #expect(report.checkoutsCount == 1)
        #expect(report.checkoutsSizeBytes == 1024)
        #expect(report.artifactsCount == 1)
        #expect(report.artifactsSizeBytes == 2048)
        #expect(report.prebuiltsCount == 2)
        #expect(report.prebuiltsSizeBytes == 512 + 768)
        #expect(report.prebuiltsByToolchain.count == 2)

        let group60 = report.prebuiltsByToolchain.first { $0.toolchainHash == tcSwift60.hash }
        let group61 = report.prebuiltsByToolchain.first { $0.toolchainHash == tcSwift61.hash }
        #expect(group60?.count == 1)
        #expect(group60?.sizeBytes == 512)
        #expect(group60?.xcodeVersion?.contains("16.2") == true)
        #expect(group61?.count == 1)
        #expect(group61?.sizeBytes == 768)
        #expect(group61?.swiftVersion?.contains("6.1.0") == true)

        #expect(report.compilationCachePath == cacheRoot.standardizedFileURL.path)
        #expect(report.compilationCacheSizeBytes == 4096)
        #expect(report.activeProjectsCount == 2)
        #expect(report.missingProjectsCount == 1)
        #expect(report.totalRegisteredProjectsCount == 3)
        #expect(report.logicalStoreSizeBytes >= 1024 + 2048 + 512 + 768)

        if APFSCloner.isAPFS(at: storeRoot) {
            #expect(report.estimatedCoWSavingsBytes == 2048)
        }
    }

    // MARK: - StoreManager.prune()

    @Test("store prune --dry-run previews and actual prune removes stale projects, unreferenced entries, and old compilation cache")
    func storePruneDryRunAndActualCleanup() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let storeRoot = tmp.appendingPathComponent(".pspm/store")
        let cacheRoot = tmp.appendingPathComponent(".pspm/compilation-cache")
        let store = GlobalStore(rootURL: storeRoot)
        try store.ensureLayout()
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)

        let toolchain = ToolchainFingerprint(
            swiftVersion: "Apple Swift version 6.0.3",
            xcodeVersion: "Xcode 16.2"
        )
        let oldToolchain = ToolchainFingerprint(
            swiftVersion: "Apple Swift version 5.10",
            xcodeVersion: "Xcode 15.4"
        )

        // Active SwiftPM project referencing active-pkg@rev-active, active-artifact, active-prebuilt
        let activeProject = tmp.appendingPathComponent("active-project")
        try FileManager.default.createDirectory(at: activeProject.appendingPathComponent(".build"), withIntermediateDirectories: true)
        try "import PackageDescription\nlet package = Package(name: \"App\")\n".write(
            to: activeProject.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        try writePackageResolvedV2(
            at: activeProject.appendingPathComponent("Package.resolved"),
            pins: [("active-pkg", "https://example.com/active-pkg.git", "rev-active", "1.0.0")]
        )
        try writeWorkspaceState(
            at: activeProject.appendingPathComponent(".build/workspace-state.json"),
            checkoutIdentity: "active-pkg",
            checkoutRevision: "rev-active",
            artifactIdentity: "active-bin",
            artifactTarget: "ActiveSDK",
            artifactChecksum: "chk-active",
            prebuiltIdentity: "swift-syntax",
            prebuiltVersion: "600.0.1"
        )

        // Missing worktree registered in index.json
        let staleWorktreePath = tmp.appendingPathComponent("deleted-worktree").path

        try store.registerProject(at: activeProject.path, toolchain: toolchain, packageIdentities: ["active-pkg"])
        try store.registerProject(at: staleWorktreePath, toolchain: oldToolchain, packageIdentities: ["orphan-pkg"])

        // Referenced entries
        try store.storeCheckout(
            from: try makePayloadDir(in: tmp, name: "p1", bytes: 500),
            identity: "active-pkg",
            revision: "rev-active"
        )
        try store.storeArtifact(
            from: try makePayloadDir(in: tmp, name: "p2", bytes: 600),
            identity: "active-bin",
            targetName: "ActiveSDK",
            checksum: "chk-active"
        )
        try store.storePrebuilt(
            from: try makePayloadDir(in: tmp, name: "p3", bytes: 700),
            toolchain: toolchain,
            packageIdentity: "swift-syntax",
            versionOrChecksum: "600.0.1"
        )

        // Unreferenced entries (old vs recent)
        try store.storeCheckout(
            from: try makePayloadDir(in: tmp, name: "p4", bytes: 1000),
            identity: "orphan-pkg",
            revision: "rev-old"
        )
        try store.storeCheckout(
            from: try makePayloadDir(in: tmp, name: "p5", bytes: 1100),
            identity: "orphan-pkg",
            revision: "rev-fresh"
        )
        try store.storeArtifact(
            from: try makePayloadDir(in: tmp, name: "p6", bytes: 2000),
            identity: "orphan-bin",
            targetName: "OldSDK",
            checksum: "chk-old"
        )
        try store.storePrebuilt(
            from: try makePayloadDir(in: tmp, name: "p7", bytes: 3000),
            toolchain: oldToolchain,
            packageIdentity: "swift-syntax",
            versionOrChecksum: "510.0.0"
        )

        // Compilation cache files (old vs fresh)
        let oldCacheFile = cacheRoot.appendingPathComponent("old-cas-blob")
        let freshCacheFile = cacheRoot.appendingPathComponent("fresh-cas-blob")
        try Data(repeating: 0x01, count: 4000).write(to: oldCacheFile)
        try Data(repeating: 0x02, count: 500).write(to: freshCacheFile)

        let now = Date()
        let fortyDaysAgo = now.addingTimeInterval(-40 * 86_400)
        let fiveDaysAgo = now.addingTimeInterval(-5 * 86_400)

        // Even referenced items older than 40 days must NEVER be pruned
        let activeCheckoutURL = try store.checkoutURL(identity: "active-pkg", revision: "rev-active")
        let oldCheckoutURL = try store.checkoutURL(identity: "orphan-pkg", revision: "rev-old")
        let freshCheckoutURL = try store.checkoutURL(identity: "orphan-pkg", revision: "rev-fresh")
        let oldArtifactURL = try store.artifactURL(identity: "orphan-bin", targetName: "OldSDK", checksum: "chk-old")
        let oldPrebuiltURL = try store.prebuiltURL(toolchainHash: oldToolchain.hash, packageIdentity: "swift-syntax", versionOrChecksum: "510.0.0")

        for url in [activeCheckoutURL, oldCheckoutURL, oldArtifactURL, oldPrebuiltURL, oldCacheFile] {
            try FileManager.default.setAttributes([.modificationDate: fortyDaysAgo], ofItemAtPath: url.path)
        }
        for url in [freshCheckoutURL, freshCacheFile] {
            try FileManager.default.setAttributes([.modificationDate: fiveDaysAgo], ofItemAtPath: url.path)
        }

        let manager = StoreManager(store: store, compilationCacheURL: cacheRoot, homeDirectory: tmp)

        // 1. Dry-run prune
        let dryReport = try manager.prune(options: PruneOptions(dryRun: true, olderThanDays: 30, now: now))
        #expect(dryReport.dryRun == true)
        #expect(dryReport.removedMissingProjects == [URL(fileURLWithPath: staleWorktreePath).standardizedFileURL.path])
        #expect(dryReport.removedCheckouts == [oldCheckoutURL.path])
        #expect(dryReport.removedArtifacts == [oldArtifactURL.path])
        #expect(dryReport.removedPrebuilts == [oldPrebuiltURL.path])
        #expect(dryReport.removedCompilationCacheEntries == [oldCacheFile.path])
        #expect(dryReport.reclaimedBytes == 1000 + 2000 + 3000 + 4000)

        // Nothing removed on disk during dry-run
        #expect(FileManager.default.fileExists(atPath: oldCheckoutURL.path))
        #expect(FileManager.default.fileExists(atPath: oldArtifactURL.path))
        #expect(FileManager.default.fileExists(atPath: oldPrebuiltURL.path))
        #expect(FileManager.default.fileExists(atPath: oldCacheFile.path))
        #expect(try store.readIndex().projects.count == 2)

        // 2. Actual prune
        let actualReport = try manager.prune(options: PruneOptions(dryRun: false, olderThanDays: 30, now: now))
        #expect(actualReport.dryRun == false)
        #expect(actualReport.removedMissingProjects == dryReport.removedMissingProjects)
        #expect(actualReport.removedCheckouts == dryReport.removedCheckouts)
        #expect(actualReport.removedArtifacts == dryReport.removedArtifacts)
        #expect(actualReport.removedPrebuilts == dryReport.removedPrebuilts)
        #expect(actualReport.removedCompilationCacheEntries == dryReport.removedCompilationCacheEntries)
        #expect(actualReport.reclaimedBytes == 10_000)

        // Referenced and recent items survive; stale/old unreferenced items are gone
        #expect(FileManager.default.fileExists(atPath: activeCheckoutURL.path))
        #expect(FileManager.default.fileExists(atPath: freshCheckoutURL.path))
        #expect(FileManager.default.fileExists(atPath: freshCacheFile.path))
        #expect(!FileManager.default.fileExists(atPath: oldCheckoutURL.path))
        #expect(!FileManager.default.fileExists(atPath: oldArtifactURL.path))
        #expect(!FileManager.default.fileExists(atPath: oldPrebuiltURL.path))
        #expect(!FileManager.default.fileExists(atPath: oldCacheFile.path))

        let updatedIndex = try store.readIndex()
        #expect(updatedIndex.projects.count == 1)
        #expect(updatedIndex.projects[activeProject.standardizedFileURL.path] != nil)
    }

    // MARK: - ProjectStatusInspector

    @Test("ProjectStatusInspector reports cached vs missing pins and compilation cache status")
    func projectStatusInspectorReportsCachedVsMissingPins() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = GlobalStore(rootURL: tmp.appendingPathComponent(".pspm/store"))
        let cacheDir = tmp.appendingPathComponent(".pspm/compilation-cache")
        try store.ensureLayout()
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try Data(repeating: 0x05, count: 256).write(to: cacheDir.appendingPathComponent("cas-entry"))

        let toolchain = ToolchainFingerprint(
            swiftVersion: "Apple Swift version 6.0.3 (swiftlang-6.0.3.1.10)",
            xcodeVersion: "Xcode 16.2\nBuild version 16C5032a"
        )

        // Create an Xcode project with 2 pins (1 cached, 1 missing)
        let projectDir = tmp.appendingPathComponent("MyApp")
        let xcodeproj = projectDir.appendingPathComponent("MyApp.xcodeproj")
        let swiftpmDir = xcodeproj.appendingPathComponent("project.xcworkspace/xcshareddata/swiftpm")
        try FileManager.default.createDirectory(at: swiftpmDir, withIntermediateDirectories: true)

        try writePackageResolvedV2(
            at: swiftpmDir.appendingPathComponent("Package.resolved"),
            pins: [
                ("cached-lib", "https://github.com/org/cached-lib.git", "rev-cached", "1.2.0"),
                ("missing-lib", "https://github.com/org/missing-lib.git", "rev-missing", "2.0.0")
            ]
        )

        try store.storeCheckout(
            from: try makePayloadDir(in: tmp, name: "cached-src", bytes: 128),
            identity: "cached-lib",
            revision: "rev-cached"
        )
        try store.storePrebuilt(
            from: try makePayloadDir(in: tmp, name: "prebuilt-src", bytes: 64),
            toolchain: toolchain,
            packageIdentity: "cached-lib",
            versionOrChecksum: "1.2.0"
        )

        let inspector = ProjectStatusInspector(
            store: store,
            compilationCacheURL: cacheDir,
            homeDirectory: tmp,
            toolchainProvider: { toolchain }
        )

        let report = try inspector.inspect(in: projectDir.path, environment: [:])
        #expect(report.projectType == .xcode)
        #expect(report.rootPath == projectDir.standardizedFileURL.path)
        #expect(report.containerPath == xcodeproj.standardizedFileURL.path)
        #expect(report.toolchainHash == toolchain.hash)
        #expect(report.derivedDataPath == DerivedDataPathCalculator.derivedDataURL(forContainerPath: xcodeproj.path).standardizedFileURL.path)
        #expect(report.sourcePackagesPath.hasSuffix("/SourcePackages"))
        #expect(report.totalPins == 2)
        #expect(report.cachedPinsCount == 1)
        #expect(report.missingPins.map(\.identity) == ["missing-lib"])
        #expect(report.cachedPrebuiltsCount == 1)
        #expect(report.compilationCache.path == cacheDir.standardizedFileURL.path)
        #expect(report.compilationCache.enabled == true)
        #expect(report.compilationCache.sizeBytes == 256)

        // Verify PSPM_NO_COMPILE_CACHE=1 disables compilation cache status
        let disabledReport = try inspector.inspect(
            in: projectDir.path,
            environment: ["PSPM_NO_COMPILE_CACHE": "1"]
        )
        #expect(disabledReport.compilationCache.enabled == false)
    }

    // MARK: - DoctorDiagnostics

    @Test("DoctorDiagnostics passes when environment, APFS, CAS, PATH shims, store, and hooks are healthy")
    func doctorDiagnosticsHealthyEnvironment() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let storeRoot = tmp.appendingPathComponent(".pspm/store")
        let cacheRoot = tmp.appendingPathComponent(".pspm/compilation-cache")
        let shimsDir = tmp.appendingPathComponent(".pspm/shims")
        let usrBinDir = tmp.appendingPathComponent("usr/bin")

        let store = GlobalStore(rootURL: storeRoot)
        try store.ensureLayout()
        try store.recordToolchain(ToolchainFingerprint(swiftVersion: "Apple Swift version 6.0.3", xcodeVersion: "Xcode 16.2"))
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: shimsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: usrBinDir, withIntermediateDirectories: true)

        var executablePaths: Set<String> = []
        for tool in SetupManager.shimNames {
            executablePaths.insert(shimsDir.appendingPathComponent(tool).path)
            executablePaths.insert(usrBinDir.appendingPathComponent(tool).path)
        }
        let allowedExecs = executablePaths

        let doctor = DoctorDiagnostics(
            store: store,
            compilationCacheURL: cacheRoot,
            homeDirectory: tmp,
            workingDirectory: tmp.path,
            environment: ["PATH": "\(shimsDir.path):\(usrBinDir.path)"],
            commandRunner: { executable, _ in
                switch executable {
                case "xcodebuild":
                    return CommandResult(exitCode: 0, stdout: "Xcode 16.2\nBuild version 16C5032a\n")
                case "swift":
                    return CommandResult(exitCode: 0, stdout: "Apple Swift version 6.0.3 (swiftlang-6.0.3.1.10)\n")
                default:
                    return CommandResult(exitCode: 1, stdout: "")
                }
            },
            gitHooksManager: GitHooksManager(gitRunner: StubGitRunner(), homeDirectory: tmp),
            fileSystemTypeProvider: { _ in "apfs" },
            executableChecker: { allowedExecs.contains($0) }
        )

        let report = doctor.run()
        #expect(!report.hasFailures)
        #expect(!report.hasWarnings)
        #expect(report.checks.count == 7)
        #expect(report.checks.allSatisfy { $0.severity == .pass })
    }

    @Test("DoctorDiagnostics detects shadowed PATH order, non-APFS volume, old Swift CAS gap, puro/fvm, and corrupted store")
    func doctorDiagnosticsDetectsIssues() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let storeRoot = tmp.appendingPathComponent(".pspm/store")
        let cacheRoot = tmp.appendingPathComponent(".pspm/compilation-cache")
        let shimsDir = tmp.appendingPathComponent(".pspm/shims")
        let puroBinDir = tmp.appendingPathComponent(".puro/bin")
        let fvmDir = tmp.appendingPathComponent("fvm")

        let store = GlobalStore(rootURL: storeRoot)
        try store.ensureLayout()
        // Write corrupted index.json
        try "{ invalid-json".write(to: store.indexURL, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: shimsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: puroBinDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fvmDir, withIntermediateDirectories: true)

        var executablePaths: Set<String> = []
        for tool in SetupManager.shimNames {
            executablePaths.insert(shimsDir.appendingPathComponent(tool).path)
        }
        // puro shadows flutter before shimsDir in PATH
        executablePaths.insert(puroBinDir.appendingPathComponent("puro").path)
        executablePaths.insert(puroBinDir.appendingPathComponent("flutter").path)
        let allowedExecs = executablePaths

        let doctor = DoctorDiagnostics(
            store: store,
            compilationCacheURL: cacheRoot,
            homeDirectory: tmp,
            workingDirectory: tmp.path,
            environment: [
                "PATH": "\(puroBinDir.path):\(shimsDir.path):/usr/bin",
                "PURO_ROOT": tmp.appendingPathComponent(".puro").path
            ],
            commandRunner: { executable, _ in
                switch executable {
                case "xcodebuild":
                    return CommandResult(exitCode: 0, stdout: "Xcode 15.4\nBuild version 15F31d\n")
                case "swift":
                    return CommandResult(exitCode: 0, stdout: "Apple Swift version 5.10 (swiftlang-5.10.0.13)\n")
                default:
                    return CommandResult(exitCode: 1, stdout: "")
                }
            },
            gitHooksManager: GitHooksManager(gitRunner: StubGitRunner(), homeDirectory: tmp),
            fileSystemTypeProvider: { _ in "hfs" },
            executableChecker: { allowedExecs.contains($0) }
        )

        let report = doctor.run()
        #expect(report.hasFailures)
        #expect(report.hasWarnings)

        let apfsCheck = report.checks.first { $0.name == "APFS Filesystem" }
        #expect(apfsCheck?.severity == .warn)

        let casCheck = report.checks.first { $0.name == "Swift & Compilation Cache" }
        #expect(casCheck?.severity == .warn)

        let pathCheck = report.checks.first { $0.name == "PATH Shims Ordering" }
        #expect(pathCheck?.severity == .fail)
        #expect(pathCheck?.summary.contains("flutter") == true)

        let storeCheck = report.checks.first { $0.name == "Store & Cache Integrity" }
        #expect(storeCheck?.severity == .fail)

        let puroFvmCheck = report.checks.first { $0.name == "puro / fvm Interoperability" }
        #expect(puroFvmCheck?.severity == .warn)
        #expect(puroFvmCheck?.summary.contains("puro") == true)
        #expect(puroFvmCheck?.summary.contains("fvm") == true)
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pspm-store-doctor-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makePayloadDir(in parent: URL, name: String, bytes: Int) throws -> URL {
        let dir = parent.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: bytes).write(to: dir.appendingPathComponent("data.bin"))
        return dir
    }

    private func writePackageResolvedV2(
        at url: URL,
        pins: [(identity: String, location: String, revision: String, version: String)]
    ) throws {
        let pinDicts: [[String: Any]] = pins.map { pin in
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
        let root: [String: Any] = [
            "version": 2,
            "pins": pinDicts
        ]
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func writeWorkspaceState(
        at url: URL,
        checkoutIdentity: String,
        checkoutRevision: String,
        artifactIdentity: String,
        artifactTarget: String,
        artifactChecksum: String,
        prebuiltIdentity: String,
        prebuiltVersion: String
    ) throws {
        let root: [String: Any] = [
            "version": 7,
            "object": [
                "dependencies": [
                    [
                        "packageRef": [
                            "identity": checkoutIdentity,
                            "kind": "remoteSourceControl",
                            "location": "https://example.com/\(checkoutIdentity).git"
                        ],
                        "state": [
                            "name": "sourceControlCheckout",
                            "checkoutState": [
                                "revision": checkoutRevision,
                                "version": "1.0.0"
                            ]
                        ],
                        "subpath": checkoutIdentity
                    ]
                ],
                "artifacts": [
                    [
                        "packageRef": [
                            "identity": artifactIdentity,
                            "kind": "remoteSourceControl",
                            "location": "https://example.com/\(artifactIdentity).git"
                        ],
                        "targetName": artifactTarget,
                        "path": "/tmp/SourcePackages/artifacts/\(artifactIdentity)/\(artifactTarget)/\(artifactTarget).xcframework",
                        "source": [
                            "type": "remote",
                            "url": "https://example.com/\(artifactTarget).zip",
                            "checksum": artifactChecksum
                        ]
                    ]
                ],
                "prebuilts": [
                    [
                        "identity": prebuiltIdentity,
                        "version": prebuiltVersion,
                        "path": "/tmp/SourcePackages/prebuilts/\(prebuiltIdentity)"
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

private struct StubGitRunner: GitCommandRunning {
    func runGit(arguments: [String], workingDirectory: String?) throws -> GitCommandResult {
        GitCommandResult(exitCode: 1, stdout: "", stderr: "")
    }
}

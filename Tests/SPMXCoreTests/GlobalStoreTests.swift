import Foundation
import Testing
@testable import SPMXCore

@Suite("GlobalStore")
struct GlobalStoreTests {
    @Test("Resolves SPMX_STORE_DIR override and defaults to ~/.spmx/store")
    func resolvesStoreRootDirectory() {
        let home = URL(fileURLWithPath: "/Users/dev")

        let defaultRoot = GlobalStore.defaultRootURL(environment: [:], homeDirectory: home)
        #expect(defaultRoot.path == "/Users/dev/.spmx/store")

        let customRoot = GlobalStore.defaultRootURL(
            environment: [GlobalStore.storeDirectoryEnvironmentKey: "/tmp/custom-spmx-store/"],
            homeDirectory: home
        )
        #expect(customRoot.path == "/tmp/custom-spmx-store")

        let blankOverride = GlobalStore.defaultRootURL(
            environment: [GlobalStore.storeDirectoryEnvironmentKey: "   "],
            homeDirectory: home
        )
        #expect(blankOverride.path == "/Users/dev/.spmx/store")
    }

    @Test("Enforces exact store directory layout for checkouts, artifacts, prebuilts, and index.json")
    func enforcesStoreLayout() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let storeRoot = tmp.appendingPathComponent("store")
        let store = GlobalStore(rootURL: storeRoot)
        try store.ensureLayout()

        let checkoutPath = try store.checkoutURL(identity: "swift-argument-parser", revision: "abc123def")
        #expect(checkoutPath.path == storeRoot.appendingPathComponent("checkouts/swift-argument-parser-abc123def").path)

        let artifactPath = try store.artifactURL(
            identity: "firebase-ios-sdk",
            targetName: "FirebaseAnalytics",
            checksum: "deadbeef"
        )
        #expect(
            artifactPath.path
                == storeRoot.appendingPathComponent("artifacts/firebase-ios-sdk/FirebaseAnalytics-deadbeef").path
        )

        let prebuiltPath = try store.prebuiltURL(
            toolchainHash: "a1b2c3d4e5f60718",
            packageIdentity: "swift-syntax",
            versionOrChecksum: "600.0.1"
        )
        #expect(
            prebuiltPath.path
                == storeRoot.appendingPathComponent("prebuilts/a1b2c3d4e5f60718/swift-syntax-600.0.1").path
        )
    }

    @Test("Computes deterministic ToolchainFingerprint hashes and handles missing xcodebuild")
    func toolchainFingerprintDeterminism() throws {
        let fp1 = try ToolchainFingerprint.current { executable, _ in
            switch executable {
            case "swift":
                return CommandResult(exitCode: 0, stdout: "Apple Swift version 6.0.3 (swiftlang-6.0.3.1.10)\n")
            case "xcodebuild":
                return CommandResult(exitCode: 0, stdout: "Xcode 16.2\nBuild version 16C5032a\n")
            default:
                return CommandResult(exitCode: 1, stdout: "")
            }
        }

        let fp1Again = try ToolchainFingerprint.current { executable, _ in
            switch executable {
            case "swift":
                return CommandResult(exitCode: 0, stdout: "  Apple Swift version 6.0.3 (swiftlang-6.0.3.1.10)\r\n")
            case "xcodebuild":
                return CommandResult(exitCode: 0, stdout: "Xcode 16.2\r\nBuild version 16C5032a")
            default:
                return CommandResult(exitCode: 1, stdout: "")
            }
        }
        #expect(fp1 == fp1Again)
        #expect(fp1.hash.count == 16)

        let fp2 = try ToolchainFingerprint.current { executable, _ in
            switch executable {
            case "swift":
                return CommandResult(exitCode: 0, stdout: "Apple Swift version 6.1.0 (swiftlang-6.1.0.1.0)\n")
            case "xcodebuild":
                return CommandResult(exitCode: 0, stdout: "Xcode 16.3\nBuild version 16E140\n")
            default:
                return CommandResult(exitCode: 1, stdout: "")
            }
        }
        #expect(fp1.hash != fp2.hash)

        let cltOnly = try ToolchainFingerprint.current { executable, _ in
            switch executable {
            case "swift":
                return CommandResult(exitCode: 0, stdout: "Apple Swift version 6.0.3\n")
            default:
                return CommandResult(exitCode: 1, stdout: "", stderr: "xcode-select: error: tool 'xcodebuild' requires Xcode")
            }
        }
        #expect(cltOnly.xcodeVersion == nil)
        #expect(!cltOnly.hash.isEmpty)

        // Verify live `swift --version` works on the host.
        let real = try ToolchainFingerprint.current()
        #expect(!real.swiftVersion.isEmpty)
        #expect(real.hash.count == 16)
    }

    @Test("Partitions prebuilts by Swift/Xcode toolchain version hash")
    func partitionsPrebuiltsByToolchainVersion() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = GlobalStore(rootURL: tmp.appendingPathComponent("store"))

        let swift60 = ToolchainFingerprint(
            swiftVersion: "Apple Swift version 6.0.3",
            xcodeVersion: "Xcode 16.2"
        )
        let swift61 = ToolchainFingerprint(
            swiftVersion: "Apple Swift version 6.1.0",
            xcodeVersion: "Xcode 16.3"
        )

        let src60 = tmp.appendingPathComponent("src-60")
        let src61 = tmp.appendingPathComponent("src-61")
        try FileManager.default.createDirectory(at: src60, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: src61, withIntermediateDirectories: true)
        try "macro-abi-6.0".write(to: src60.appendingPathComponent("SwiftSyntaxMacros.o"), atomically: true, encoding: .utf8)
        try "macro-abi-6.1".write(to: src61.appendingPathComponent("SwiftSyntaxMacros.o"), atomically: true, encoding: .utf8)

        let res60 = try store.storePrebuilt(
            from: src60,
            toolchain: swift60,
            packageIdentity: "swift-syntax",
            versionOrChecksum: "600.0.1"
        )
        let res61 = try store.storePrebuilt(
            from: src61,
            toolchain: swift61,
            packageIdentity: "swift-syntax",
            versionOrChecksum: "600.0.1"
        )

        #expect(res60.storeURL != res61.storeURL)
        #expect(store.hasPrebuilt(toolchainHash: swift60.hash, packageIdentity: "swift-syntax", versionOrChecksum: "600.0.1"))
        #expect(store.hasPrebuilt(toolchainHash: swift61.hash, packageIdentity: "swift-syntax", versionOrChecksum: "600.0.1"))

        let worktreeDest60 = tmp.appendingPathComponent("wt/prebuilts/swift-syntax")
        _ = try store.clonePrebuiltToWorktree(
            toolchainHash: swift60.hash,
            packageIdentity: "swift-syntax",
            versionOrChecksum: "600.0.1",
            destinationURL: worktreeDest60
        )
        let hydrated60 = try String(contentsOf: worktreeDest60.appendingPathComponent("SwiftSyntaxMacros.o"), encoding: .utf8)
        #expect(hydrated60 == "macro-abi-6.0")

        let worktreeDest61 = tmp.appendingPathComponent("wt2/prebuilts/swift-syntax")
        _ = try store.clonePrebuiltToWorktree(
            toolchainHash: swift61.hash,
            packageIdentity: "swift-syntax",
            versionOrChecksum: "600.0.1",
            destinationURL: worktreeDest61
        )
        let hydrated61 = try String(contentsOf: worktreeDest61.appendingPathComponent("SwiftSyntaxMacros.o"), encoding: .utf8)
        #expect(hydrated61 == "macro-abi-6.1")
    }

    @Test("Persists projects, toolchains, and Flutter Package.resolved cache in index.json")
    func persistsStoreIndexMetadata() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = GlobalStore(rootURL: tmp.appendingPathComponent("store"))
        let toolchain = ToolchainFingerprint(swiftVersion: "Apple Swift version 6.0.3", xcodeVersion: "Xcode 16.2")
        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = Date(timeIntervalSince1970: 1_700_000_500)

        let projectPath = tmp.appendingPathComponent("worktrees/feature-a").path
        let first = try store.registerProject(
            at: projectPath + "/",
            toolchain: toolchain,
            packageIdentities: ["firebase-ios-sdk", "swift-syntax", "firebase-ios-sdk"],
            timestamp: t1
        )
        #expect(first.path == projectPath)
        #expect(first.registeredAt == t1)
        #expect(first.lastAccessedAt == t1)
        #expect(first.packageIdentities == ["firebase-ios-sdk", "swift-syntax"])

        let updated = try store.registerProject(
            at: projectPath,
            toolchain: toolchain,
            packageIdentities: nil,
            timestamp: t2
        )
        #expect(updated.registeredAt == t1)
        #expect(updated.lastAccessedAt == t2)
        #expect(updated.packageIdentities == ["firebase-ios-sdk", "swift-syntax"])

        let resolvedJSON = "{\"version\":2,\"pins\":[]}"
        try store.cacheFlutterPackageResolved(
            resolvedJSON,
            forDependencyHash: "flutter-deps-hash-123",
            toolchainHash: toolchain.hash,
            timestamp: t2
        )

        let cached = try store.cachedFlutterPackageResolved(forDependencyHash: "flutter-deps-hash-123")
        #expect(cached?.packageResolvedContents == resolvedJSON)
        #expect(cached?.toolchainHash == toolchain.hash)

        let index = try store.readIndex()
        #expect(index.schemaVersion == StoreIndex.currentSchemaVersion)
        #expect(index.toolchains[toolchain.hash]?.fingerprint == toolchain)
        #expect(index.projects.count == 1)
    }

    @Test("FileLock enforces timeout while held and releases cleanly on scope exit")
    func fileLockTimeoutAndRelease() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let lockURL = tmp.appendingPathComponent("locks/resource.lock")
        let holderLock = FileLock(lockFileURL: lockURL, timeout: 1.0, pollInterval: 0.01)
        let guardHandle = try holderLock.acquire()

        let contendingLock = FileLock(lockFileURL: lockURL, timeout: 0.08, pollInterval: 0.01)
        #expect(throws: FileLockError.timeout(path: lockURL.standardizedFileURL.path, timeout: 0.08)) {
            try contendingLock.withLock { }
        }

        guardHandle.release()

        let acquiredValue = try contendingLock.withLock { 42 }
        #expect(acquiredValue == 42)
    }

    @Test("Supports concurrent multi-task writes to store entries and index.json safely")
    func concurrentMultiTaskWrites() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = GlobalStore(rootURL: tmp.appendingPathComponent("store"), lockTimeout: 10.0)
        let toolchain = ToolchainFingerprint(swiftVersion: "Apple Swift version 6.0.3", xcodeVersion: "Xcode 16.2")

        // Prepare source packages on disk.
        let sharedSource = tmp.appendingPathComponent("shared-pkg")
        try FileManager.default.createDirectory(at: sharedSource, withIntermediateDirectories: true)
        try "shared-code".write(to: sharedSource.appendingPathComponent("Shared.swift"), atomically: true, encoding: .utf8)

        let uniqueCount = 16
        for index in 0..<uniqueCount {
            let src = tmp.appendingPathComponent("pkg-\(index)")
            try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
            try "pkg-\(index)".write(to: src.appendingPathComponent("File.swift"), atomically: true, encoding: .utf8)
        }

        let worktreeBase = tmp.appendingPathComponent("worktrees")
        try FileManager.default.createDirectory(at: worktreeBase, withIntermediateDirectories: true)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for idx in 0..<uniqueCount {
                let pkgSrc = tmp.appendingPathComponent("pkg-\(idx)")
                let wtPath = worktreeBase.appendingPathComponent("wt-\(idx)").path
                group.addTask {
                    // Contend on shared checkout + write unique checkout + mutate index.json concurrently.
                    _ = try store.storeCheckout(
                        from: sharedSource,
                        identity: "shared-pkg",
                        revision: "rev-001"
                    )
                    _ = try store.storeCheckout(
                        from: pkgSrc,
                        identity: "unique-pkg-\(idx)",
                        revision: "rev-\(idx)"
                    )
                    _ = try store.registerProject(
                        at: wtPath,
                        toolchain: toolchain,
                        packageIdentities: ["shared-pkg", "unique-pkg-\(idx)"]
                    )
                    try store.cacheFlutterPackageResolved(
                        "{\"id\":\(idx)}",
                        forDependencyHash: "hash-\(idx)",
                        toolchainHash: toolchain.hash
                    )
                }
            }
            try await group.waitForAll()
        }

        // Verify all 16 projects, cache entries, shared checkout, and unique checkouts survived intact.
        let index = try store.readIndex()
        #expect(index.projects.count == uniqueCount)
        #expect(index.flutterResolvedCache.count == uniqueCount)
        #expect(store.hasCheckout(identity: "shared-pkg", revision: "rev-001"))

        for idx in 0..<uniqueCount {
            #expect(store.hasCheckout(identity: "unique-pkg-\(idx)", revision: "rev-\(idx)"))
            let cachedCheckout = try store.checkoutURL(identity: "unique-pkg-\(idx)", revision: "rev-\(idx)")
            let contents = try String(contentsOf: cachedCheckout.appendingPathComponent("File.swift"), encoding: .utf8)
            #expect(contents == "pkg-\(idx)")
        }
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spmx-store-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

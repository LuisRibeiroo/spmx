import Foundation
import Testing
@testable import SPMXCore

@Suite("PackageSyncEngine")
struct PackageSyncTests {
    private static let sampleRevisionA = "f9b6f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0"
    private static let sampleRevisionB = "0687bfdc7645e9f482b6f6fb45183578a5d8e5f1"
    private static let artifactChecksum = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
    private static let prebuiltChecksum = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

    @Test("Worktree A harvest -> Worktree B offline hydrate clones checkouts, artifacts, prebuilts and rewrites workspace-state.json")
    func worktreeAToWorktreeBOfflineHydration() throws {
        let env = try TestSyncEnvironment()
        defer { env.cleanup() }

        let toolchain = ToolchainFingerprint(
            swiftVersion: "Apple Swift version 6.0.2 (swiftlang-6.0.2.1.2)",
            xcodeVersion: "Xcode 16.2\nBuild version 16C5032a"
        )
        let store = GlobalStore(rootURL: env.storeURL)
        let engine = PackageSyncEngine(store: store, toolchain: toolchain)

        // Worktree A: Xcode workspace with custom DerivedData via WorkspaceSettings.xcsettings
        let worktreeA = try env.createXcodeProject(
            name: "worktree-a",
            workspaceName: "App.xcworkspace",
            derivedDataRoot: env.derivedDataBaseURL
        )
        let spA = try engine.resolveSourcePackagesURL(for: worktreeA)
        #expect(spA.path.hasPrefix(env.derivedDataBaseURL.path))
        #expect(spA.lastPathComponent == "SourcePackages")

        try env.populateSourcePackages(
            at: spA,
            firebaseRevision: Self.sampleRevisionA,
            syntaxRevision: Self.sampleRevisionB,
            artifactChecksum: Self.artifactChecksum,
            prebuiltChecksum: Self.prebuiltChecksum,
            firebaseSourceMarker: "firebase-v11.4.0",
            syntaxSourceMarker: "syntax-v600.0.1"
        )

        let harvestResult = try engine.harvest(project: worktreeA)
        #expect(harvestResult.harvestedCheckouts.count == 2)
        #expect(harvestResult.harvestedArtifacts.count == 1)
        #expect(harvestResult.harvestedPrebuilts.count == 1)
        #expect(harvestResult.skippedItems.isEmpty)
        #expect(harvestResult.savedTemplateURL != nil)
        #expect(store.hasCheckout(identity: "firebase-ios-sdk", revision: Self.sampleRevisionA))
        #expect(store.hasCheckout(identity: "swift-syntax", revision: Self.sampleRevisionB))
        #expect(store.hasArtifact(
            identity: "firebase-ios-sdk",
            targetName: "FirebaseAnalytics",
            checksum: Self.artifactChecksum
        ))
        #expect(store.hasPrebuilt(
            toolchainHash: toolchain.hash,
            packageIdentity: "swift-syntax",
            versionOrChecksum: Self.prebuiltChecksum
        ))

        // Worktree B: fresh worktree with only Package.resolved (no SourcePackages yet)
        let worktreeB = try env.createXcodeProject(
            name: "worktree-b",
            workspaceName: "App.xcworkspace",
            derivedDataRoot: env.derivedDataBaseURL
        )
        let spB = try engine.resolveSourcePackagesURL(for: worktreeB)
        #expect(spB != spA)
        #expect(!FileManager.default.fileExists(atPath: spB.path))

        let hydrateResult = try engine.hydrate(project: worktreeB)
        #expect(hydrateResult.sourcePackagesURL == spB)
        #expect(hydrateResult.hydratedCheckouts.count == 2)
        #expect(hydrateResult.skippedCheckouts.isEmpty)
        #expect(hydrateResult.hydratedArtifacts.count == 1)
        #expect(hydrateResult.hydratedPrebuilts.count == 1)
        #expect(hydrateResult.didUpdateWorkspaceState)

        // Verify cloned files exist in Worktree B
        let firebaseCheckoutFile = spB.appendingPathComponent("checkouts/firebase-ios-sdk/Sources/Firebase.swift")
        let syntaxCheckoutFile = spB.appendingPathComponent("checkouts/swift-syntax/Sources/Syntax.swift")
        let artifactBinary = spB.appendingPathComponent("artifacts/firebase-ios-sdk/FirebaseAnalytics/FirebaseAnalytics.xcframework/Info.plist")
        let prebuiltDylib = spB.appendingPathComponent("prebuilts/swift-syntax/600.0.1/swiftlang-600/libSwiftSyntaxPrebuilt.dylib")

        #expect(try String(contentsOf: firebaseCheckoutFile, encoding: .utf8) == "firebase-v11.4.0")
        #expect(try String(contentsOf: syntaxCheckoutFile, encoding: .utf8) == "syntax-v600.0.1")
        #expect(FileManager.default.fileExists(atPath: artifactBinary.path))
        #expect(FileManager.default.fileExists(atPath: prebuiltDylib.path))

        // Verify workspace-state.json paths point to Worktree B, never Worktree A
        let wsURL = try #require(hydrateResult.workspaceStateURL)
        let wsData = try Data(contentsOf: wsURL)
        let wsText = try #require(String(data: wsData, encoding: .utf8))
        #expect(!wsText.contains(spA.path))

        let parsedWS = try WorkspaceStateParser.parse(data: wsData)
        #expect(parsedWS.artifacts.count == 1)
        #expect(parsedWS.artifacts[0].path == spB.appendingPathComponent("artifacts/firebase-ios-sdk/FirebaseAnalytics/FirebaseAnalytics.xcframework").path)
        #expect(parsedWS.prebuilts.count == 1)
        #expect(parsedWS.prebuilts[0].path == spB.appendingPathComponent("prebuilts/swift-syntax/600.0.1/swiftlang-600").path)
        #expect(parsedWS.prebuilts[0].includePaths == [
            spB.appendingPathComponent("checkouts/swift-syntax/Sources/_SwiftSyntaxCShims/include").path
        ])

        // Verify both worktrees are registered in index.json
        let index = try store.readIndex()
        let canonicalA = DerivedDataPathCalculator.canonicalizePath(worktreeA.rootPath)
        let canonicalB = DerivedDataPathCalculator.canonicalizePath(worktreeB.rootPath)
        #expect(index.projects[canonicalA] != nil)
        #expect(index.projects[canonicalB] != nil)
        #expect(index.projects[canonicalB]?.toolchainHash == toolchain.hash)
    }

    @Test("Harvest ignores .partial markers and incomplete entries missing revision or checksum")
    func harvestSkipsPartialAndIncompleteEntries() throws {
        let env = try TestSyncEnvironment()
        defer { env.cleanup() }

        let toolchain = ToolchainFingerprint(swiftVersion: "Apple Swift version 6.0", xcodeVersion: "Xcode 16.0")
        let store = GlobalStore(rootURL: env.storeURL)
        let engine = PackageSyncEngine(store: store, toolchain: toolchain)

        let project = try env.createSwiftPackageProject(name: "swift-pkg-partial")
        let buildDir = try engine.resolveSourcePackagesURL(for: project)

        try env.populateSourcePackages(
            at: buildDir,
            firebaseRevision: Self.sampleRevisionA,
            syntaxRevision: Self.sampleRevisionB,
            artifactChecksum: Self.artifactChecksum,
            prebuiltChecksum: Self.prebuiltChecksum
        )

        // Add .partial marker inside swift-syntax checkout
        let syntaxPartial = buildDir.appendingPathComponent("checkouts/swift-syntax/.partial")
        try Data("in-progress".utf8).write(to: syntaxPartial)

        // Add sibling .partial checkout directory
        let incompleteCheckout = buildDir.appendingPathComponent("checkouts/downloading-pkg.partial")
        try FileManager.default.createDirectory(at: incompleteCheckout, withIntermediateDirectories: true)
        try Data("tmp".utf8).write(to: incompleteCheckout.appendingPathComponent("file.swift"))

        // Add checkout with no revision in Package.resolved or workspace-state.json
        let orphanCheckout = buildDir.appendingPathComponent("checkouts/unknown-pkg")
        try FileManager.default.createDirectory(at: orphanCheckout, withIntermediateDirectories: true)
        try Data("// orphan".utf8).write(to: orphanCheckout.appendingPathComponent("Orphan.swift"))

        // Add incomplete artifact (missing checksum) and partial prebuilt (.partial marker)
        let extraArtifactDir = buildDir.appendingPathComponent("artifacts/local-sdk/LocalBin/LocalBin.xcframework")
        try FileManager.default.createDirectory(at: extraArtifactDir, withIntermediateDirectories: true)
        try Data("bin".utf8).write(to: extraArtifactDir.appendingPathComponent("bin"))

        let partialPrebuiltDir = buildDir.appendingPathComponent("prebuilts/broken-macro/1.0.0")
        try FileManager.default.createDirectory(at: partialPrebuiltDir, withIntermediateDirectories: true)
        try Data("dylib".utf8).write(to: partialPrebuiltDir.appendingPathComponent("lib.dylib"))
        try Data().write(to: partialPrebuiltDir.appendingPathComponent("download.partial"))

        let wsURL = buildDir.appendingPathComponent("workspace-state.json")
        let wsJSON: [String: Any] = [
            "version": 7,
            "object": [
                "dependencies": [
                    [
                        "packageRef": [
                            "identity": "firebase-ios-sdk",
                            "kind": "remoteSourceControl",
                            "location": "https://github.com/firebase/firebase-ios-sdk.git"
                        ],
                        "state": [
                            "checkoutState": [
                                "revision": Self.sampleRevisionA,
                                "version": "11.4.0"
                            ],
                            "name": "sourceControlCheckout"
                        ],
                        "subpath": "firebase-ios-sdk"
                    ],
                    [
                        "packageRef": [
                            "identity": "swift-syntax",
                            "kind": "remoteSourceControl",
                            "location": "https://github.com/swiftlang/swift-syntax.git"
                        ],
                        "state": [
                            "checkoutState": [
                                "revision": Self.sampleRevisionB,
                                "version": "600.0.1"
                            ],
                            "name": "sourceControlCheckout"
                        ],
                        "subpath": "swift-syntax"
                    ]
                ],
                "artifacts": [
                    [
                        "kind": "xcframework",
                        "packageRef": [
                            "identity": "firebase-ios-sdk",
                            "kind": "remoteSourceControl",
                            "location": "https://github.com/firebase/firebase-ios-sdk.git"
                        ],
                        "path": buildDir.appendingPathComponent("artifacts/firebase-ios-sdk/FirebaseAnalytics/FirebaseAnalytics.xcframework").path,
                        "source": [
                            "type": "remote",
                            "url": "https://example.com/FirebaseAnalytics.zip",
                            "checksum": Self.artifactChecksum
                        ],
                        "targetName": "FirebaseAnalytics"
                    ],
                    [
                        "kind": "xcframework",
                        "packageRef": [
                            "identity": "local-sdk",
                            "kind": "localSourceControl",
                            "location": "/tmp/LocalSDK"
                        ],
                        "path": extraArtifactDir.path,
                        "source": [
                            "type": "local"
                        ],
                        "targetName": "LocalBin"
                    ]
                ],
                "prebuilts": [
                    [
                        "identity": "swift-syntax",
                        "version": "600.0.1",
                        "checksum": Self.prebuiltChecksum,
                        "checkoutState": [
                            "revision": Self.sampleRevisionB,
                            "version": "600.0.1"
                        ],
                        "path": buildDir.appendingPathComponent("prebuilts/swift-syntax/600.0.1/swiftlang-600").path
                    ],
                    [
                        "identity": "broken-macro",
                        "version": "1.0.0",
                        "checksum": "abcd1234",
                        "path": partialPrebuiltDir.path
                    ],
                    [
                        "identity": "incomplete-macro",
                        "path": buildDir.appendingPathComponent("prebuilts/incomplete-macro").path
                    ]
                ]
            ]
        ]
        let wsData = try JSONSerialization.data(withJSONObject: wsJSON, options: [.prettyPrinted])
        try wsData.write(to: wsURL)

        let result = try engine.harvest(project: project)

        // Only valid entries were stored
        #expect(result.harvestedCheckouts.map(\.identity) == ["firebase-ios-sdk"])
        #expect(result.harvestedArtifacts.map(\.targetName) == ["FirebaseAnalytics"])
        #expect(result.harvestedPrebuilts.map(\.identity) == ["swift-syntax"])

        #expect(store.hasCheckout(identity: "firebase-ios-sdk", revision: Self.sampleRevisionA))
        #expect(!store.hasCheckout(identity: "swift-syntax", revision: Self.sampleRevisionB))
        #expect(!store.hasPrebuilt(toolchainHash: toolchain.hash, packageIdentity: "broken-macro", versionOrChecksum: "abcd1234"))

        #expect(result.skippedItems.contains { $0.kind == "checkout" && $0.identifier == "swift-syntax" })
        #expect(result.skippedItems.contains { $0.kind == "checkout" && $0.identifier == "downloading-pkg.partial" })
        #expect(result.skippedItems.contains { $0.kind == "checkout" && $0.identifier == "unknown-pkg" })
        #expect(result.skippedItems.contains { $0.kind == "artifact" && $0.identifier == "local-sdk/LocalBin" })
        #expect(result.skippedItems.contains { $0.kind == "prebuilt" && $0.identifier == "broken-macro" })
        #expect(result.skippedItems.contains { $0.kind == "prebuilt" && $0.identifier == "incomplete-macro" })
    }

    @Test("Hydrate preserves locally modified checkouts unless --force is passed")
    func hydratePreservesModifiedCheckoutsWithoutForce() throws {
        let env = try TestSyncEnvironment()
        defer { env.cleanup() }

        let toolchain = ToolchainFingerprint(swiftVersion: "Apple Swift version 6.0", xcodeVersion: "Xcode 16.0")
        let store = GlobalStore(rootURL: env.storeURL)
        let engine = PackageSyncEngine(store: store, toolchain: toolchain)

        // Seed store from Worktree A
        let worktreeA = try env.createSwiftPackageProject(name: "wt-a")
        let buildA = try engine.resolveSourcePackagesURL(for: worktreeA)
        try env.populateSourcePackages(
            at: buildA,
            firebaseRevision: Self.sampleRevisionA,
            syntaxRevision: Self.sampleRevisionB,
            artifactChecksum: Self.artifactChecksum,
            prebuiltChecksum: Self.prebuiltChecksum,
            firebaseSourceMarker: "clean-store-firebase",
            syntaxSourceMarker: "clean-store-syntax"
        )
        _ = try engine.harvest(project: worktreeA)

        // Prepare Worktree B with:
        // 1) A locally modified git checkout for firebase-ios-sdk
        // 2) An existing non-empty checkout for swift-syntax (no .git)
        let worktreeB = try env.createSwiftPackageProject(name: "wt-b")
        let buildB = try engine.resolveSourcePackagesURL(for: worktreeB)

        let firebaseDest = buildB.appendingPathComponent("checkouts/firebase-ios-sdk")
        let firebaseFile = firebaseDest.appendingPathComponent("Sources/Firebase.swift")
        try FileManager.default.createDirectory(at: firebaseFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("committed".utf8).write(to: firebaseFile)
        try env.runGit(["init"], in: firebaseDest)
        try env.runGit(["config", "user.email", "test@example.com"], in: firebaseDest)
        try env.runGit(["config", "user.name", "Tester"], in: firebaseDest)
        try env.runGit(["add", "."], in: firebaseDest)
        try env.runGit(["commit", "-m", "initial"], in: firebaseDest)
        try Data("user-local-modification".utf8).write(to: firebaseFile)

        let syntaxDest = buildB.appendingPathComponent("checkouts/swift-syntax")
        let syntaxFile = syntaxDest.appendingPathComponent("Sources/Syntax.swift")
        try FileManager.default.createDirectory(at: syntaxFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("user-plain-modification".utf8).write(to: syntaxFile)

        // Hydrate without --force -> both modified checkouts must be preserved
        let safeResult = try engine.hydrate(project: worktreeB, options: HydrateOptions(force: false))
        #expect(safeResult.hydratedCheckouts.isEmpty)
        #expect(safeResult.skippedCheckouts.count == 2)

        let skippedFirebase = try #require(safeResult.skippedCheckouts.first { $0.identity == "firebase-ios-sdk" })
        #expect(skippedFirebase.reason == .locallyModified)
        let skippedSyntax = try #require(safeResult.skippedCheckouts.first { $0.identity == "swift-syntax" })
        #expect(skippedSyntax.reason == .alreadyExists)

        #expect(try String(contentsOf: firebaseFile, encoding: .utf8) == "user-local-modification")
        #expect(try String(contentsOf: syntaxFile, encoding: .utf8) == "user-plain-modification")

        // Hydrate with --force -> both checkouts are overwritten from store
        let forcedResult = try engine.hydrate(project: worktreeB, options: HydrateOptions(force: true))
        #expect(forcedResult.hydratedCheckouts.count == 2)
        #expect(forcedResult.skippedCheckouts.isEmpty)
        #expect(try String(contentsOf: firebaseFile, encoding: .utf8) == "clean-store-firebase")
        #expect(try String(contentsOf: syntaxFile, encoding: .utf8) == "clean-store-syntax")
    }

    @Test("Pure SwiftPM .build/ harvest and hydrate plus toolchain isolation for prebuilts")
    func pureSwiftPMAndToolchainIsolation() throws {
        let env = try TestSyncEnvironment()
        defer { env.cleanup() }

        let toolchain60 = ToolchainFingerprint(swiftVersion: "Apple Swift version 6.0", xcodeVersion: "Xcode 16.0")
        let toolchain61 = ToolchainFingerprint(swiftVersion: "Apple Swift version 6.1", xcodeVersion: "Xcode 16.3")

        let store = GlobalStore(rootURL: env.storeURL)
        let engine60 = PackageSyncEngine(store: store, toolchain: toolchain60)
        let engine61 = PackageSyncEngine(store: store, toolchain: toolchain61)

        // Worktree A (SwiftPM .build/)
        let pkgA = try env.createSwiftPackageProject(name: "spm-a")
        let buildA = try engine60.resolveSourcePackagesURL(for: pkgA)
        #expect(buildA.lastPathComponent == ".build")

        try env.populateSourcePackages(
            at: buildA,
            firebaseRevision: Self.sampleRevisionA,
            syntaxRevision: Self.sampleRevisionB,
            artifactChecksum: Self.artifactChecksum,
            prebuiltChecksum: Self.prebuiltChecksum
        )
        _ = try engine60.harvest(project: pkgA)

        // Worktree B (SwiftPM .build/) on same toolchain 6.0
        let pkgB = try env.createSwiftPackageProject(name: "spm-b")
        let buildB = try engine60.resolveSourcePackagesURL(for: pkgB)
        let hydrate60 = try engine60.hydrate(project: pkgB)

        #expect(hydrate60.hydratedCheckouts.count == 2)
        #expect(hydrate60.hydratedArtifacts.count == 1)
        #expect(hydrate60.hydratedPrebuilts.count == 1)
        #expect(FileManager.default.fileExists(atPath: buildB.appendingPathComponent("checkouts/firebase-ios-sdk/Sources/Firebase.swift").path))
        #expect(FileManager.default.fileExists(atPath: buildB.appendingPathComponent("artifacts/firebase-ios-sdk/FirebaseAnalytics/FirebaseAnalytics.xcframework/Info.plist").path))
        #expect(FileManager.default.fileExists(atPath: buildB.appendingPathComponent("prebuilts/swift-syntax/600.0.1/swiftlang-600/libSwiftSyntaxPrebuilt.dylib").path))

        let wsB = try WorkspaceStateParser.parse(fileAt: buildB.appendingPathComponent("workspace-state.json").path)
        #expect(wsB.artifacts.first?.path == buildB.appendingPathComponent("artifacts/firebase-ios-sdk/FirebaseAnalytics/FirebaseAnalytics.xcframework").path)
        #expect(wsB.prebuilts.first?.path == buildB.appendingPathComponent("prebuilts/swift-syntax/600.0.1/swiftlang-600").path)

        // Worktree C (SwiftPM .build/) on different toolchain 6.1 -> checkouts & artifacts hydrate, prebuilts do NOT
        let pkgC = try env.createSwiftPackageProject(name: "spm-c")
        let buildC = try engine61.resolveSourcePackagesURL(for: pkgC)
        let hydrate61 = try engine61.hydrate(project: pkgC)

        #expect(hydrate61.hydratedCheckouts.count == 2)
        #expect(hydrate61.hydratedArtifacts.count == 1)
        #expect(hydrate61.hydratedPrebuilts.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: buildC.appendingPathComponent("prebuilts/swift-syntax/600.0.1/swiftlang-600").path))

        let wsC = try WorkspaceStateParser.parse(fileAt: buildC.appendingPathComponent("workspace-state.json").path)
        #expect(wsC.artifacts.count == 1)
        #expect(wsC.prebuilts.isEmpty)
    }
}

// MARK: - Test Fixture Helpers

private struct TestSyncEnvironment {
    let rootURL: URL
    let storeURL: URL
    let derivedDataBaseURL: URL
    private let fileManager = FileManager.default

    init() throws {
        rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("spmx-sync-tests-\(UUID().uuidString)")
        storeURL = rootURL.appendingPathComponent("store")
        derivedDataBaseURL = rootURL.appendingPathComponent("DerivedData")
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: derivedDataBaseURL, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? fileManager.removeItem(at: rootURL)
    }

    func createXcodeProject(
        name: String,
        workspaceName: String,
        derivedDataRoot: URL
    ) throws -> DetectedProject {
        let projectDir = rootURL.appendingPathComponent(name)
        let workspaceDir = projectDir.appendingPathComponent(workspaceName)
        let xcshareddata = workspaceDir.appendingPathComponent("xcshareddata")
        let swiftpmDir = xcshareddata.appendingPathComponent("swiftpm")

        try fileManager.createDirectory(at: swiftpmDir, withIntermediateDirectories: true)
        try Data("<Workspace version = \"1.0\"></Workspace>".utf8)
            .write(to: workspaceDir.appendingPathComponent("contents.xcworkspacedata"))

        // Configure deterministic custom DerivedData location inside WorkspaceSettings.xcsettings
        let settingsPlist: [String: Any] = [
            "DerivedDataLocation": derivedDataRoot.path
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: settingsPlist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: xcshareddata.appendingPathComponent("WorkspaceSettings.xcsettings"))

        try writeSamplePackageResolved(to: swiftpmDir.appendingPathComponent("Package.resolved"))
        return try ProjectDetector.detect(in: projectDir.path)
    }

    func createSwiftPackageProject(name: String) throws -> DetectedProject {
        let projectDir = rootURL.appendingPathComponent(name)
        try fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let manifest = """
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(name: "\(name)", targets: [])
        """
        try Data(manifest.utf8).write(to: projectDir.appendingPathComponent("Package.swift"))
        try writeSamplePackageResolved(to: projectDir.appendingPathComponent("Package.resolved"))
        return try ProjectDetector.detect(in: projectDir.path)
    }

    func writeSamplePackageResolved(to url: URL) throws {
        let json = """
        {
          "originHash" : "deadbeef",
          "pins" : [
            {
              "identity" : "firebase-ios-sdk",
              "kind" : "remoteSourceControl",
              "location" : "https://github.com/firebase/firebase-ios-sdk.git",
              "state" : {
                "revision" : "f9b6f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0",
                "version" : "11.4.0"
              }
            },
            {
              "identity" : "swift-syntax",
              "kind" : "remoteSourceControl",
              "location" : "https://github.com/swiftlang/swift-syntax.git",
              "state" : {
                "revision" : "0687bfdc7645e9f482b6f6fb45183578a5d8e5f1",
                "version" : "600.0.1"
              }
            }
          ],
          "version" : 3
        }
        """
        try Data(json.utf8).write(to: url)
    }

    func populateSourcePackages(
        at sourcePackagesURL: URL,
        firebaseRevision: String,
        syntaxRevision: String,
        artifactChecksum: String,
        prebuiltChecksum: String,
        firebaseSourceMarker: String = "firebase-source",
        syntaxSourceMarker: String = "syntax-source"
    ) throws {
        let firebaseFile = sourcePackagesURL.appendingPathComponent("checkouts/firebase-ios-sdk/Sources/Firebase.swift")
        let syntaxFile = sourcePackagesURL.appendingPathComponent("checkouts/swift-syntax/Sources/Syntax.swift")
        let syntaxInclude = sourcePackagesURL.appendingPathComponent("checkouts/swift-syntax/Sources/_SwiftSyntaxCShims/include/shims.h")
        let artifactInfo = sourcePackagesURL.appendingPathComponent("artifacts/firebase-ios-sdk/FirebaseAnalytics/FirebaseAnalytics.xcframework/Info.plist")
        let prebuiltDylib = sourcePackagesURL.appendingPathComponent("prebuilts/swift-syntax/600.0.1/swiftlang-600/libSwiftSyntaxPrebuilt.dylib")

        for fileURL in [firebaseFile, syntaxFile, syntaxInclude, artifactInfo, prebuiltDylib] {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        }

        try Data(firebaseSourceMarker.utf8).write(to: firebaseFile)
        try Data(syntaxSourceMarker.utf8).write(to: syntaxFile)
        try Data("#define SHIM 1\n".utf8).write(to: syntaxInclude)
        try Data("<plist/>".utf8).write(to: artifactInfo)
        try Data("dylib-bytes".utf8).write(to: prebuiltDylib)

        let artifactPath = sourcePackagesURL
            .appendingPathComponent("artifacts/firebase-ios-sdk/FirebaseAnalytics/FirebaseAnalytics.xcframework")
            .path
        let prebuiltPath = sourcePackagesURL
            .appendingPathComponent("prebuilts/swift-syntax/600.0.1/swiftlang-600")
            .path
        let includePath = sourcePackagesURL
            .appendingPathComponent("checkouts/swift-syntax/Sources/_SwiftSyntaxCShims/include")
            .path

        let wsJSON: [String: Any] = [
            "version": 7,
            "object": [
                "artifacts": [
                    [
                        "kind": ["xcframework": [:]],
                        "packageRef": [
                            "identity": "firebase-ios-sdk",
                            "kind": "remoteSourceControl",
                            "location": "https://github.com/firebase/firebase-ios-sdk.git",
                            "name": "Firebase"
                        ],
                        "path": artifactPath,
                        "source": [
                            "checksum": artifactChecksum,
                            "type": "remote",
                            "url": "https://dl.google.com/firebase/ios/swiftpm/11.4.0/FirebaseAnalytics.zip"
                        ],
                        "targetName": "FirebaseAnalytics"
                    ]
                ],
                "dependencies": [
                    [
                        "basedOn": NSNull(),
                        "packageRef": [
                            "identity": "firebase-ios-sdk",
                            "kind": "remoteSourceControl",
                            "location": "https://github.com/firebase/firebase-ios-sdk.git",
                            "name": "Firebase"
                        ],
                        "state": [
                            "checkoutState": [
                                "revision": firebaseRevision,
                                "version": "11.4.0"
                            ],
                            "name": "sourceControlCheckout"
                        ],
                        "subpath": "firebase-ios-sdk"
                    ],
                    [
                        "basedOn": NSNull(),
                        "packageRef": [
                            "identity": "swift-syntax",
                            "kind": "remoteSourceControl",
                            "location": "https://github.com/swiftlang/swift-syntax.git",
                            "name": "swift-syntax"
                        ],
                        "state": [
                            "checkoutState": [
                                "revision": syntaxRevision,
                                "version": "600.0.1"
                            ],
                            "name": "sourceControlCheckout"
                        ],
                        "subpath": "swift-syntax"
                    ]
                ],
                "prebuilts": [
                    [
                        "cModules": ["_SwiftSyntaxCShims"],
                        "checksum": prebuiltChecksum,
                        "checkoutState": [
                            "revision": syntaxRevision,
                            "version": "600.0.1"
                        ],
                        "identity": "swift-syntax",
                        "includePath": [includePath],
                        "libraryName": "libSwiftSyntaxPrebuilt.dylib",
                        "path": prebuiltPath,
                        "products": ["SwiftSyntax", "SwiftSyntaxMacros"]
                    ]
                ]
            ]
        ]

        let wsData = try JSONSerialization.data(withJSONObject: wsJSON, options: [.prettyPrinted, .sortedKeys])
        try wsData.write(to: sourcePackagesURL.appendingPathComponent("workspace-state.json"))
    }

    func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw SyncError.ioFailed(
                operation: "run git \(arguments.joined(separator: " "))",
                path: directory.path,
                message: "exit code \(process.terminationStatus)"
            )
        }
    }
}

import Foundation
import Testing
@testable import SPMXCore

@Suite("FlutterSPMIntegrator")
struct FlutterSPMIntegratorTests {
    // MARK: - Helpers

    private struct Invocation: Equatable, Sendable {
        let executablePath: String
        let arguments: [String]
        let workingDirectory: String
        let environment: [String: String]
    }

    private final class MockFlutterCommandRunner: FlutterCommandRunning, @unchecked Sendable {
        private let lock = NSLock()
        private var recordedInvocations: [Invocation] = []
        private let handler: @Sendable (Invocation) throws -> CommandResult

        init(handler: @escaping @Sendable (Invocation) throws -> CommandResult) {
            self.handler = handler
        }

        var invocations: [Invocation] {
            lock.lock()
            defer { lock.unlock() }
            return recordedInvocations
        }

        func run(
            executablePath: String,
            arguments: [String],
            workingDirectory: String,
            environment: [String: String]
        ) throws -> CommandResult {
            let invocation = Invocation(
                executablePath: executablePath,
                arguments: arguments,
                workingDirectory: workingDirectory,
                environment: environment
            )
            lock.lock()
            recordedInvocations.append(invocation)
            lock.unlock()
            return try handler(invocation)
        }
    }

    private struct MockExecutableResolver: FlutterExecutableResolving, Sendable {
        let resolvedPath: String

        func resolveFlutterExecutable(environment: [String: String]) throws -> String {
            resolvedPath
        }

        func sanitizedEnvironment(from environment: [String: String]) -> [String: String] {
            var copy = environment
            copy[FlutterExecutableResolver.flutterShimActiveEnvironmentKey] = "1"
            return copy
        }
    }

    private func makeTempDir() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath()
            .appendingPathComponent("spmx-flutter-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func makeExecutableFile(at url: URL, contents: String = "#!/bin/sh\nexit 0\n") throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }

    private func createFlutterWorkspaceScaffold(
        at root: URL,
        platforms: [FlutterPlatform] = [.ios, .macos]
    ) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try """
        name: multiplatform_flutter_app
        environment:
          sdk: ">=3.5.0 <4.0.0"
        dependencies:
          flutter:
            sdk: flutter
          firebase_core: ^3.6.0
          shared_preferences: ^2.3.0
        """.write(
            to: root.appendingPathComponent("pubspec.yaml"),
            atomically: true,
            encoding: .utf8
        )

        for platform in platforms {
            let workspaceDir = root
                .appendingPathComponent(platform.rawValue)
                .appendingPathComponent("Runner.xcworkspace")
            try FileManager.default.createDirectory(at: workspaceDir, withIntermediateDirectories: true)
            try """
            <?xml version="1.0" encoding="UTF-8"?>
            <Workspace version="1.0">
               <FileRef location="group:Runner.xcodeproj"/>
            </Workspace>
            """.write(
                to: workspaceDir.appendingPathComponent("contents.xcworkspacedata"),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    private static func writeFlutterGeneratedMetadata(
        in root: URL,
        platforms: [FlutterPlatform] = [.ios, .macos],
        dateCreated: String = "2026-11-15 00:00:00.000000",
        iosExtraPlugin: String? = nil
    ) throws {
        var iosPlugins: [[String: Any]] = [
            [
                "name": "firebase_core",
                "path": "/Users/dev/.pub-cache/hosted/pub.dev/firebase_core-3.6.0/",
                "native_build": true,
                "shared_darwin_source": false
            ],
            [
                "name": "shared_preferences_foundation",
                "path": "/Users/dev/.pub-cache/hosted/pub.dev/shared_preferences_foundation-2.4.0/",
                "native_build": true,
                "shared_darwin_source": true
            ]
        ]
        if let iosExtraPlugin {
            iosPlugins.append([
                "name": iosExtraPlugin,
                "path": "/Users/dev/.pub-cache/hosted/pub.dev/\(iosExtraPlugin)-1.0.0/",
                "native_build": true,
                "shared_darwin_source": false
            ])
        }

        let macosPlugins: [[String: Any]] = [
            [
                "name": "shared_preferences_foundation",
                "path": "/Users/dev/.pub-cache/hosted/pub.dev/shared_preferences_foundation-2.4.0/",
                "native_build": true,
                "shared_darwin_source": true
            ]
        ]

        var pluginsMap: [String: Any] = [:]
        if platforms.contains(.ios) {
            pluginsMap["ios"] = iosPlugins
        }
        if platforms.contains(.macos) {
            pluginsMap["macos"] = macosPlugins
        }

        let depsObject: [String: Any] = [
            "info": "This is a generated file; do not edit or check into version control.",
            "plugins": pluginsMap,
            "date_created": dateCreated
        ]
        let depsData = try JSONSerialization.data(
            withJSONObject: depsObject,
            options: [.prettyPrinted, .sortedKeys]
        )
        try depsData.write(to: root.appendingPathComponent(".flutter-plugins-dependencies"))

        for platform in platforms {
            let generatedPkgDir = root
                .appendingPathComponent(platform.rawValue)
                .appendingPathComponent("Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage")
            try FileManager.default.createDirectory(at: generatedPkgDir, withIntermediateDirectories: true)

            let targetDeps: String
            if platform == .ios {
                let extraDep = iosExtraPlugin.map { ",\n        .package(name: \"\($0)\", path: \"/Users/dev/.pub-cache/\($0)\")" } ?? ""
                targetDeps = """
                // swift-tools-version: 5.9
                import PackageDescription
                let package = Package(
                    name: "FlutterGeneratedPluginSwiftPackage",
                    platforms: [.iOS("13.0")],
                    products: [.library(name: "FlutterGeneratedPluginSwiftPackage", type: .static, targets: ["FlutterGeneratedPluginSwiftPackage"])],
                    dependencies: [
                        .package(name: "firebase_core", path: "/Users/dev/.pub-cache/firebase_core"),
                        .package(name: "shared_preferences_foundation", path: "/Users/dev/.pub-cache/shared_preferences_foundation")\(extraDep)
                    ],
                    targets: [.target(name: "FlutterGeneratedPluginSwiftPackage")]
                )
                """
            } else {
                targetDeps = """
                // swift-tools-version: 5.9
                import PackageDescription
                let package = Package(
                    name: "FlutterGeneratedPluginSwiftPackage",
                    platforms: [.macOS("10.15")],
                    products: [.library(name: "FlutterGeneratedPluginSwiftPackage", type: .static, targets: ["FlutterGeneratedPluginSwiftPackage"])],
                    dependencies: [
                        .package(name: "shared_preferences_foundation", path: "/Users/dev/.pub-cache/shared_preferences_foundation")
                    ],
                    targets: [.target(name: "FlutterGeneratedPluginSwiftPackage")]
                )
                """
            }

            try targetDeps.write(
                to: generatedPkgDir.appendingPathComponent("Package.swift"),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    private func samplePackageResolved(pins: [(identity: String, location: String, revision: String, version: String)]) -> String {
        let pinEntries = pins.map { pin in
            """
                {
                  "identity" : "\(pin.identity)",
                  "kind" : "remoteSourceControl",
                  "location" : "\(pin.location)",
                  "state" : {
                    "revision" : "\(pin.revision)",
                    "version" : "\(pin.version)"
                  }
                }
            """
        }.joined(separator: ",\n")

        return """
        {
          "pins" : [
        \(pinEntries)
          ],
          "version" : 2
        }
        """
    }

    // MARK: - PATH / Shim Resolution Tests

    @Test("FlutterExecutableResolver skips ~/.spmx/shims, SPMX_SHIMS_DIR, and spmx symlinks")
    func resolvesRealFlutterExcludingShims() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let fakeHome = tmp.appendingPathComponent("home")
        let defaultShims = fakeHome.appendingPathComponent(".spmx/shims")
        let customShims = tmp.appendingPathComponent("custom-shims")
        let sneakyDir = tmp.appendingPathComponent("sneaky-bin")
        let realSpmxBin = fakeHome.appendingPathComponent(".spmx/bin/spmx")
        let realFlutterDir = tmp.appendingPathComponent("fvm/default/bin")
        let realFlutter = realFlutterDir.appendingPathComponent("flutter")

        try makeExecutableFile(at: defaultShims.appendingPathComponent("flutter"))
        try makeExecutableFile(at: customShims.appendingPathComponent("flutter"))
        try makeExecutableFile(at: realSpmxBin)
        try FileManager.default.createDirectory(at: sneakyDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: sneakyDir.appendingPathComponent("flutter"),
            withDestinationURL: realSpmxBin
        )
        try makeExecutableFile(at: realFlutter)

        let env: [String: String] = [
            "PATH": [
                defaultShims.path,
                customShims.path,
                sneakyDir.path,
                realFlutterDir.path,
                "/usr/bin"
            ].joined(separator: ":"),
            FlutterExecutableResolver.shimsDirectoryEnvironmentKey: customShims.path
        ]

        let resolver = FlutterExecutableResolver(homeDirectory: fakeHome)
        let resolved = try resolver.resolveFlutterExecutable(environment: env)
        #expect(resolved == realFlutter.path)

        let sanitized = resolver.sanitizedEnvironment(from: env)
        #expect(sanitized[FlutterExecutableResolver.flutterShimActiveEnvironmentKey] == "1")
        let sanitizedPathParts = (sanitized["PATH"] ?? "").split(separator: ":").map(String.init)
        #expect(!sanitizedPathParts.contains(defaultShims.path))
        #expect(!sanitizedPathParts.contains(customShims.path))
        #expect(sanitizedPathParts.contains(realFlutterDir.path))
    }

    @Test("FlutterExecutableResolver throws when only spmx shim exists on PATH")
    func throwsWhenOnlyShimsExist() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let fakeHome = tmp.appendingPathComponent("home")
        let defaultShims = fakeHome.appendingPathComponent(".spmx/shims")
        try makeExecutableFile(at: defaultShims.appendingPathComponent("flutter"))

        let resolver = FlutterExecutableResolver(homeDirectory: fakeHome)
        #expect(throws: FlutterSPMIntegratorError.self) {
            try resolver.resolveFlutterExecutable(environment: ["PATH": defaultShims.path])
        }
    }

    // MARK: - Clean Worktree & Multiplatform Hydration Tests

    @Test("Clean worktree without ephemeral triggers real flutter pub get with SPMX_FLUTTER_SHIM_ACTIVE=1 and shims stripped")
    func cleanWorktreeTriggersRealFlutterPubGet() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let fakeHome = tmp.appendingPathComponent("home")
        let defaultShims = fakeHome.appendingPathComponent(".spmx/shims")
        let customShims = tmp.appendingPathComponent("custom-shims")
        let realFlutterDir = tmp.appendingPathComponent("puro/envs/stable/flutter/bin")
        let realFlutter = realFlutterDir.appendingPathComponent("flutter")
        try makeExecutableFile(at: defaultShims.appendingPathComponent("flutter"))
        try makeExecutableFile(at: customShims.appendingPathComponent("flutter"))
        try makeExecutableFile(at: realFlutter)

        let worktree = tmp.appendingPathComponent("worktree-clean")
        try createFlutterWorkspaceScaffold(at: worktree, platforms: [.ios, .macos])

        let store = GlobalStore(rootURL: tmp.appendingPathComponent("store"))
        let resolver = FlutterExecutableResolver(homeDirectory: fakeHome)
        let runner = MockFlutterCommandRunner { invocation in
            let worktreeURL = URL(fileURLWithPath: invocation.workingDirectory)
            try Self.writeFlutterGeneratedMetadata(in: worktreeURL, platforms: [.ios, .macos])
            return CommandResult(exitCode: 0, stdout: "Got dependencies!\n")
        }

        let integrator = FlutterSPMIntegrator(
            store: store,
            executableResolver: resolver,
            commandRunner: runner
        )

        let initialProject = try ProjectDetector.detect(in: worktree.path)
        #expect(integrator.isFlutterSPMProject(initialProject))
        #expect(initialProject.flutterInfo?.hasGeneratedSwiftPackage == false)

        let env: [String: String] = [
            "PATH": "\(defaultShims.path):\(customShims.path):\(realFlutterDir.path)",
            FlutterExecutableResolver.shimsDirectoryEnvironmentKey: customShims.path
        ]

        let result = try integrator.prepareForHydration(
            project: initialProject,
            runPubGetIfMissing: true,
            environment: env
        )

        #expect(result.didRunPubGet == true)
        #expect(result.executedFlutterPath == realFlutter.path)
        #expect(result.project.flutterInfo?.hasGeneratedSwiftPackage == true)
        #expect(result.dependencyHashes[.ios] != nil)
        #expect(result.dependencyHashes[.macos] != nil)

        #expect(runner.invocations.count == 1)
        let invocation = try #require(runner.invocations.first)
        #expect(invocation.executablePath == realFlutter.path)
        #expect(invocation.arguments == ["pub", "get"])
        #expect(invocation.workingDirectory == worktree.path)
        #expect(invocation.environment[FlutterExecutableResolver.flutterShimActiveEnvironmentKey] == "1")
        let childPathEntries = (invocation.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        #expect(!childPathEntries.contains(defaultShims.path))
        #expect(!childPathEntries.contains(customShims.path))
        #expect(childPathEntries.contains(realFlutterDir.path))
    }

    @Test("Caches Package.resolved in Worktree A and restores both ios and macos in clean Worktree B")
    func cachesInWorktreeAAndRestoresInWorktreeB() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = GlobalStore(rootURL: tmp.appendingPathComponent("store"))

        // Worktree A: already built, has ephemeral/ and both ios + macos Package.resolved
        let worktreeA = tmp.appendingPathComponent("worktree-a")
        try createFlutterWorkspaceScaffold(at: worktreeA, platforms: [.ios, .macos])
        try Self.writeFlutterGeneratedMetadata(
            in: worktreeA,
            platforms: [.ios, .macos],
            dateCreated: "2026-11-15 01:00:00.000000"
        )

        let iosResolvedContents = samplePackageResolved(pins: [
            (
                identity: "firebase-ios-sdk",
                location: "https://github.com/firebase/firebase-ios-sdk.git",
                revision: "1111111111111111111111111111111111111111",
                version: "11.4.0"
            ),
            (
                identity: "abseil-cpp-binary",
                location: "https://github.com/google/abseil-cpp-binary.git",
                revision: "2222222222222222222222222222222222222222",
                version: "1.2024011602.0"
            )
        ])
        let macosResolvedContents = samplePackageResolved(pins: [
            (
                identity: "swift-log",
                location: "https://github.com/apple/swift-log.git",
                revision: "3333333333333333333333333333333333333333",
                version: "1.6.1"
            )
        ])

        let iosResolvedA = worktreeA.appendingPathComponent("ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        let macosResolvedA = worktreeA.appendingPathComponent("macos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        try FileManager.default.createDirectory(at: iosResolvedA.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: macosResolvedA.deletingLastPathComponent(), withIntermediateDirectories: true)
        try iosResolvedContents.write(to: iosResolvedA, atomically: true, encoding: .utf8)
        try macosResolvedContents.write(to: macosResolvedA, atomically: true, encoding: .utf8)

        let noopRunner = MockFlutterCommandRunner { _ in
            Issue.record("flutter pub get should not run in Worktree A when ephemeral already exists")
            return CommandResult(exitCode: 0, stdout: "")
        }
        let integratorA = FlutterSPMIntegrator(
            store: store,
            executableResolver: MockExecutableResolver(resolvedPath: "/opt/flutter/bin/flutter"),
            commandRunner: noopRunner
        )

        let projectA = try ProjectDetector.detect(in: worktreeA.path)
        let recorded = try integratorA.recordResolvedDependencies(project: projectA)
        #expect(recorded.keys.sorted(by: { $0.rawValue < $1.rawValue }) == [.ios, .macos])
        #expect(recorded[.ios] != recorded[.macos])

        // Worktree B: fresh git worktree with ephemeral/ and Package.resolved git-ignored / missing
        let worktreeB = tmp.appendingPathComponent("worktree-b")
        try createFlutterWorkspaceScaffold(at: worktreeB, platforms: [.ios, .macos])

        let runnerB = MockFlutterCommandRunner { invocation in
            let rootURL = URL(fileURLWithPath: invocation.workingDirectory)
            // Simulate slightly different date_created timestamp emitted by flutter pub get in Worktree B
            try Self.writeFlutterGeneratedMetadata(
                in: rootURL,
                platforms: [.ios, .macos],
                dateCreated: "2026-11-15 02:30:00.000000"
            )
            return CommandResult(exitCode: 0, stdout: "Running \"flutter pub get\" in worktree-b...\n")
        }
        let integratorB = FlutterSPMIntegrator(
            store: store,
            executableResolver: MockExecutableResolver(resolvedPath: "/opt/flutter/bin/flutter"),
            commandRunner: runnerB
        )

        let projectB = try ProjectDetector.detect(in: worktreeB.path)
        #expect(projectB.packageResolvedPath == nil)

        let prepareResult = try integratorB.prepareForHydration(
            project: projectB,
            runPubGetIfMissing: true,
            environment: ["PATH": "/opt/flutter/bin"]
        )

        #expect(prepareResult.didRunPubGet == true)
        #expect(prepareResult.dependencyHashes[.ios] == recorded[.ios])
        #expect(prepareResult.dependencyHashes[.macos] == recorded[.macos])

        let iosResolvedB = worktreeB.appendingPathComponent("ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        let macosResolvedB = worktreeB.appendingPathComponent("macos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved")

        #expect(prepareResult.restoredPackageResolvedPaths[.ios] == iosResolvedB.path)
        #expect(prepareResult.restoredPackageResolvedPaths[.macos] == macosResolvedB.path)
        #expect(FileManager.default.fileExists(atPath: iosResolvedB.path))
        #expect(FileManager.default.fileExists(atPath: macosResolvedB.path))

        let parsedIOS = try PackageResolvedParser.parse(fileAt: iosResolvedB.path)
        #expect(parsedIOS.pins.map(\.identity) == ["firebase-ios-sdk", "abseil-cpp-binary"])

        let parsedMacOS = try PackageResolvedParser.parse(fileAt: macosResolvedB.path)
        #expect(parsedMacOS.pins.map(\.identity) == ["swift-log"])

        #expect(prepareResult.project.allPackageResolvedPaths == [iosResolvedB.path, macosResolvedB.path])
    }

    @Test("Supports targeting macos/Runner.xcworkspace explicitly without overwriting existing Package.resolved")
    func supportsExplicitMacOSWorkspaceAndPreservesExistingResolved() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = GlobalStore(rootURL: tmp.appendingPathComponent("store"))

        let worktreeA = tmp.appendingPathComponent("wt-a")
        try createFlutterWorkspaceScaffold(at: worktreeA, platforms: [.ios, .macos])
        try Self.writeFlutterGeneratedMetadata(in: worktreeA, platforms: [.ios, .macos])

        let cachedMacOSResolved = samplePackageResolved(pins: [
            (
                identity: "swift-collections",
                location: "https://github.com/apple/swift-collections.git",
                revision: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                version: "1.1.4"
            )
        ])
        let macosResolvedA = worktreeA.appendingPathComponent("macos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        try FileManager.default.createDirectory(at: macosResolvedA.deletingLastPathComponent(), withIntermediateDirectories: true)
        try cachedMacOSResolved.write(to: macosResolvedA, atomically: true, encoding: .utf8)

        let integrator = FlutterSPMIntegrator(
            store: store,
            executableResolver: MockExecutableResolver(resolvedPath: "/opt/flutter/bin/flutter"),
            commandRunner: MockFlutterCommandRunner { _ in
                CommandResult(exitCode: 0, stdout: "")
            }
        )

        let macosProjectA = try ProjectDetector.detect(
            workspacePath: worktreeA.appendingPathComponent("macos/Runner.xcworkspace").path
        )
        let recorded = try integrator.recordResolvedDependencies(project: macosProjectA)
        #expect(recorded[.macos] != nil)
        #expect(recorded[.ios] == nil)

        // Worktree B already has a custom macos Package.resolved checked in, and ephemeral already exists.
        let worktreeB = tmp.appendingPathComponent("wt-b")
        try createFlutterWorkspaceScaffold(at: worktreeB, platforms: [.ios, .macos])
        try Self.writeFlutterGeneratedMetadata(in: worktreeB, platforms: [.ios, .macos])

        let existingMacOSResolved = samplePackageResolved(pins: [
            (
                identity: "swift-collections",
                location: "https://github.com/apple/swift-collections.git",
                revision: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                version: "1.1.3"
            )
        ])
        let macosResolvedB = worktreeB.appendingPathComponent("macos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        try FileManager.default.createDirectory(at: macosResolvedB.deletingLastPathComponent(), withIntermediateDirectories: true)
        try existingMacOSResolved.write(to: macosResolvedB, atomically: true, encoding: .utf8)

        let macosProjectB = try ProjectDetector.detect(
            workspacePath: worktreeB.appendingPathComponent("macos/Runner.xcworkspace").path
        )
        let result = try integrator.prepareForHydration(project: macosProjectB, runPubGetIfMissing: true)

        #expect(result.didRunPubGet == false)
        #expect(result.restoredPackageResolvedPaths.isEmpty)
        let parsed = try PackageResolvedParser.parse(fileAt: macosResolvedB.path)
        #expect(parsed.pins.first?.revision == "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
    }

    @Test("Dependency hash changes when native plugin dependencies change and respects runPubGetIfMissing=false")
    func dependencyHashDetectsChangesAndRespectsFlag() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let worktree = tmp.appendingPathComponent("wt")
        try createFlutterWorkspaceScaffold(at: worktree, platforms: [.ios, .macos])

        let runner = MockFlutterCommandRunner { _ in
            Issue.record("flutter pub get must not be called when runPubGetIfMissing is false")
            return CommandResult(exitCode: 0, stdout: "")
        }
        let integrator = FlutterSPMIntegrator(
            store: GlobalStore(rootURL: tmp.appendingPathComponent("store")),
            executableResolver: MockExecutableResolver(resolvedPath: "/opt/flutter/bin/flutter"),
            commandRunner: runner
        )

        let cleanProject = try ProjectDetector.detect(in: worktree.path)
        let skippedResult = try integrator.prepareForHydration(
            project: cleanProject,
            runPubGetIfMissing: false
        )
        #expect(skippedResult.didRunPubGet == false)
        #expect(skippedResult.dependencyHashes.isEmpty)
        #expect(skippedResult.restoredPackageResolvedPaths.isEmpty)

        try Self.writeFlutterGeneratedMetadata(in: worktree, platforms: [.ios, .macos])
        let project1 = try ProjectDetector.detect(in: worktree.path)
        let iosHash1 = try integrator.computeDependencyHash(for: project1, platform: .ios)
        let macosHash1 = try integrator.computeDependencyHash(for: project1, platform: .macos)
        let combinedHash1 = try integrator.computeDependencyHash(for: project1)

        try Self.writeFlutterGeneratedMetadata(
            in: worktree,
            platforms: [.ios, .macos],
            iosExtraPlugin: "cloud_firestore"
        )
        let project2 = try ProjectDetector.detect(in: worktree.path)
        let iosHash2 = try integrator.computeDependencyHash(for: project2, platform: .ios)
        let macosHash2 = try integrator.computeDependencyHash(for: project2, platform: .macos)
        let combinedHash2 = try integrator.computeDependencyHash(for: project2)

        #expect(iosHash1 != iosHash2)
        #expect(combinedHash1 != combinedHash2)
        #expect(macosHash1 == macosHash2)
    }

    @Test("Throws pubGetFailed when flutter pub get exits non-zero")
    func throwsWhenPubGetFails() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let worktree = tmp.appendingPathComponent("wt-fail")
        try createFlutterWorkspaceScaffold(at: worktree, platforms: [.ios])

        let failingRunner = MockFlutterCommandRunner { _ in
            CommandResult(exitCode: 69, stdout: "", stderr: "Because app depends on foo, version solving failed.")
        }
        let integrator = FlutterSPMIntegrator(
            store: GlobalStore(rootURL: tmp.appendingPathComponent("store")),
            executableResolver: MockExecutableResolver(resolvedPath: "/opt/flutter/bin/flutter"),
            commandRunner: failingRunner
        )

        let project = try ProjectDetector.detect(in: worktree.path)
        #expect(throws: FlutterSPMIntegratorError.pubGetFailed(
            exitCode: 69,
            stderr: "Because app depends on foo, version solving failed.",
            stdout: ""
        )) {
            try integrator.prepareForHydration(project: project, runPubGetIfMissing: true)
        }
    }
}

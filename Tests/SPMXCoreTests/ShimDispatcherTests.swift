import Foundation
import Testing
@testable import SPMXCore

@Suite("ShimDispatcher & ExecutableLocator")
struct ShimDispatcherTests {
    // MARK: - Test Doubles

    private final class MockProcessExecutor: ShimProcessExecuting, @unchecked Sendable {
        private let lock = NSLock()
        private var recordedRequests: [ShimExecutionRequest] = []
        private let handler: @Sendable (ShimExecutionRequest) throws -> Int32

        init(handler: @escaping @Sendable (ShimExecutionRequest) throws -> Int32 = { _ in 0 }) {
            self.handler = handler
        }

        var requests: [ShimExecutionRequest] {
            lock.lock()
            defer { lock.unlock() }
            return recordedRequests
        }

        func execute(_ request: ShimExecutionRequest) throws -> Int32 {
            lock.lock()
            recordedRequests.append(request)
            lock.unlock()
            return try handler(request)
        }
    }

    private final class MockFlutterCommandRunner: FlutterCommandRunning, @unchecked Sendable {
        private let lock = NSLock()
        private var recordedInvocations: [(executablePath: String, arguments: [String], workingDirectory: String, environment: [String: String])] = []
        private let handler: @Sendable (String, [String], String, [String: String]) throws -> CommandResult

        init(
            handler: @escaping @Sendable (String, [String], String, [String: String]) throws -> CommandResult = { _, _, _, _ in
                CommandResult(exitCode: 0, stdout: "", stderr: "")
            }
        ) {
            self.handler = handler
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return recordedInvocations.count
        }

        func run(
            executablePath: String,
            arguments: [String],
            workingDirectory: String,
            environment: [String: String]
        ) throws -> CommandResult {
            lock.lock()
            recordedInvocations.append((executablePath, arguments, workingDirectory, environment))
            lock.unlock()
            return try handler(executablePath, arguments, workingDirectory, environment)
        }
    }

    private struct MockCacheProbe: CompilationCacheProbing, Sendable {
        let xcodeSupported: Bool
        let swiftSupported: Bool

        init(xcodeSupported: Bool = true, swiftSupported: Bool = true) {
            self.xcodeSupported = xcodeSupported
            self.swiftSupported = swiftSupported
        }

        func isXcodeCompilationCacheSupported(
            xcodebuildPath: String,
            environment: [String: String]
        ) -> Bool {
            xcodeSupported
        }

        func isSwiftBuildCacheSupported(
            swiftPath: String,
            environment: [String: String]
        ) -> Bool {
            swiftSupported
        }
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath()
            .appendingPathComponent("spmx-shim-tests-\(UUID().uuidString)")
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

    private func sampleToolchain() -> ToolchainFingerprint {
        ToolchainFingerprint(
            swiftVersion: "Apple Swift version 6.0 (swiftlang-6.0.0.9.10)",
            xcodeVersion: "Xcode 16.2\nBuild version 16C5032a"
        )
    }

    private func samplePackageResolved(
        identity: String = "swift-log",
        revision: String = "9cb486020ebf03c5b53df273802f4059445f2c4e",
        version: String = "1.6.2"
    ) -> String {
        """
        {
          "originHash" : "abcdef1234567890",
          "pins" : [
            {
              "identity" : "\(identity)",
              "kind" : "remoteSourceControl",
              "location" : "https://github.com/apple/\(identity).git",
              "state" : {
                "revision" : "\(revision)",
                "version" : "\(version)"
              }
            }
          ],
          "version" : 3
        }
        """
    }

    private func sampleWorkspaceStateJSON(
        identity: String = "swift-log",
        revision: String = "9cb486020ebf03c5b53df273802f4059445f2c4e",
        version: String = "1.6.2",
        subpath: String = "swift-log"
    ) -> String {
        """
        {
          "object" : {
            "artifacts" : [],
            "dependencies" : [
              {
                "basedOn" : null,
                "packageRef" : {
                  "identity" : "\(identity)",
                  "kind" : "remoteSourceControl",
                  "location" : "https://github.com/apple/\(identity).git",
                  "name" : "\(identity)"
                },
                "state" : {
                  "checkoutState" : {
                    "branch" : null,
                    "revision" : "\(revision)",
                    "version" : "\(version)"
                  },
                  "name" : "sourceControlCheckout"
                },
                "subpath" : "\(subpath)"
              }
            ],
            "prebuilts" : []
          },
          "version" : 6
        }
        """
    }

    private func seedCheckoutAndPopulateStore(
        store: GlobalStore,
        tempDir: URL,
        identity: String = "swift-log",
        revision: String = "9cb486020ebf03c5b53df273802f4059445f2c4e"
    ) throws {
        let seedCheckout = tempDir.appendingPathComponent("seed-checkout-\(identity)")
        try FileManager.default.createDirectory(at: seedCheckout, withIntermediateDirectories: true)
        try "// \(identity)\n".write(
            to: seedCheckout.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        try store.storeCheckout(from: seedCheckout, identity: identity, revision: revision)
    }

    private func createSwiftPackage(
        at root: URL,
        withPackageResolved: Bool = true
    ) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try """
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(
            name: "SampleApp",
            targets: [.executableTarget(name: "SampleApp")]
        )
        """.write(
            to: root.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        if withPackageResolved {
            try samplePackageResolved().write(
                to: root.appendingPathComponent("Package.resolved"),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    private func createXcodeProject(
        at root: URL,
        name: String = "SampleApp",
        withPackageResolved: Bool = true
    ) throws -> URL {
        let workspaceURL = root.appendingPathComponent("\(name).xcworkspace")
        let swiftpmDir = workspaceURL
            .appendingPathComponent("xcshareddata")
            .appendingPathComponent("swiftpm")
        try FileManager.default.createDirectory(at: swiftpmDir, withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <Workspace version="1.0">
           <FileRef location="group:\(name).xcodeproj"/>
        </Workspace>
        """.write(
            to: workspaceURL.appendingPathComponent("contents.xcworkspacedata"),
            atomically: true,
            encoding: .utf8
        )
        if withPackageResolved {
            try samplePackageResolved().write(
                to: swiftpmDir.appendingPathComponent("Package.resolved"),
                atomically: true,
                encoding: .utf8
            )
        }
        return workspaceURL
    }

    private func createFlutterProject(
        at root: URL,
        withGeneratedSPM: Bool = true,
        withPackageResolved: Bool = true
    ) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try """
        name: demo_app
        environment:
          sdk: ">=3.5.0 <4.0.0"
        dependencies:
          flutter:
            sdk: flutter
        """.write(
            to: root.appendingPathComponent("pubspec.yaml"),
            atomically: true,
            encoding: .utf8
        )

        let iosWorkspace = root.appendingPathComponent("ios/Runner.xcworkspace")
        let swiftpmDir = iosWorkspace.appendingPathComponent("xcshareddata/swiftpm")
        try FileManager.default.createDirectory(at: swiftpmDir, withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <Workspace version="1.0">
           <FileRef location="group:Runner.xcodeproj"/>
        </Workspace>
        """.write(
            to: iosWorkspace.appendingPathComponent("contents.xcworkspacedata"),
            atomically: true,
            encoding: .utf8
        )

        if withGeneratedSPM {
            let pkgDir = root.appendingPathComponent(
                "ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage"
            )
            try FileManager.default.createDirectory(at: pkgDir, withIntermediateDirectories: true)
            try """
            // swift-tools-version: 5.9
            import PackageDescription
            let package = Package(
                name: "FlutterGeneratedPluginSwiftPackage",
                platforms: [.iOS("13.0")],
                products: [],
                dependencies: [],
                targets: [.target(name: "FlutterGeneratedPluginSwiftPackage")]
            )
            """.write(
                to: pkgDir.appendingPathComponent("Package.swift"),
                atomically: true,
                encoding: .utf8
            )
        }

        if withPackageResolved {
            try samplePackageResolved().write(
                to: swiftpmDir.appendingPathComponent("Package.resolved"),
                atomically: true,
                encoding: .utf8
            )
        }

        return iosWorkspace
    }

    // MARK: - Multicall Role Detection

    @Test("ShimRole detects multicall role from argv0")
    func multicallRoleDetection() {
        #expect(ShimRole.detect(argv0: "spmx") == .spmx)
        #expect(ShimRole.detect(argv0: "/Users/dev/.spmx/bin/spmx") == .spmx)
        #expect(ShimRole.detect(argv0: "flutter") == .flutter)
        #expect(ShimRole.detect(argv0: "/Users/dev/.spmx/shims/flutter") == .flutter)
        #expect(ShimRole.detect(argv0: "xcodebuild") == .xcodebuild)
        #expect(ShimRole.detect(argv0: "/Users/dev/.spmx/shims/xcodebuild") == .xcodebuild)
        #expect(ShimRole.detect(argv0: "swift") == .swift)
        #expect(ShimRole.detect(argv0: "/Users/dev/.spmx/shims/swift") == .swift)
        #expect(ShimRole.detect(argv0: "/tmp/unknown-tool") == .spmx)
        #expect(ShimRole.detect(argv0: "") == .spmx)
    }

    // MARK: - ExecutableLocator & Anti-Loop PATH Resolution

    @Test("ExecutableLocator filters shims and symlink loops while preserving puro/fvm/xcodebuild priority")
    func executableLocatorFiltersShimsAndLoops() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeHome = tempDir.appendingPathComponent("home")
        let defaultShimsDir = fakeHome.appendingPathComponent(".spmx/shims")
        let customShimsDir = tempDir.appendingPathComponent("custom-shims")
        let spmxBin = fakeHome.appendingPathComponent(".spmx/bin/spmx")
        let loopDir = tempDir.appendingPathComponent("loop-bin")
        let puroBin = tempDir.appendingPathComponent("puro/bin")
        let fvmBin = tempDir.appendingPathComponent("fvm/bin")
        let usrBin = tempDir.appendingPathComponent("usr/bin")

        try makeExecutableFile(at: spmxBin)
        try FileManager.default.createDirectory(at: defaultShimsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: customShimsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: loopDir, withIntermediateDirectories: true)

        // Create shims in ~/.spmx/shims and custom SPMX_SHIMS_DIR pointing to spmx
        try FileManager.default.createSymbolicLink(
            at: defaultShimsDir.appendingPathComponent("flutter"),
            withDestinationURL: spmxBin
        )
        try FileManager.default.createSymbolicLink(
            at: customShimsDir.appendingPathComponent("xcodebuild"),
            withDestinationURL: spmxBin
        )
        // Create a symlink in an unrelated directory pointing to spmx (must be skipped to prevent infinite recursion)
        try FileManager.default.createSymbolicLink(
            at: loopDir.appendingPathComponent("swift"),
            withDestinationURL: spmxBin
        )
        // Create another symlink in loopDir pointing into ~/.spmx/shims
        try FileManager.default.createSymbolicLink(
            at: loopDir.appendingPathComponent("flutter"),
            withDestinationURL: defaultShimsDir.appendingPathComponent("flutter")
        )

        let puroFlutter = puroBin.appendingPathComponent("flutter")
        let fvmFlutter = fvmBin.appendingPathComponent("flutter")
        let realXcodebuild = usrBin.appendingPathComponent("xcodebuild")
        let realSwift = usrBin.appendingPathComponent("swift")

        try makeExecutableFile(at: puroFlutter)
        try makeExecutableFile(at: fvmFlutter)
        try makeExecutableFile(at: realXcodebuild)
        try makeExecutableFile(at: realSwift)

        let env: [String: String] = [
            "PATH": [
                defaultShimsDir.path,
                customShimsDir.path,
                loopDir.path,
                puroBin.path,
                fvmBin.path,
                usrBin.path
            ].joined(separator: ":"),
            ExecutableLocator.shimsDirectoryEnvironmentKey: customShimsDir.path
        ]

        let locator = ExecutableLocator(homeDirectory: fakeHome)

        #expect(try locator.resolveFlutter(environment: env) == puroFlutter.path)
        #expect(try locator.resolveXcodebuild(environment: env) == realXcodebuild.path)
        #expect(try locator.resolveSwift(environment: env) == realSwift.path)

        let sanitized = locator.sanitizedEnvironment(from: env)
        let sanitizedEntries = (sanitized["PATH"] ?? "").split(separator: ":").map(String.init)
        #expect(!sanitizedEntries.contains(defaultShimsDir.path))
        #expect(!sanitizedEntries.contains(customShimsDir.path))
        #expect(sanitizedEntries == [loopDir.path, puroBin.path, fvmBin.path, usrBin.path])
    }

    @Test("ExecutableLocator throws executableNotFound when only shim binaries exist")
    func executableLocatorThrowsWhenOnlyShimExists() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeHome = tempDir.appendingPathComponent("home")
        let shimsDir = fakeHome.appendingPathComponent(".spmx/shims")
        let spmxBin = fakeHome.appendingPathComponent(".spmx/bin/spmx")
        try makeExecutableFile(at: spmxBin)
        try FileManager.default.createDirectory(at: shimsDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: shimsDir.appendingPathComponent("flutter"),
            withDestinationURL: spmxBin
        )

        let locator = ExecutableLocator(homeDirectory: fakeHome)
        let env = ["PATH": shimsDir.path]

        #expect(throws: ExecutableLocatorError.executableNotFound(name: "flutter", searchedPaths: [])) {
            try locator.resolveFlutter(environment: env)
        }
    }

    // MARK: - CompilationCacheConfig

    @Test("CompilationCacheConfig resolves default directory, overrides, and version support")
    func compilationCacheConfigBehavior() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let home = tempDir.appendingPathComponent("home")
        let defaultConfig = CompilationCacheConfig.resolve(environment: [:], homeDirectory: home)
        #expect(defaultConfig.isEnabled == true)
        #expect(defaultConfig.cacheDirectory.path == home.appendingPathComponent(".spmx/compilation-cache").path)

        let customDir = tempDir.appendingPathComponent("custom-cas")
        let disabledConfig = CompilationCacheConfig.resolve(
            environment: [
                CompilationCacheConfig.directoryEnvironmentKey: customDir.path,
                CompilationCacheConfig.disableEnvironmentKey: "1"
            ],
            homeDirectory: home
        )
        #expect(disabledConfig.isEnabled == false)
        #expect(disabledConfig.cacheDirectory.path == customDir.path)

        #expect(CompilationCacheConfig.isXcodeSupported(versionOutput: "Xcode 16.0\nBuild version 16A242d"))
        #expect(CompilationCacheConfig.isXcodeSupported(versionOutput: "Xcode 16.2\nBuild version 16C5032a"))
        #expect(!CompilationCacheConfig.isXcodeSupported(versionOutput: "Xcode 15.4\nBuild version 15F31d"))
        #expect(CompilationCacheConfig.isSwiftSupported(versionOutput: "Apple Swift version 6.0 (swiftlang-6.0.0.9.10)"))
        #expect(CompilationCacheConfig.isSwiftSupported(versionOutput: "Swift version 6.1-dev"))
        #expect(!CompilationCacheConfig.isSwiftSupported(versionOutput: "Apple Swift version 5.10 (swiftlang-5.10.0.13)"))
    }

    // MARK: - Global Bypass (SPMX_DISABLE=1)

    @Test("SPMX_DISABLE=1 bypasses hydration, harvest, and flag injection across all shims")
    func globalDisableBypass() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeHome = tempDir.appendingPathComponent("home")
        let shimsDir = fakeHome.appendingPathComponent(".spmx/shims")
        let binDir = tempDir.appendingPathComponent("bin")
        let projectDir = tempDir.appendingPathComponent("swift-pkg")
        let storeDir = tempDir.appendingPathComponent("store")

        try createSwiftPackage(at: projectDir)
        let realSwift = binDir.appendingPathComponent("swift")
        let realXcodebuild = binDir.appendingPathComponent("xcodebuild")
        let realFlutter = binDir.appendingPathComponent("flutter")
        try makeExecutableFile(at: realSwift)
        try makeExecutableFile(at: realXcodebuild)
        try makeExecutableFile(at: realFlutter)

        let executor = MockProcessExecutor { _ in 42 }
        let store = GlobalStore(rootURL: storeDir)
        let dispatcher = ShimDispatcher(
            store: store,
            executableLocator: ExecutableLocator(homeDirectory: fakeHome),
            processExecutor: executor,
            cacheProbe: MockCacheProbe(xcodeSupported: true, swiftSupported: true),
            toolchainProvider: { sampleToolchain() },
            flutterCommandRunner: MockFlutterCommandRunner(),
            homeDirectory: fakeHome
        )

        let env: [String: String] = [
            "PATH": "\(shimsDir.path):\(binDir.path)",
            ExecutableLocator.disableEnvironmentKey: "1"
        ]

        let swiftOutcome = try dispatcher.dispatch(
            argv0: shimsDir.appendingPathComponent("swift").path,
            arguments: ["build"],
            workingDirectory: projectDir.path,
            environment: env
        )

        #expect(swiftOutcome.role == .swift)
        #expect(swiftOutcome.bypassed == true)
        #expect(swiftOutcome.exitCode == 42)
        #expect(swiftOutcome.didHydrate == false)
        #expect(swiftOutcome.didHarvest == false)
        #expect(swiftOutcome.injectedCompilationCache == false)
        #expect(swiftOutcome.forwardedArguments == ["build"])
        #expect(swiftOutcome.executedExecutablePath == realSwift.path)
        #expect(executor.requests.last?.canReplaceProcess == true)
        #expect(executor.requests.last?.environment["PATH"] == binDir.path)

        let xcodeOutcome = try dispatcher.dispatch(
            argv0: "xcodebuild",
            arguments: ["-scheme", "App", "build"],
            workingDirectory: projectDir.path,
            environment: env
        )
        #expect(xcodeOutcome.bypassed == true)
        #expect(xcodeOutcome.injectedCompilationCache == false)
        #expect(xcodeOutcome.forwardedArguments == ["-scheme", "App", "build"])
        #expect(xcodeOutcome.executedExecutablePath == realXcodebuild.path)

        let flutterOutcome = try dispatcher.dispatch(
            argv0: "flutter",
            arguments: ["build", "ios"],
            workingDirectory: projectDir.path,
            environment: env
        )
        #expect(flutterOutcome.bypassed == true)
        #expect(flutterOutcome.executedExecutablePath == realFlutter.path)
        #expect(executor.requests.last?.environment[ExecutableLocator.flutterShimActiveEnvironmentKey] == nil)
    }

    // MARK: - Flutter Shim

    @Test("Flutter shim delegates irrelevant commands directly without hydration or harvest")
    func flutterShimPassthroughCommands() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeHome = tempDir.appendingPathComponent("home")
        let binDir = tempDir.appendingPathComponent("bin")
        let realFlutter = binDir.appendingPathComponent("flutter")
        try makeExecutableFile(at: realFlutter)

        let projectDir = tempDir.appendingPathComponent("flutter-app")
        _ = try createFlutterProject(at: projectDir)

        let executor = MockProcessExecutor { _ in 0 }
        let flutterRunner = MockFlutterCommandRunner()
        let dispatcher = ShimDispatcher(
            store: GlobalStore(rootURL: tempDir.appendingPathComponent("store")),
            executableLocator: ExecutableLocator(homeDirectory: fakeHome),
            processExecutor: executor,
            cacheProbe: MockCacheProbe(),
            toolchainProvider: { sampleToolchain() },
            flutterCommandRunner: flutterRunner,
            homeDirectory: fakeHome
        )

        let env = ["PATH": binDir.path]
        let passthroughArgSets: [[String]] = [
            ["--version"],
            ["doctor", "-v"],
            ["analyze"],
            ["build", "apk", "--release"],
            ["test", "--platform", "chrome"],
            ["build", "ios", "--no-spmx"]
        ]

        for args in passthroughArgSets {
            let outcome = try dispatcher.dispatch(
                argv0: "flutter",
                arguments: args,
                workingDirectory: projectDir.path,
                environment: env
            )
            #expect(outcome.role == .flutter)
            #expect(outcome.didHydrate == false)
            #expect(outcome.didHarvest == false)
            #expect(outcome.bypassed == false)
            #expect(executor.requests.last?.canReplaceProcess == true)
            #expect(executor.requests.last?.environment[ExecutableLocator.flutterShimActiveEnvironmentKey] == nil)
            #expect(!(outcome.forwardedArguments.contains("--no-spmx")))
        }

        #expect(flutterRunner.count == 0)
    }

    @Test("Flutter shim sets SPMX_FLUTTER_SHIM_ACTIVE=1, hydrates before, and harvests after Apple build/run")
    func flutterShimHydratesAndHarvestsAppleBuild() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeHome = tempDir.appendingPathComponent("home")
        let binDir = tempDir.appendingPathComponent("bin")
        let realFlutter = binDir.appendingPathComponent("flutter")
        try makeExecutableFile(at: realFlutter)

        let store = GlobalStore(rootURL: tempDir.appendingPathComponent("store"))
        try seedCheckoutAndPopulateStore(store: store, tempDir: tempDir)

        let projectDir = tempDir.appendingPathComponent("flutter-app")
        let iosWorkspace = try createFlutterProject(at: projectDir)

        let expectedSourcePackages = DerivedDataPathCalculator.derivedDataURL(
            forContainerPath: iosWorkspace.path
        ).appendingPathComponent("SourcePackages")
        defer { try? FileManager.default.removeItem(at: expectedSourcePackages.deletingLastPathComponent()) }

        let executor = MockProcessExecutor { request in
            // Verify hydration materialized the checkout before flutter ran
            let hydratedCheckout = expectedSourcePackages.appendingPathComponent("checkouts/swift-log/Package.swift")
            #expect(FileManager.default.fileExists(atPath: hydratedCheckout.path))
            #expect(request.environment[ExecutableLocator.flutterShimActiveEnvironmentKey] == "1")
            #expect(request.canReplaceProcess == false)

            // Simulate flutter/xcodebuild producing a new package checkout + workspace-state.json during build
            let newCheckout = expectedSourcePackages.appendingPathComponent("checkouts/swift-numerics")
            try FileManager.default.createDirectory(at: newCheckout, withIntermediateDirectories: true)
            try "// swift-numerics\n".write(
                to: newCheckout.appendingPathComponent("Package.swift"),
                atomically: true,
                encoding: .utf8
            )
            let wsState = """
            {
              "object" : {
                "artifacts" : [],
                "dependencies" : [
                  {
                    "basedOn" : null,
                    "packageRef" : {
                      "identity" : "swift-numerics",
                      "kind" : "remoteSourceControl",
                      "location" : "https://github.com/apple/swift-numerics.git",
                      "name" : "swift-numerics"
                    },
                    "state" : {
                      "checkoutState" : {
                        "branch" : null,
                        "revision" : "0a5bc04095a675662cf24757cc0640aa2204253b",
                        "version" : "1.0.2"
                      },
                      "name" : "sourceControlCheckout"
                    },
                    "subpath" : "swift-numerics"
                  }
                ],
                "prebuilts" : []
              },
              "version" : 6
            }
            """
            try wsState.write(
                to: expectedSourcePackages.appendingPathComponent("workspace-state.json"),
                atomically: true,
                encoding: .utf8
            )
            return 0
        }

        let dispatcher = ShimDispatcher(
            store: store,
            executableLocator: ExecutableLocator(homeDirectory: fakeHome),
            processExecutor: executor,
            cacheProbe: MockCacheProbe(),
            toolchainProvider: { sampleToolchain() },
            flutterCommandRunner: MockFlutterCommandRunner(),
            homeDirectory: fakeHome
        )

        let outcome = try dispatcher.dispatch(
            argv0: "flutter",
            arguments: ["build", "ios", "--no-codesign"],
            workingDirectory: projectDir.path,
            environment: ["PATH": binDir.path]
        )

        #expect(outcome.role == .flutter)
        #expect(outcome.exitCode == 0)
        #expect(outcome.didHydrate == true)
        #expect(outcome.didHarvest == true)
        #expect(outcome.forwardedArguments == ["build", "ios", "--no-codesign"])
        #expect(store.hasCheckout(
            identity: "swift-numerics",
            revision: "0a5bc04095a675662cf24757cc0640aa2204253b"
        ))
    }

    // MARK: - Xcodebuild Shim

    @Test("Xcodebuild shim parses flags, injects COMPILATION_CACHE_*, and harvests on success")
    func xcodebuildShimHydratesInjectsCacheAndHarvests() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeHome = tempDir.appendingPathComponent("home")
        let binDir = tempDir.appendingPathComponent("bin")
        let realXcodebuild = binDir.appendingPathComponent("xcodebuild")
        try makeExecutableFile(at: realXcodebuild)

        let store = GlobalStore(rootURL: tempDir.appendingPathComponent("store"))
        try seedCheckoutAndPopulateStore(store: store, tempDir: tempDir)

        let projectDir = tempDir.appendingPathComponent("xcode-app")
        let workspaceURL = try createXcodeProject(at: projectDir)
        let derivedDataDir = tempDir.appendingPathComponent("dd")
        let expectedSourcePackages = derivedDataDir.appendingPathComponent("SourcePackages")

        let executor = MockProcessExecutor { request in
            let hydratedFile = expectedSourcePackages.appendingPathComponent("checkouts/swift-log/Package.swift")
            #expect(FileManager.default.fileExists(atPath: hydratedFile.path))

            let wsState = sampleWorkspaceStateJSON()
            try wsState.write(
                to: expectedSourcePackages.appendingPathComponent("workspace-state.json"),
                atomically: true,
                encoding: .utf8
            )
            return 0
        }

        let dispatcher = ShimDispatcher(
            store: store,
            executableLocator: ExecutableLocator(homeDirectory: fakeHome),
            processExecutor: executor,
            cacheProbe: MockCacheProbe(xcodeSupported: true, swiftSupported: true),
            toolchainProvider: { sampleToolchain() },
            flutterCommandRunner: MockFlutterCommandRunner(),
            homeDirectory: fakeHome
        )

        let outcome = try dispatcher.dispatch(
            argv0: "xcodebuild",
            arguments: [
                "-workspace", workspaceURL.path,
                "-scheme", "SampleApp",
                "-derivedDataPath", derivedDataDir.path,
                "build"
            ],
            workingDirectory: projectDir.path,
            environment: ["PATH": binDir.path]
        )

        let expectedCachePath = fakeHome.appendingPathComponent(".spmx/compilation-cache").path
        #expect(outcome.role == .xcodebuild)
        #expect(outcome.exitCode == 0)
        #expect(outcome.didHydrate == true)
        #expect(outcome.didHarvest == true)
        #expect(outcome.injectedCompilationCache == true)
        #expect(outcome.forwardedArguments.contains("COMPILATION_CACHE_ENABLE_CACHING=YES"))
        #expect(outcome.forwardedArguments.contains("COMPILATION_CACHE_ENABLE_PLUGIN_CACHING=YES"))
        #expect(outcome.forwardedArguments.contains("COMPILATION_CACHE_CAS_PATH=\(expectedCachePath)"))
    }

    @Test("Xcodebuild shim skips redundant hydration when SPMX_FLUTTER_SHIM_ACTIVE=1 or -clonedSourcePackagesDirPath is set")
    func xcodebuildShimSkipsRedundantHydration() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeHome = tempDir.appendingPathComponent("home")
        let binDir = tempDir.appendingPathComponent("bin")
        try makeExecutableFile(at: binDir.appendingPathComponent("xcodebuild"))

        let store = GlobalStore(rootURL: tempDir.appendingPathComponent("store"))
        try seedCheckoutAndPopulateStore(store: store, tempDir: tempDir)

        let projectDir = tempDir.appendingPathComponent("xcode-app")
        let workspaceURL = try createXcodeProject(at: projectDir)
        let derivedDataDir = tempDir.appendingPathComponent("dd")
        let customClonedDir = tempDir.appendingPathComponent("custom-cloned")

        let executor = MockProcessExecutor { _ in 0 }
        let dispatcher = ShimDispatcher(
            store: store,
            executableLocator: ExecutableLocator(homeDirectory: fakeHome),
            processExecutor: executor,
            cacheProbe: MockCacheProbe(xcodeSupported: true, swiftSupported: true),
            toolchainProvider: { sampleToolchain() },
            flutterCommandRunner: MockFlutterCommandRunner(),
            homeDirectory: fakeHome
        )

        // 1. SPMX_FLUTTER_SHIM_ACTIVE=1 skips hydration but injects compilation cache
        let flutterActiveOutcome = try dispatcher.dispatch(
            argv0: "xcodebuild",
            arguments: [
                "-workspace", workspaceURL.path,
                "-scheme", "Runner",
                "-derivedDataPath", derivedDataDir.path,
                "build"
            ],
            workingDirectory: projectDir.path,
            environment: [
                "PATH": binDir.path,
                ExecutableLocator.flutterShimActiveEnvironmentKey: "1"
            ]
        )
        #expect(flutterActiveOutcome.didHydrate == false)
        #expect(flutterActiveOutcome.injectedCompilationCache == true)
        #expect(!FileManager.default.fileExists(atPath: derivedDataDir.appendingPathComponent("SourcePackages").path))

        // 2. -clonedSourcePackagesDirPath skips hydration
        let clonedOverrideOutcome = try dispatcher.dispatch(
            argv0: "xcodebuild",
            arguments: [
                "-workspace", workspaceURL.path,
                "-scheme", "SampleApp",
                "-clonedSourcePackagesDirPath", customClonedDir.path,
                "archive"
            ],
            workingDirectory: projectDir.path,
            environment: ["PATH": binDir.path]
        )
        #expect(clonedOverrideOutcome.didHydrate == false)
        #expect(clonedOverrideOutcome.injectedCompilationCache == true)
    }

    @Test("Xcodebuild shim respects SPMX_NO_COMPILE_CACHE=1, explicit COMPILATION_CACHE_*, and preserves non-zero exit codes")
    func xcodebuildShimCacheBypassAndExitCodePreservation() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeHome = tempDir.appendingPathComponent("home")
        let binDir = tempDir.appendingPathComponent("bin")
        try makeExecutableFile(at: binDir.appendingPathComponent("xcodebuild"))

        let projectDir = tempDir.appendingPathComponent("xcode-app")
        let workspaceURL = try createXcodeProject(at: projectDir)
        let derivedDataDir = tempDir.appendingPathComponent("dd")

        let executor = MockProcessExecutor { _ in 65 }
        let dispatcher = ShimDispatcher(
            store: GlobalStore(rootURL: tempDir.appendingPathComponent("store")),
            executableLocator: ExecutableLocator(homeDirectory: fakeHome),
            processExecutor: executor,
            cacheProbe: MockCacheProbe(xcodeSupported: true, swiftSupported: true),
            toolchainProvider: { sampleToolchain() },
            flutterCommandRunner: MockFlutterCommandRunner(),
            homeDirectory: fakeHome
        )

        // SPMX_NO_COMPILE_CACHE=1 disables injection and non-zero exit code 65 skips harvest & is preserved
        let noCacheOutcome = try dispatcher.dispatch(
            argv0: "xcodebuild",
            arguments: [
                "-workspace", workspaceURL.path,
                "-scheme", "SampleApp",
                "-derivedDataPath", derivedDataDir.path,
                "test"
            ],
            workingDirectory: projectDir.path,
            environment: [
                "PATH": binDir.path,
                CompilationCacheConfig.disableEnvironmentKey: "1"
            ]
        )
        #expect(noCacheOutcome.exitCode == 65)
        #expect(noCacheOutcome.injectedCompilationCache == false)
        #expect(noCacheOutcome.didHarvest == false)
        #expect(!noCacheOutcome.forwardedArguments.contains(where: { $0.hasPrefix("COMPILATION_CACHE_") }))

        // Explicit user COMPILATION_CACHE_* arg suppresses duplicate injection
        let explicitCacheOutcome = try dispatcher.dispatch(
            argv0: "xcodebuild",
            arguments: [
                "-workspace", workspaceURL.path,
                "-scheme", "SampleApp",
                "-derivedDataPath", derivedDataDir.path,
                "COMPILATION_CACHE_ENABLE_CACHING=NO",
                "build"
            ],
            workingDirectory: projectDir.path,
            environment: ["PATH": binDir.path]
        )
        #expect(explicitCacheOutcome.injectedCompilationCache == false)
        #expect(explicitCacheOutcome.forwardedArguments.filter { $0.hasPrefix("COMPILATION_CACHE_") } == [
            "COMPILATION_CACHE_ENABLE_CACHING=NO"
        ])
    }

    // MARK: - Swift Shim

    @Test("Swift shim passes through non-build commands and directories without Package.swift")
    func swiftShimPassthrough() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeHome = tempDir.appendingPathComponent("home")
        let binDir = tempDir.appendingPathComponent("bin")
        let realSwift = binDir.appendingPathComponent("swift")
        try makeExecutableFile(at: realSwift)

        let emptyDir = tempDir.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)

        let pkgDir = tempDir.appendingPathComponent("pkg")
        try createSwiftPackage(at: pkgDir)

        let executor = MockProcessExecutor { _ in 0 }
        let dispatcher = ShimDispatcher(
            store: GlobalStore(rootURL: tempDir.appendingPathComponent("store")),
            executableLocator: ExecutableLocator(homeDirectory: fakeHome),
            processExecutor: executor,
            cacheProbe: MockCacheProbe(xcodeSupported: true, swiftSupported: true),
            toolchainProvider: { sampleToolchain() },
            flutterCommandRunner: MockFlutterCommandRunner(),
            homeDirectory: fakeHome
        )

        let versionOutcome = try dispatcher.dispatch(
            argv0: "swift",
            arguments: ["--version"],
            workingDirectory: pkgDir.path,
            environment: ["PATH": binDir.path]
        )
        #expect(versionOutcome.didHydrate == false)
        #expect(versionOutcome.didHarvest == false)
        #expect(versionOutcome.injectedCompilationCache == false)
        #expect(executor.requests.last?.canReplaceProcess == true)

        let noManifestOutcome = try dispatcher.dispatch(
            argv0: "swift",
            arguments: ["build"],
            workingDirectory: emptyDir.path,
            environment: ["PATH": binDir.path]
        )
        #expect(noManifestOutcome.didHydrate == false)
        #expect(noManifestOutcome.didHarvest == false)
        #expect(noManifestOutcome.injectedCompilationCache == false)
        #expect(executor.requests.last?.canReplaceProcess == true)
    }

    @Test("Swift shim intercepts swift build/run/package resolve, hydrates .build/, injects --enable-build-cache, and harvests")
    func swiftShimInterceptsAndInjectsBuildCache() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeHome = tempDir.appendingPathComponent("home")
        let binDir = tempDir.appendingPathComponent("bin")
        try makeExecutableFile(at: binDir.appendingPathComponent("swift"))

        let store = GlobalStore(rootURL: tempDir.appendingPathComponent("store"))
        try seedCheckoutAndPopulateStore(store: store, tempDir: tempDir)

        let pkgDir = tempDir.appendingPathComponent("swift-pkg")
        try createSwiftPackage(at: pkgDir)
        let dotBuildDir = pkgDir.appendingPathComponent(".build")

        let executor = MockProcessExecutor { _ in
            let hydratedFile = dotBuildDir.appendingPathComponent("checkouts/swift-log/Package.swift")
            #expect(FileManager.default.fileExists(atPath: hydratedFile.path))

            try sampleWorkspaceStateJSON().write(
                to: dotBuildDir.appendingPathComponent("workspace-state.json"),
                atomically: true,
                encoding: .utf8
            )
            return 0
        }

        let dispatcher = ShimDispatcher(
            store: store,
            executableLocator: ExecutableLocator(homeDirectory: fakeHome),
            processExecutor: executor,
            cacheProbe: MockCacheProbe(xcodeSupported: true, swiftSupported: true),
            toolchainProvider: { sampleToolchain() },
            flutterCommandRunner: MockFlutterCommandRunner(),
            homeDirectory: fakeHome
        )

        // 1. `swift build` injects `--enable-build-cache`, hydrates, and harvests
        let buildOutcome = try dispatcher.dispatch(
            argv0: "swift",
            arguments: ["build", "-c", "release"],
            workingDirectory: pkgDir.path,
            environment: ["PATH": binDir.path]
        )
        #expect(buildOutcome.didHydrate == true)
        #expect(buildOutcome.didHarvest == true)
        #expect(buildOutcome.injectedCompilationCache == true)
        #expect(buildOutcome.forwardedArguments == ["build", "--enable-build-cache", "-c", "release"])

        // 2. `swift run MyApp --help` inserts `--enable-build-cache` before target name & doesn't mistake `--help` for swift help
        let runOutcome = try dispatcher.dispatch(
            argv0: "swift",
            arguments: ["run", "SampleApp", "--help"],
            workingDirectory: pkgDir.path,
            environment: ["PATH": binDir.path]
        )
        #expect(runOutcome.didHydrate == true)
        #expect(runOutcome.injectedCompilationCache == true)
        #expect(runOutcome.forwardedArguments == ["run", "--enable-build-cache", "SampleApp", "--help"])

        // 3. `swift package resolve` hydrates/harvests without injecting `--enable-build-cache`
        let resolveOutcome = try dispatcher.dispatch(
            argv0: "swift",
            arguments: ["package", "resolve"],
            workingDirectory: pkgDir.path,
            environment: ["PATH": binDir.path]
        )
        #expect(resolveOutcome.didHydrate == true)
        #expect(resolveOutcome.didHarvest == true)
        #expect(resolveOutcome.injectedCompilationCache == false)
        #expect(resolveOutcome.forwardedArguments == ["package", "resolve"])

        // 4. `SPMX_NO_COMPILE_CACHE=1` and explicit `--disable-build-cache` bypass flag injection
        let noCacheOutcome = try dispatcher.dispatch(
            argv0: "swift",
            arguments: ["test"],
            workingDirectory: pkgDir.path,
            environment: [
                "PATH": binDir.path,
                CompilationCacheConfig.disableEnvironmentKey: "1"
            ]
        )
        #expect(noCacheOutcome.injectedCompilationCache == false)
        #expect(noCacheOutcome.forwardedArguments == ["test"])

        let explicitDisableOutcome = try dispatcher.dispatch(
            argv0: "swift",
            arguments: ["build", "--disable-build-cache"],
            workingDirectory: pkgDir.path,
            environment: ["PATH": binDir.path]
        )
        #expect(explicitDisableOutcome.injectedCompilationCache == false)
        #expect(explicitDisableOutcome.forwardedArguments == ["build", "--disable-build-cache"])
    }
}

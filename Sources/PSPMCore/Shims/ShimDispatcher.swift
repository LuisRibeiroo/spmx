import Foundation

/// Summary of executing a `PATH` shim invocation via ``ShimDispatcher``.
public struct ShimDispatchOutcome: Equatable, Sendable {
    public let role: ShimRole
    public let exitCode: Int32
    public let bypassed: Bool
    public let didHydrate: Bool
    public let didHarvest: Bool
    public let injectedCompilationCache: Bool
    public let executedExecutablePath: String
    public let forwardedArguments: [String]

    public init(
        role: ShimRole,
        exitCode: Int32,
        bypassed: Bool,
        didHydrate: Bool,
        didHarvest: Bool,
        injectedCompilationCache: Bool,
        executedExecutablePath: String,
        forwardedArguments: [String]
    ) {
        self.role = role
        self.exitCode = exitCode
        self.bypassed = bypassed
        self.didHydrate = didHydrate
        self.didHarvest = didHarvest
        self.injectedCompilationCache = injectedCompilationCache
        self.executedExecutablePath = executedExecutablePath
        self.forwardedArguments = forwardedArguments
    }
}

/// Coordinates transparent `flutter`, `xcodebuild`, and `swift` PATH shims with ``PackageSyncEngine``,
/// ``FlutterSPMIntegrator``, and native LLVM CAS compilation caching.
public struct ShimDispatcher: Sendable {
    public let store: GlobalStore
    public let executableLocator: any ExecutableLocating
    public let processExecutor: any ShimProcessExecuting
    public let cacheProbe: any CompilationCacheProbing
    public let toolchainProvider: PackageSyncEngine.ToolchainProvider
    public let flutterCommandRunner: any FlutterCommandRunning
    public let homeDirectory: URL
    public let verboseLogger: (@Sendable (String) -> Void)?

    public init(
        store: GlobalStore = GlobalStore(),
        executableLocator: any ExecutableLocating = ExecutableLocator(),
        processExecutor: any ShimProcessExecuting = SystemShimProcessExecutor(),
        cacheProbe: any CompilationCacheProbing = DefaultCompilationCacheProbe(),
        toolchainProvider: @escaping PackageSyncEngine.ToolchainProvider = { try ToolchainFingerprint.current() },
        flutterCommandRunner: any FlutterCommandRunning = ProcessFlutterCommandRunner(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        verboseLogger: (@Sendable (String) -> Void)? = nil
    ) {
        self.store = store
        self.executableLocator = executableLocator
        self.processExecutor = processExecutor
        self.cacheProbe = cacheProbe
        self.toolchainProvider = toolchainProvider
        self.flutterCommandRunner = flutterCommandRunner
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.verboseLogger = verboseLogger
    }

    /// Detects the shim role from `argv0` and dispatches the invocation.
    public func dispatch(
        argv0: String,
        arguments: [String],
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ShimDispatchOutcome {
        let role = ShimRole.detect(argv0: argv0)
        return try dispatch(
            role: role,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment
        )
    }

    /// Dispatches an invocation for an explicit ``ShimRole``.
    public func dispatch(
        role: ShimRole,
        arguments: [String],
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ShimDispatchOutcome {
        guard role != .pspm else {
            throw ShimError.unsupportedRoleForShimDispatch(role)
        }

        // Global bypass: `PSPM_DISABLE=1` delegates immediately with zero hydration/harvest or flag injection.
        if CompilationCacheConfig.isTruthy(environment[ExecutableLocator.disableEnvironmentKey]) {
            let realExecutable = try executableLocator.resolveExecutable(
                named: role.rawValue,
                environment: environment
            )
            let sanitizedEnv = executableLocator.sanitizedEnvironment(from: environment)
            let exitCode = try processExecutor.execute(
                ShimExecutionRequest(
                    executablePath: realExecutable,
                    arguments: arguments,
                    workingDirectory: workingDirectory,
                    environment: sanitizedEnv,
                    canReplaceProcess: true
                )
            )
            return ShimDispatchOutcome(
                role: role,
                exitCode: exitCode,
                bypassed: true,
                didHydrate: false,
                didHarvest: false,
                injectedCompilationCache: false,
                executedExecutablePath: realExecutable,
                forwardedArguments: arguments
            )
        }

        switch role {
        case .flutter:
            return try dispatchFlutter(
                arguments: arguments,
                workingDirectory: workingDirectory,
                environment: environment
            )
        case .xcodebuild:
            return try dispatchXcodebuild(
                arguments: arguments,
                workingDirectory: workingDirectory,
                environment: environment
            )
        case .swift:
            return try dispatchSwift(
                arguments: arguments,
                workingDirectory: workingDirectory,
                environment: environment
            )
        case .pspm:
            throw ShimError.unsupportedRoleForShimDispatch(role)
        }
    }

    // MARK: - Flutter Shim

    private func dispatchFlutter(
        arguments: [String],
        workingDirectory: String,
        environment: [String: String]
    ) throws -> ShimDispatchOutcome {
        let analysis = FlutterShimParser.parse(arguments: arguments)
        let realFlutter = try executableLocator.resolveExecutable(
            named: ShimRole.flutter.rawValue,
            environment: environment
        )

        guard analysis.shouldIntercept else {
            let sanitizedEnv = executableLocator.sanitizedEnvironment(from: environment)
            let exitCode = try processExecutor.execute(
                ShimExecutionRequest(
                    executablePath: realFlutter,
                    arguments: analysis.forwardedArguments,
                    workingDirectory: workingDirectory,
                    environment: sanitizedEnv,
                    canReplaceProcess: true
                )
            )
            return ShimDispatchOutcome(
                role: .flutter,
                exitCode: exitCode,
                bypassed: false,
                didHydrate: false,
                didHarvest: false,
                injectedCompilationCache: false,
                executedExecutablePath: realFlutter,
                forwardedArguments: analysis.forwardedArguments
            )
        }

        let childEnv = executableLocator.sanitizedEnvironment(
            from: environment,
            additionalEnvironment: [
                ExecutableLocator.flutterShimActiveEnvironmentKey: "1"
            ]
        )

        guard let initialProject = try? ProjectDetector.detect(in: workingDirectory),
              initialProject.type == .flutter
        else {
            let exitCode = try processExecutor.execute(
                ShimExecutionRequest(
                    executablePath: realFlutter,
                    arguments: analysis.forwardedArguments,
                    workingDirectory: workingDirectory,
                    environment: childEnv,
                    canReplaceProcess: true
                )
            )
            return ShimDispatchOutcome(
                role: .flutter,
                exitCode: exitCode,
                bypassed: false,
                didHydrate: false,
                didHarvest: false,
                injectedCompilationCache: false,
                executedExecutablePath: realFlutter,
                forwardedArguments: analysis.forwardedArguments
            )
        }

        let integrator = makeFlutterIntegrator()
        let syncEngine = PackageSyncEngine(store: store, toolchainProvider: toolchainProvider)

        if analysis.command == .pubGet {
            let exitCode = try processExecutor.execute(
                ShimExecutionRequest(
                    executablePath: realFlutter,
                    arguments: analysis.forwardedArguments,
                    workingDirectory: workingDirectory,
                    environment: childEnv,
                    canReplaceProcess: false
                )
            )

            var didHydrate = false
            if exitCode == 0 {
                let freshProject = (try? ProjectDetector.detect(in: workingDirectory)) ?? initialProject
                let preparedProject: DetectedProject
                do {
                    preparedProject = try integrator.prepareForHydration(
                        project: freshProject,
                        runPubGetIfMissing: false,
                        environment: environment
                    ).project
                } catch {
                    verboseLogger?("Flutter prepareForHydration skipped after pub get: \(error.localizedDescription)")
                    preparedProject = freshProject
                }

                didHydrate = hydrateFlutterTargets(
                    from: preparedProject,
                    platformFilter: nil,
                    syncEngine: syncEngine
                )
            }

            return ShimDispatchOutcome(
                role: .flutter,
                exitCode: exitCode,
                bypassed: false,
                didHydrate: didHydrate,
                didHarvest: false,
                injectedCompilationCache: false,
                executedExecutablePath: realFlutter,
                forwardedArguments: analysis.forwardedArguments
            )
        }

        // Apple-relevant `run`, `build ios/ipa/macos`, or `test`.
        let preparedProject: DetectedProject
        do {
            preparedProject = try integrator.prepareForHydration(
                project: initialProject,
                runPubGetIfMissing: true,
                environment: environment
            ).project
        } catch {
            verboseLogger?("Flutter prepareForHydration warning: \(error.localizedDescription)")
            preparedProject = initialProject
        }

        let didHydrate = hydrateFlutterTargets(
            from: preparedProject,
            platformFilter: analysis.targetPlatform,
            syncEngine: syncEngine
        )

        let exitCode = try processExecutor.execute(
            ShimExecutionRequest(
                executablePath: realFlutter,
                arguments: analysis.forwardedArguments,
                workingDirectory: workingDirectory,
                environment: childEnv,
                canReplaceProcess: false
            )
        )

        var didHarvest = false
        if exitCode == 0 {
            let freshProject = (try? ProjectDetector.detect(in: workingDirectory)) ?? preparedProject
            didHarvest = harvestFlutterTargets(
                from: freshProject,
                platformFilter: analysis.targetPlatform,
                syncEngine: syncEngine
            )
            let toolchainHash = try? toolchainProvider().hash
            _ = try? integrator.recordResolvedDependencies(
                project: freshProject,
                toolchainHash: toolchainHash
            )
        }

        return ShimDispatchOutcome(
            role: .flutter,
            exitCode: exitCode,
            bypassed: false,
            didHydrate: didHydrate,
            didHarvest: didHarvest,
            injectedCompilationCache: false,
            executedExecutablePath: realFlutter,
            forwardedArguments: analysis.forwardedArguments
        )
    }

    private func hydrateFlutterTargets(
        from project: DetectedProject,
        platformFilter: FlutterPlatform?,
        syncEngine: PackageSyncEngine
    ) -> Bool {
        let targetProjects = resolveFlutterTargetProjects(from: project, platformFilter: platformFilter)
        let fileManager = FileManager.default
        var anyHydrated = false

        for targetProject in targetProjects {
            guard targetProject.packageResolvedPath != nil || !targetProject.allPackageResolvedPaths.isEmpty else {
                continue
            }
            let primaryURL = try? syncEngine.resolveSourcePackagesURL(for: targetProject)
            let candidates = (try? syncEngine.resolveCandidateSourcePackagesURLs(for: targetProject)) ?? []
            let destinations = candidates.filter { url in
                url.path == primaryURL?.path || fileManager.fileExists(atPath: url.path)
            }
            for destinationURL in destinations {
                do {
                    _ = try syncEngine.hydrate(
                        project: targetProject,
                        options: HydrateOptions(
                            sourcePackagesOverride: destinationURL.path,
                            verboseLogger: verboseLogger
                        )
                    )
                    anyHydrated = true
                } catch {
                    verboseLogger?("Flutter hydrate skipped for '\(targetProject.rootPath)': \(error.localizedDescription)")
                }
            }
        }

        return anyHydrated
    }

    private func harvestFlutterTargets(
        from project: DetectedProject,
        platformFilter: FlutterPlatform?,
        syncEngine: PackageSyncEngine
    ) -> Bool {
        let targetProjects = resolveFlutterTargetProjects(from: project, platformFilter: platformFilter)
        let fileManager = FileManager.default
        var anyHarvested = false

        for targetProject in targetProjects {
            let candidates = (try? syncEngine.resolveCandidateSourcePackagesURLs(for: targetProject)) ?? []
            for sourcePackagesURL in candidates where fileManager.fileExists(atPath: sourcePackagesURL.path) {
                do {
                    _ = try syncEngine.harvest(
                        project: targetProject,
                        options: HarvestOptions(
                            sourcePackagesOverride: sourcePackagesURL.path,
                            verboseLogger: verboseLogger
                        )
                    )
                    anyHarvested = true
                } catch {
                    verboseLogger?("Flutter harvest warning for '\(targetProject.rootPath)': \(error.localizedDescription)")
                }
            }
        }

        return anyHarvested
    }

    private func resolveFlutterTargetProjects(
        from project: DetectedProject,
        platformFilter: FlutterPlatform?
    ) -> [DetectedProject] {
        guard let targets = project.flutterInfo?.targets else {
            return [project]
        }

        let filtered = targets.filter { target in
            platformFilter == nil || target.platform == platformFilter
        }
        var projects: [DetectedProject] = []

        for target in filtered {
            if let workspacePath = target.workspacePath,
               let detected = try? ProjectDetector.detect(workspacePath: workspacePath) {
                projects.append(detected)
            } else if let projectPath = target.projectPath,
                      let detected = try? ProjectDetector.detect(projectPath: projectPath) {
                projects.append(detected)
            }
        }

        if projects.isEmpty {
            return [project]
        }
        return projects
    }

    // MARK: - Xcodebuild Shim

    private func dispatchXcodebuild(
        arguments: [String],
        workingDirectory: String,
        environment: [String: String]
    ) throws -> ShimDispatchOutcome {
        let analysis = XcodebuildShimParser.parse(arguments: arguments)
        let realXcodebuild = try executableLocator.resolveExecutable(
            named: ShimRole.xcodebuild.rawValue,
            environment: environment
        )
        let sanitizedEnv = executableLocator.sanitizedEnvironment(from: environment)
        let syncEngine = PackageSyncEngine(store: store, toolchainProvider: toolchainProvider)

        let derivedDataSourcePackagesOverride: String? = analysis.derivedDataPath.map { rawPath in
            let canonical = DerivedDataPathCalculator.canonicalizePath(
                rawPath,
                currentDirectory: workingDirectory
            )
            return URL(fileURLWithPath: canonical)
                .appendingPathComponent("SourcePackages")
                .standardizedFileURL
                .path
        }

        let flutterShimActive = CompilationCacheConfig.isTruthy(
            environment[ExecutableLocator.flutterShimActiveEnvironmentKey]
        )
        let hasClonedOverride = analysis.clonedSourcePackagesDirPath != nil

        var detectedProject: DetectedProject?
        if analysis.shouldHydrate || analysis.shouldHarvest {
            detectedProject = detectXcodeProject(analysis: analysis, workingDirectory: workingDirectory)
        }

        var didHydrate = false
        if analysis.shouldHydrate && !hasClonedOverride && !flutterShimActive, var project = detectedProject {
            if project.type == .flutter {
                let integrator = makeFlutterIntegrator()
                if let prepared = try? integrator.prepareForHydration(
                    project: project,
                    runPubGetIfMissing: false,
                    environment: environment
                ) {
                    project = prepared.project
                    detectedProject = project
                }
            }

            if project.packageResolvedPath != nil || !project.allPackageResolvedPaths.isEmpty {
                do {
                    _ = try syncEngine.hydrate(
                        project: project,
                        options: HydrateOptions(
                            sourcePackagesOverride: derivedDataSourcePackagesOverride,
                            verboseLogger: verboseLogger
                        )
                    )
                    didHydrate = true
                } catch {
                    verboseLogger?("xcodebuild hydrate skipped: \(error.localizedDescription)")
                }
            }
        }

        var finalArguments = arguments
        var injectedCompilationCache = false
        if analysis.shouldInjectCompilationCache {
            let cacheConfig = CompilationCacheConfig.resolve(
                environment: environment,
                homeDirectory: homeDirectory
            )
            if cacheConfig.isEnabled
                && cacheProbe.isXcodeCompilationCacheSupported(
                    xcodebuildPath: realXcodebuild,
                    environment: sanitizedEnv
                ) {
                try? cacheConfig.ensureCacheDirectoryExists()
                finalArguments.append(contentsOf: cacheConfig.xcodebuildArguments)
                injectedCompilationCache = true
            }
        }

        let exitCode = try processExecutor.execute(
            ShimExecutionRequest(
                executablePath: realXcodebuild,
                arguments: finalArguments,
                workingDirectory: workingDirectory,
                environment: sanitizedEnv,
                canReplaceProcess: !analysis.shouldHarvest
            )
        )

        var didHarvest = false
        if analysis.shouldHarvest && exitCode == 0 {
            let freshProject = detectXcodeProject(analysis: analysis, workingDirectory: workingDirectory)
                ?? detectedProject
            if let freshProject {
                let harvestOverride = analysis.clonedSourcePackagesDirPath.map {
                    DerivedDataPathCalculator.canonicalizePath($0, currentDirectory: workingDirectory)
                } ?? derivedDataSourcePackagesOverride

                if let sourcePackagesURL = try? syncEngine.resolveSourcePackagesURL(
                    for: freshProject,
                    overridePath: harvestOverride
                ),
                   FileManager.default.fileExists(atPath: sourcePackagesURL.path) {
                    do {
                        _ = try syncEngine.harvest(
                            project: freshProject,
                            options: HarvestOptions(
                                sourcePackagesOverride: harvestOverride,
                                verboseLogger: verboseLogger
                            )
                        )
                        didHarvest = true
                    } catch {
                        verboseLogger?("xcodebuild harvest warning: \(error.localizedDescription)")
                    }
                }

                if freshProject.type == .flutter {
                    let integrator = makeFlutterIntegrator()
                    let toolchainHash = try? toolchainProvider().hash
                    _ = try? integrator.recordResolvedDependencies(
                        project: freshProject,
                        toolchainHash: toolchainHash
                    )
                }
            }
        }

        return ShimDispatchOutcome(
            role: .xcodebuild,
            exitCode: exitCode,
            bypassed: false,
            didHydrate: didHydrate,
            didHarvest: didHarvest,
            injectedCompilationCache: injectedCompilationCache,
            executedExecutablePath: realXcodebuild,
            forwardedArguments: finalArguments
        )
    }

    private func detectXcodeProject(
        analysis: XcodebuildCommandAnalysis,
        workingDirectory: String
    ) -> DetectedProject? {
        try? ProjectDetector.detect(
            in: workingDirectory,
            projectPath: analysis.projectPath,
            workspacePath: analysis.workspacePath,
            currentDirectory: workingDirectory
        )
    }

    // MARK: - Swift Shim

    private func dispatchSwift(
        arguments: [String],
        workingDirectory: String,
        environment: [String: String]
    ) throws -> ShimDispatchOutcome {
        let analysis = SwiftShimParser.parse(arguments: arguments)
        let realSwift = try executableLocator.resolveExecutable(
            named: ShimRole.swift.rawValue,
            environment: environment
        )
        let sanitizedEnv = executableLocator.sanitizedEnvironment(from: environment)

        let packageRoot = analysis.packagePath.map {
            DerivedDataPathCalculator.canonicalizePath($0, currentDirectory: workingDirectory)
        } ?? workingDirectory
        let manifestPath = URL(fileURLWithPath: packageRoot)
            .appendingPathComponent("Package.swift")
            .standardizedFileURL
            .path

        var isDir: ObjCBool = false
        let manifestExists = FileManager.default.fileExists(atPath: manifestPath, isDirectory: &isDir)
            && !isDir.boolValue

        guard analysis.shouldIntercept && manifestExists else {
            let exitCode = try processExecutor.execute(
                ShimExecutionRequest(
                    executablePath: realSwift,
                    arguments: arguments,
                    workingDirectory: workingDirectory,
                    environment: sanitizedEnv,
                    canReplaceProcess: true
                )
            )
            return ShimDispatchOutcome(
                role: .swift,
                exitCode: exitCode,
                bypassed: false,
                didHydrate: false,
                didHarvest: false,
                injectedCompilationCache: false,
                executedExecutablePath: realSwift,
                forwardedArguments: arguments
            )
        }

        let syncEngine = PackageSyncEngine(store: store, toolchainProvider: toolchainProvider)
        let sourcePackagesOverride = analysis.scratchPath.map {
            DerivedDataPathCalculator.canonicalizePath($0, currentDirectory: workingDirectory)
        }

        var didHydrate = false
        if let project = try? ProjectDetector.detect(
            projectPath: manifestPath,
            currentDirectory: workingDirectory
        ),
           project.packageResolvedPath != nil || !project.allPackageResolvedPaths.isEmpty {
            do {
                _ = try syncEngine.hydrate(
                    project: project,
                    options: HydrateOptions(
                        sourcePackagesOverride: sourcePackagesOverride,
                        verboseLogger: verboseLogger
                    )
                )
                didHydrate = true
            } catch {
                verboseLogger?("swift hydrate skipped: \(error.localizedDescription)")
            }
        }

        var finalArguments = arguments
        var injectedCompilationCache = false
        if analysis.supportsBuildCacheFlag && !analysis.hasExplicitBuildCacheFlag {
            let cacheConfig = CompilationCacheConfig.resolve(
                environment: environment,
                homeDirectory: homeDirectory
            )
            if cacheConfig.isEnabled
                && cacheProbe.isSwiftBuildCacheSupported(
                    swiftPath: realSwift,
                    environment: sanitizedEnv
                ) {
                try? cacheConfig.ensureCacheDirectoryExists()
                finalArguments = analysis.argumentsWithBuildCacheEnabled(from: arguments)
                injectedCompilationCache = true
            }
        }

        let exitCode = try processExecutor.execute(
            ShimExecutionRequest(
                executablePath: realSwift,
                arguments: finalArguments,
                workingDirectory: workingDirectory,
                environment: sanitizedEnv,
                canReplaceProcess: false
            )
        )

        var didHarvest = false
        if exitCode == 0,
           let freshProject = try? ProjectDetector.detect(
               projectPath: manifestPath,
               currentDirectory: workingDirectory
           ),
           let sourcePackagesURL = try? syncEngine.resolveSourcePackagesURL(
               for: freshProject,
               overridePath: sourcePackagesOverride
           ),
           FileManager.default.fileExists(atPath: sourcePackagesURL.path) {
            do {
                _ = try syncEngine.harvest(
                    project: freshProject,
                    options: HarvestOptions(
                        sourcePackagesOverride: sourcePackagesOverride,
                        verboseLogger: verboseLogger
                    )
                )
                didHarvest = true
            } catch {
                verboseLogger?("swift harvest warning: \(error.localizedDescription)")
            }
        }

        return ShimDispatchOutcome(
            role: .swift,
            exitCode: exitCode,
            bypassed: false,
            didHydrate: didHydrate,
            didHarvest: didHarvest,
            injectedCompilationCache: injectedCompilationCache,
            executedExecutablePath: realSwift,
            forwardedArguments: finalArguments
        )
    }

    // MARK: - Helpers

    private func makeFlutterIntegrator() -> FlutterSPMIntegrator {
        FlutterSPMIntegrator(
            store: store,
            executableResolver: LocatorBackedFlutterExecutableResolver(locator: executableLocator),
            commandRunner: flutterCommandRunner
        )
    }
}

private struct LocatorBackedFlutterExecutableResolver: FlutterExecutableResolving {
    let locator: any ExecutableLocating

    func resolveFlutterExecutable(environment: [String: String]) throws -> String {
        try locator.resolveExecutable(named: ShimRole.flutter.rawValue, environment: environment)
    }

    func sanitizedEnvironment(from environment: [String: String]) -> [String: String] {
        locator.sanitizedEnvironment(
            from: environment,
            additionalEnvironment: [
                ExecutableLocator.flutterShimActiveEnvironmentKey: "1"
            ]
        )
    }
}

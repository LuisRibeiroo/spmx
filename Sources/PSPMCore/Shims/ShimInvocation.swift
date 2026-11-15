import Darwin
import Foundation

/// Identifies which multicall persona `pspm` was invoked as via `argv[0]`.
public enum ShimRole: String, CaseIterable, Equatable, Hashable, Sendable {
    case pspm
    case flutter
    case xcodebuild
    case swift

    /// Detects the active multicall role from `argv[0]`.
    public static func detect(argv0: String) -> ShimRole {
        let trimmed = argv0.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .pspm
        }
        let name = URL(fileURLWithPath: trimmed).lastPathComponent
        return ShimRole(rawValue: name) ?? .pspm
    }
}

/// Errors thrown during shim dispatching or process execution.
public enum ShimError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedRoleForShimDispatch(ShimRole)
    case processExecutionFailed(executablePath: String, errno: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedRoleForShimDispatch(let role):
            return "Role '\(role.rawValue)' is not a PATH shim role."
        case .processExecutionFailed(let path, let code, let message):
            return "Failed to execute '\(path)' (errno \(code): \(message))."
        }
    }
}

/// Configuration for the shared LLVM CAS / SwiftPM compilation cache (`~/.pspm/compilation-cache`).
public struct CompilationCacheConfig: Equatable, Sendable {
    public static let directoryEnvironmentKey = "PSPM_COMPILATION_CACHE_DIR"
    public static let disableEnvironmentKey = "PSPM_NO_COMPILE_CACHE"

    public let cacheDirectory: URL
    public let isEnabled: Bool

    public init(cacheDirectory: URL, isEnabled: Bool) {
        self.cacheDirectory = cacheDirectory.standardizedFileURL
        self.isEnabled = isEnabled
    }

    /// Resolves the compilation cache directory (`~/.pspm/compilation-cache` or `PSPM_COMPILATION_CACHE_DIR`)
    /// and whether compilation caching is enabled (`PSPM_NO_COMPILE_CACHE=1` disables it).
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> CompilationCacheConfig {
        let directory = defaultCacheDirectory(environment: environment, homeDirectory: homeDirectory)
        let disabled = isTruthy(environment[disableEnvironmentKey])
        return CompilationCacheConfig(cacheDirectory: directory, isEnabled: !disabled)
    }

    /// Resolves `~/.pspm/compilation-cache` or `PSPM_COMPILATION_CACHE_DIR`.
    public static func defaultCacheDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let override = environment[directoryEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        return homeDirectory
            .appendingPathComponent(".pspm")
            .appendingPathComponent("compilation-cache")
            .standardizedFileURL
    }

    /// Ensures the shared compilation cache directory exists on disk.
    public func ensureCacheDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Build settings arguments injected into `xcodebuild` build actions on Xcode 16+.
    public var xcodebuildArguments: [String] {
        [
            "COMPILATION_CACHE_ENABLE_CACHING=YES",
            "COMPILATION_CACHE_ENABLE_PLUGIN_CACHING=YES",
            "COMPILATION_CACHE_CAS_PATH=\(cacheDirectory.path)"
        ]
    }

    /// Parses boolean-style environment flags (`1`, `true`, `yes`).
    public static func isTruthy(_ value: String?) -> Bool {
        guard let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !normalized.isEmpty
        else {
            return false
        }
        return normalized == "1" || normalized == "true" || normalized == "yes"
    }

    /// Extracts the Xcode major version from `xcodebuild -version` output (e.g. `"Xcode 16.2"` -> `16`).
    public static func parseXcodeMajorVersion(from versionOutput: String) -> Int? {
        guard let range = versionOutput.range(of: "Xcode ", options: [.caseInsensitive]) else {
            return nil
        }
        let tail = versionOutput[range.upperBound...]
        let digits = tail.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    /// Returns `true` when `xcodebuild -version` output indicates Xcode 16 or newer.
    public static func isXcodeSupported(versionOutput: String) -> Bool {
        (parseXcodeMajorVersion(from: versionOutput) ?? 0) >= 16
    }

    /// Extracts the Swift `(major, minor)` version from `swift --version` output.
    public static func parseSwiftVersion(from versionOutput: String) -> (major: Int, minor: Int)? {
        guard let range = versionOutput.range(of: "Swift version ", options: [.caseInsensitive]) else {
            return nil
        }
        let tail = versionOutput[range.upperBound...]
        let majorDigits = tail.prefix { $0.isNumber }
        guard !majorDigits.isEmpty, let major = Int(majorDigits) else {
            return nil
        }
        let afterMajor = tail.dropFirst(majorDigits.count)
        if afterMajor.first == "." {
            let minorDigits = afterMajor.dropFirst().prefix { $0.isNumber }
            let minor = Int(minorDigits) ?? 0
            return (major, minor)
        }
        return (major, 0)
    }

    /// Returns `true` when `swift --version` output indicates Swift 6 or newer.
    public static func isSwiftSupported(versionOutput: String) -> Bool {
        (parseSwiftVersion(from: versionOutput)?.major ?? 0) >= 6
    }
}

/// Probes whether the active `xcodebuild` and `swift` toolchains support native compilation caching.
public protocol CompilationCacheProbing: Sendable {
    func isXcodeCompilationCacheSupported(
        xcodebuildPath: String,
        environment: [String: String]
    ) -> Bool

    func isSwiftBuildCacheSupported(
        swiftPath: String,
        environment: [String: String]
    ) -> Bool
}

/// Default toolchain compilation-cache probe invoking `xcodebuild -version` and `swift --version` / `swift build --help`.
public struct DefaultCompilationCacheProbe: CompilationCacheProbing, Sendable {
    public typealias CommandRunner = @Sendable (
        _ executablePath: String,
        _ arguments: [String],
        _ environment: [String: String]
    ) throws -> CommandResult

    private let runner: CommandRunner

    public init(runner: @escaping CommandRunner = DefaultCompilationCacheProbe.defaultRunner) {
        self.runner = runner
    }

    public func isXcodeCompilationCacheSupported(
        xcodebuildPath: String,
        environment: [String: String]
    ) -> Bool {
        guard let result = try? runner(xcodebuildPath, ["-version"], environment),
              result.exitCode == 0
        else {
            return false
        }
        return CompilationCacheConfig.isXcodeSupported(versionOutput: result.stdout)
    }

    public func isSwiftBuildCacheSupported(
        swiftPath: String,
        environment: [String: String]
    ) -> Bool {
        guard let versionResult = try? runner(swiftPath, ["--version"], environment),
              versionResult.exitCode == 0,
              CompilationCacheConfig.isSwiftSupported(versionOutput: versionResult.stdout)
        else {
            return false
        }
        guard let helpResult = try? runner(swiftPath, ["build", "--help"], environment),
              helpResult.exitCode == 0
        else {
            return false
        }
        return helpResult.stdout.contains("--enable-build-cache")
            || helpResult.stderr.contains("--enable-build-cache")
    }

    public static let defaultRunner: CommandRunner = { executablePath, arguments, environment in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}

/// Request passed to ``ShimProcessExecuting`` to run a real tool binary.
public struct ShimExecutionRequest: Equatable, Sendable {
    public let executablePath: String
    public let arguments: [String]
    public let workingDirectory: String
    public let environment: [String: String]
    public let canReplaceProcess: Bool

    public init(
        executablePath: String,
        arguments: [String],
        workingDirectory: String,
        environment: [String: String],
        canReplaceProcess: Bool
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.canReplaceProcess = canReplaceProcess
    }
}

/// Abstraction for executing the underlying real binary so callers and tests can inject process execution.
public protocol ShimProcessExecuting: Sendable {
    func execute(_ request: ShimExecutionRequest) throws -> Int32
}

/// Default process executor using `execve` for zero-overhead pass-throughs when allowed,
/// or `Foundation.Process` with inherited `stdin`/`stdout`/`stderr` when post-execution harvesting is required.
public struct SystemShimProcessExecutor: ShimProcessExecuting, Sendable {
    public let allowProcessReplacement: Bool

    public init(allowProcessReplacement: Bool = true) {
        self.allowProcessReplacement = allowProcessReplacement
    }

    public func execute(_ request: ShimExecutionRequest) throws -> Int32 {
        if allowProcessReplacement && request.canReplaceProcess {
            try replaceCurrentProcess(request)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: request.executablePath)
        process.arguments = request.arguments
        process.currentDirectoryURL = URL(fileURLWithPath: request.workingDirectory)
        process.environment = request.environment
        // Leave standardInput/standardOutput/standardError unset so child inherits parent TTY & FDs directly.

        do {
            try process.run()
        } catch {
            let code = (error as NSError).code
            throw ShimError.processExecutionFailed(
                executablePath: request.executablePath,
                errno: Int32(code),
                message: error.localizedDescription
            )
        }

        process.waitUntilExit()
        if process.terminationReason == .uncaughtSignal {
            return 128 + process.terminationStatus
        }
        return process.terminationStatus
    }

    private func replaceCurrentProcess(_ request: ShimExecutionRequest) throws -> Never {
        let currentDir = FileManager.default.currentDirectoryPath
        if request.workingDirectory != currentDir {
            if Darwin.chdir(request.workingDirectory) != 0 {
                let code = Darwin.errno
                throw ShimError.processExecutionFailed(
                    executablePath: request.executablePath,
                    errno: code,
                    message: String(cString: strerror(code))
                )
            }
        }

        let argvStrings = [request.executablePath] + request.arguments
        var cArgs: [UnsafeMutablePointer<CChar>?] = argvStrings.map { strdup($0) }
        cArgs.append(nil)
        defer {
            for case let ptr? in cArgs {
                free(ptr)
            }
        }

        let envStrings = request.environment.map { "\($0.key)=\($0.value)" }
        var cEnv: [UnsafeMutablePointer<CChar>?] = envStrings.map { strdup($0) }
        cEnv.append(nil)
        defer {
            for case let ptr? in cEnv {
                free(ptr)
            }
        }

        Darwin.execve(request.executablePath, cArgs, cEnv)
        let code = Darwin.errno
        throw ShimError.processExecutionFailed(
            executablePath: request.executablePath,
            errno: code,
            message: String(cString: strerror(code))
        )
    }
}

// MARK: - Lightweight Argument Parsers

/// Parsed representation of a `flutter` CLI invocation.
public struct FlutterCommandAnalysis: Equatable, Sendable {
    public enum Command: Equatable, Sendable {
        case run
        case build(platform: FlutterPlatform?)
        case test(isNonApple: Bool)
        case pubGet
        case other
    }

    public let command: Command
    public let targetPlatform: FlutterPlatform?
    public let hasNoPSPMFlag: Bool
    public let hasHelpOrVersionFlag: Bool
    public let shouldIntercept: Bool
    public let forwardedArguments: [String]

    public init(
        command: Command,
        targetPlatform: FlutterPlatform?,
        hasNoPSPMFlag: Bool,
        hasHelpOrVersionFlag: Bool,
        shouldIntercept: Bool,
        forwardedArguments: [String]
    ) {
        self.command = command
        self.targetPlatform = targetPlatform
        self.hasNoPSPMFlag = hasNoPSPMFlag
        self.hasHelpOrVersionFlag = hasHelpOrVersionFlag
        self.shouldIntercept = shouldIntercept
        self.forwardedArguments = forwardedArguments
    }
}

/// Lightweight parser for `flutter` shim invocations.
public enum FlutterShimParser {
    private static let valueTakingFlags: Set<String> = [
        "-d", "--device-id",
        "--local-engine", "--local-engine-src-path", "--local-engine-host",
        "--packages", "--flutter-root",
        "-t", "--target",
        "--flavor",
        "-p", "--platform",
        "--reporter", "--name", "--plain-name", "--tags", "--exclude-tags",
        "--concurrency", "-j",
        "--dart-define", "--dart-define-from-file",
        "--build-name", "--build-number",
        "--export-options-plist", "--export-method",
        "--split-debug-info"
    ]

    private static let nonApplePlatforms: Set<String> = [
        "chrome", "firefox", "edge", "node", "web", "web-server", "android", "linux", "windows"
    ]

    public static func parse(arguments: [String]) -> FlutterCommandAnalysis {
        var forwardedArguments: [String] = []
        var positionals: [String] = []
        var hasNoPSPMFlag = false
        var hasHelpOrVersionFlag = false
        var deviceID: String?
        var testPlatform: String?
        var awaitingFlag: String?
        var afterDoubleDash = false

        for arg in arguments {
            if arg == "--no-pspm" && !afterDoubleDash {
                hasNoPSPMFlag = true
                continue
            }
            forwardedArguments.append(arg)

            if afterDoubleDash {
                continue
            }
            if arg == "--" {
                afterDoubleDash = true
                continue
            }

            if let flag = awaitingFlag {
                awaitingFlag = nil
                if flag == "-d" || flag == "--device-id" {
                    deviceID = arg
                } else if flag == "-p" || flag == "--platform" {
                    testPlatform = arg
                }
                continue
            }

            if arg == "--help" || arg == "-h" || arg == "--version" {
                hasHelpOrVersionFlag = true
                continue
            }

            if arg.hasPrefix("--device-id=") {
                deviceID = String(arg.dropFirst("--device-id=".count))
                continue
            }
            if arg.hasPrefix("-d=") {
                deviceID = String(arg.dropFirst("-d=".count))
                continue
            }
            if arg.hasPrefix("--platform=") {
                testPlatform = String(arg.dropFirst("--platform=".count))
                continue
            }
            if arg.hasPrefix("-p=") {
                testPlatform = String(arg.dropFirst("-p=".count))
                continue
            }

            if valueTakingFlags.contains(arg) {
                awaitingFlag = arg
                continue
            }

            if arg.hasPrefix("-") {
                continue
            }

            positionals.append(arg)
        }

        let command: FlutterCommandAnalysis.Command
        var targetPlatform: FlutterPlatform?
        var shouldIntercept = false

        switch positionals.first {
        case "run":
            command = .run
            let lowerDevice = deviceID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isExplicitNonAppleDevice = lowerDevice.map { nonApplePlatforms.contains($0) } ?? false
            if lowerDevice == "macos" {
                targetPlatform = .macos
            } else if lowerDevice == "ios" || lowerDevice == "iphone" || lowerDevice == "ipad" {
                targetPlatform = .ios
            }
            shouldIntercept = !hasNoPSPMFlag && !hasHelpOrVersionFlag && !isExplicitNonAppleDevice

        case "build":
            let buildTarget = positionals.dropFirst().first?.lowercased()
            switch buildTarget {
            case "ios", "ipa":
                targetPlatform = .ios
                command = .build(platform: .ios)
                shouldIntercept = !hasNoPSPMFlag && !hasHelpOrVersionFlag
            case "macos":
                targetPlatform = .macos
                command = .build(platform: .macos)
                shouldIntercept = !hasNoPSPMFlag && !hasHelpOrVersionFlag
            default:
                command = .build(platform: nil)
                shouldIntercept = false
            }

        case "test":
            let lowerPlatform = testPlatform?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isNonApple = lowerPlatform.map { nonApplePlatforms.contains($0) } ?? false
            command = .test(isNonApple: isNonApple)
            if lowerPlatform == "macos" {
                targetPlatform = .macos
            } else if lowerPlatform == "ios" {
                targetPlatform = .ios
            }
            shouldIntercept = !hasNoPSPMFlag && !hasHelpOrVersionFlag && !isNonApple

        case "pub":
            if positionals.dropFirst().first == "get" {
                command = .pubGet
                shouldIntercept = !hasNoPSPMFlag && !hasHelpOrVersionFlag
            } else {
                command = .other
                shouldIntercept = false
            }

        default:
            command = .other
            shouldIntercept = false
        }

        return FlutterCommandAnalysis(
            command: command,
            targetPlatform: targetPlatform,
            hasNoPSPMFlag: hasNoPSPMFlag,
            hasHelpOrVersionFlag: hasHelpOrVersionFlag,
            shouldIntercept: shouldIntercept,
            forwardedArguments: forwardedArguments
        )
    }
}

/// Parsed representation of an `xcodebuild` CLI invocation.
public struct XcodebuildCommandAnalysis: Equatable, Sendable {
    public static let buildActionNames: Set<String> = [
        "build",
        "archive",
        "test",
        "build-for-testing"
    ]

    public let workspacePath: String?
    public let projectPath: String?
    public let clonedSourcePackagesDirPath: String?
    public let derivedDataPath: String?
    public let hasSchemeOrTarget: Bool
    public let hasExplicitCompilationCacheArgs: Bool
    public let hasResolvePackageDependencies: Bool
    public let hasQueryFlag: Bool
    public let actions: [String]

    public init(
        workspacePath: String?,
        projectPath: String?,
        clonedSourcePackagesDirPath: String?,
        derivedDataPath: String?,
        hasSchemeOrTarget: Bool,
        hasExplicitCompilationCacheArgs: Bool,
        hasResolvePackageDependencies: Bool,
        hasQueryFlag: Bool,
        actions: [String]
    ) {
        self.workspacePath = workspacePath
        self.projectPath = projectPath
        self.clonedSourcePackagesDirPath = clonedSourcePackagesDirPath
        self.derivedDataPath = derivedDataPath
        self.hasSchemeOrTarget = hasSchemeOrTarget
        self.hasExplicitCompilationCacheArgs = hasExplicitCompilationCacheArgs
        self.hasResolvePackageDependencies = hasResolvePackageDependencies
        self.hasQueryFlag = hasQueryFlag
        self.actions = actions
    }

    /// True when no explicit action was supplied on a project/workspace/scheme build invocation (implicit `build`).
    public var isImplicitBuild: Bool {
        !hasQueryFlag
            && !hasResolvePackageDependencies
            && actions.isEmpty
            && (workspacePath != nil || projectPath != nil || hasSchemeOrTarget)
    }

    /// True for `build`, `archive`, `test`, `build-for-testing`, or implicit `build`.
    public var isBuildAction: Bool {
        guard !hasQueryFlag else { return false }
        return actions.contains(where: { Self.buildActionNames.contains($0) }) || isImplicitBuild
    }

    /// True when `DerivedData/.../SourcePackages` should be hydrated before execution (unless overridden/already hydrated).
    public var shouldHydrate: Bool {
        guard !hasQueryFlag else { return false }
        return hasResolvePackageDependencies || isBuildAction || actions.contains("test-without-building")
    }

    /// True when `harvest` should run after `xcodebuild` succeeds.
    public var shouldHarvest: Bool {
        guard !hasQueryFlag else { return false }
        return hasResolvePackageDependencies || isBuildAction
    }

    /// True when `COMPILATION_CACHE_*` flags should be injected (subject to Xcode 16+ & `PSPM_NO_COMPILE_CACHE`).
    public var shouldInjectCompilationCache: Bool {
        isBuildAction && !hasExplicitCompilationCacheArgs
    }
}

/// Lightweight parser for `xcodebuild` shim invocations.
public enum XcodebuildShimParser {
    private static let valueTakingFlags: Set<String> = [
        "-workspace",
        "-project",
        "-clonedSourcePackagesDirPath",
        "-derivedDataPath",
        "-scheme",
        "-target",
        "-configuration",
        "-sdk",
        "-destination",
        "-archivePath",
        "-resultBundlePath",
        "-xcconfig",
        "-toolchain",
        "-jobs",
        "-resultStreamVersion",
        "-destination-timeout",
        "-testPlan",
        "-exportOptionsPlist",
        "-exportPath",
        "-exportArchivePath",
        "-localizationPath",
        "-exportLanguage",
        "-authenticationKeyPath",
        "-authenticationKeyID",
        "-authenticationKeyIssuerID",
        "-packageCachePath",
        "-defaultPackageRegistryURL",
        "-scmProvider"
    ]

    private static let queryFlags: Set<String> = [
        "-version",
        "-help",
        "-usage",
        "-list",
        "-showsdks",
        "-showBuildSettings",
        "-showdestinations",
        "-showTestPlans",
        "-checkFirstLaunchStatus",
        "-runFirstLaunch",
        "-exportArchive",
        "-exportLocalizations",
        "-importLocalizations"
    ]

    public static func parse(arguments: [String]) -> XcodebuildCommandAnalysis {
        var workspacePath: String?
        var projectPath: String?
        var clonedSourcePackagesDirPath: String?
        var derivedDataPath: String?
        var hasSchemeOrTarget = false
        var hasExplicitCompilationCacheArgs = false
        var hasResolvePackageDependencies = false
        var hasQueryFlag = false
        var actions: [String] = []
        var awaitingFlag: String?

        for arg in arguments {
            if let flag = awaitingFlag {
                awaitingFlag = nil
                switch flag {
                case "-workspace":
                    workspacePath = arg
                case "-project":
                    projectPath = arg
                case "-clonedSourcePackagesDirPath":
                    clonedSourcePackagesDirPath = arg
                case "-derivedDataPath":
                    derivedDataPath = arg
                case "-scheme", "-target":
                    hasSchemeOrTarget = true
                default:
                    break
                }
                continue
            }

            if arg == "-resolvePackageDependencies" {
                hasResolvePackageDependencies = true
                continue
            }

            if queryFlags.contains(arg) {
                hasQueryFlag = true
                continue
            }

            if arg.hasPrefix("-workspace=") {
                workspacePath = String(arg.dropFirst("-workspace=".count))
                continue
            }
            if arg.hasPrefix("-project=") {
                projectPath = String(arg.dropFirst("-project=".count))
                continue
            }
            if arg.hasPrefix("-clonedSourcePackagesDirPath=") {
                clonedSourcePackagesDirPath = String(arg.dropFirst("-clonedSourcePackagesDirPath=".count))
                continue
            }
            if arg.hasPrefix("-derivedDataPath=") {
                derivedDataPath = String(arg.dropFirst("-derivedDataPath=".count))
                continue
            }
            if arg.hasPrefix("-scheme=") || arg.hasPrefix("-target=") {
                hasSchemeOrTarget = true
                continue
            }

            if valueTakingFlags.contains(arg) {
                awaitingFlag = arg
                continue
            }

            if arg.hasPrefix("-") {
                if arg.hasPrefix("-DCOMPILATION_CACHE_") {
                    hasExplicitCompilationCacheArgs = true
                }
                continue
            }

            if let equalsIndex = arg.firstIndex(of: "=") {
                let key = arg[..<equalsIndex]
                if key.hasPrefix("COMPILATION_CACHE_") {
                    hasExplicitCompilationCacheArgs = true
                }
                continue
            }

            actions.append(arg)
        }

        return XcodebuildCommandAnalysis(
            workspacePath: workspacePath,
            projectPath: projectPath,
            clonedSourcePackagesDirPath: clonedSourcePackagesDirPath,
            derivedDataPath: derivedDataPath,
            hasSchemeOrTarget: hasSchemeOrTarget,
            hasExplicitCompilationCacheArgs: hasExplicitCompilationCacheArgs,
            hasResolvePackageDependencies: hasResolvePackageDependencies,
            hasQueryFlag: hasQueryFlag,
            actions: actions
        )
    }
}

/// Parsed representation of a `swift` CLI invocation.
public struct SwiftCommandAnalysis: Equatable, Sendable {
    public enum Subcommand: Equatable, Sendable {
        case build
        case test
        case run
        case packageResolve
        case other
    }

    public let subcommand: Subcommand
    public let subcommandArgumentIndex: Int?
    public let packagePath: String?
    public let scratchPath: String?
    public let hasHelpOrVersionFlag: Bool
    public let hasExplicitBuildCacheFlag: Bool

    public init(
        subcommand: Subcommand,
        subcommandArgumentIndex: Int?,
        packagePath: String?,
        scratchPath: String?,
        hasHelpOrVersionFlag: Bool,
        hasExplicitBuildCacheFlag: Bool
    ) {
        self.subcommand = subcommand
        self.subcommandArgumentIndex = subcommandArgumentIndex
        self.packagePath = packagePath
        self.scratchPath = scratchPath
        self.hasHelpOrVersionFlag = hasHelpOrVersionFlag
        self.hasExplicitBuildCacheFlag = hasExplicitBuildCacheFlag
    }

    /// True when the invocation targets a SwiftPM dependency/build command rather than a query or unrelated subcommand.
    public var shouldIntercept: Bool {
        subcommand != .other && !hasHelpOrVersionFlag
    }

    /// True when `--enable-build-cache` is supported by the subcommand syntax (`build`, `test`, `run`).
    public var supportsBuildCacheFlag: Bool {
        switch subcommand {
        case .build, .test, .run:
            return true
        case .packageResolve, .other:
            return false
        }
    }

    /// Returns arguments with `--enable-build-cache` inserted directly after the subcommand when applicable.
    public func argumentsWithBuildCacheEnabled(from originalArguments: [String]) -> [String] {
        guard let index = subcommandArgumentIndex, index < originalArguments.count else {
            return originalArguments
        }
        var updated = originalArguments
        updated.insert("--enable-build-cache", at: index + 1)
        return updated
    }
}

/// Lightweight parser for `swift` shim invocations.
public enum SwiftShimParser {
    private static let valueTakingFlags: Set<String> = [
        "--package-path",
        "--scratch-path",
        "--build-path",
        "--cache-path",
        "--config-path",
        "--security-path",
        "--pkg-config-path",
        "-Xcc", "-Xcxx", "-Xlinker", "-Xswiftc", "-Xmanifest",
        "-c", "--configuration",
        "--arch", "--triple", "--sdk", "--toolchain", "--sanitize",
        "-j", "--jobs",
        "--target", "--product",
        "--filter", "--skip",
        "--num-workers", "--xunit-output"
    ]

    public static func parse(arguments: [String]) -> SwiftCommandAnalysis {
        var subcommand: SwiftCommandAnalysis.Subcommand?
        var subcommandArgumentIndex: Int?
        var sawPackageCommand = false
        var packagePath: String?
        var scratchPath: String?
        var hasHelpOrVersionFlag = false
        var hasExplicitBuildCacheFlag = false
        var awaitingFlag: String?

        for (index, arg) in arguments.enumerated() {
            if arg == "--" {
                break
            }

            if let flag = awaitingFlag {
                awaitingFlag = nil
                switch flag {
                case "--package-path":
                    packagePath = arg
                case "--scratch-path", "--build-path":
                    scratchPath = arg
                default:
                    break
                }
                continue
            }

            if arg == "--help" || arg == "-h" || arg == "--version" || arg == "-version" {
                hasHelpOrVersionFlag = true
                continue
            }

            if arg == "--enable-build-cache"
                || arg == "--disable-build-cache"
                || arg.hasPrefix("--enable-build-cache=")
                || arg.hasPrefix("--disable-build-cache=") {
                hasExplicitBuildCacheFlag = true
                continue
            }

            if arg.hasPrefix("--package-path=") {
                packagePath = String(arg.dropFirst("--package-path=".count))
                continue
            }
            if arg.hasPrefix("--scratch-path=") {
                scratchPath = String(arg.dropFirst("--scratch-path=".count))
                continue
            }
            if arg.hasPrefix("--build-path=") {
                scratchPath = String(arg.dropFirst("--build-path=".count))
                continue
            }

            if valueTakingFlags.contains(arg) {
                awaitingFlag = arg
                continue
            }

            if arg.hasPrefix("-") {
                continue
            }

            if subcommand == nil && !sawPackageCommand {
                switch arg {
                case "build":
                    subcommand = .build
                    subcommandArgumentIndex = index
                case "test":
                    subcommand = .test
                    subcommandArgumentIndex = index
                case "run":
                    subcommand = .run
                    subcommandArgumentIndex = index
                case "package":
                    sawPackageCommand = true
                    subcommandArgumentIndex = index
                default:
                    subcommand = .other
                }
                if subcommand == .other {
                    break
                }
            } else if sawPackageCommand && subcommand == nil {
                if arg == "resolve" {
                    subcommand = .packageResolve
                } else {
                    subcommand = .other
                    break
                }
            } else if subcommand == .run {
                // First positional argument after `swift run` is the target name;
                // subsequent arguments are passed to the user's executable.
                break
            }
        }

        return SwiftCommandAnalysis(
            subcommand: subcommand ?? .other,
            subcommandArgumentIndex: subcommandArgumentIndex,
            packagePath: packagePath,
            scratchPath: scratchPath,
            hasHelpOrVersionFlag: hasHelpOrVersionFlag,
            hasExplicitBuildCacheFlag: hasExplicitBuildCacheFlag
        )
    }
}

import Foundation

/// Severity level for a `spmx doctor` diagnostic check.
public enum DiagnosticSeverity: String, Sendable, Equatable, Codable, CaseIterable {
    case pass
    case warn
    case fail
}

/// Outcome of a single diagnostic check executed by ``DoctorDiagnostics``.
public struct DoctorCheck: Sendable, Equatable {
    public let name: String
    public let severity: DiagnosticSeverity
    public let summary: String
    public let remediation: String?

    public init(
        name: String,
        severity: DiagnosticSeverity,
        summary: String,
        remediation: String? = nil
    ) {
        self.name = name
        self.severity = severity
        self.summary = summary
        self.remediation = remediation
    }
}

/// Aggregate diagnostic report returned by ``DoctorDiagnostics/run()``.
public struct DoctorReport: Sendable, Equatable {
    public let checks: [DoctorCheck]

    public var hasFailures: Bool {
        checks.contains { $0.severity == .fail }
    }

    public var hasWarnings: Bool {
        checks.contains { $0.severity == .warn }
    }

    public var passCount: Int {
        checks.filter { $0.severity == .pass }.count
    }

    public var warnCount: Int {
        checks.filter { $0.severity == .warn }.count
    }

    public var failCount: Int {
        checks.filter { $0.severity == .fail }.count
    }

    public init(checks: [DoctorCheck]) {
        self.checks = checks
    }
}

/// Runs version, environment, filesystem, toolchain, PATH shim, store integrity, and Git hooks diagnostics.
public struct DoctorDiagnostics: Sendable {
    public typealias CommandRunner = ToolchainFingerprint.CommandRunner
    public typealias FileSystemTypeProvider = @Sendable (URL) -> String?
    public typealias ExecutableChecker = @Sendable (String) -> Bool
    public typealias LatestVersionProvider = @Sendable () -> String?

    private let store: GlobalStore
    private let compilationCacheURL: URL
    private let homeDirectory: URL
    private let workingDirectory: String
    private let environment: [String: String]
    private let commandRunner: CommandRunner
    private let gitHooksManager: GitHooksManager
    private let fileSystemTypeProvider: FileSystemTypeProvider
    private let executableChecker: ExecutableChecker
    private let currentVersion: String
    private let latestVersionProvider: LatestVersionProvider

    public init(
        store: GlobalStore = GlobalStore(),
        compilationCacheURL: URL? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        commandRunner: @escaping CommandRunner = ToolchainFingerprint.defaultCommandRunner,
        gitHooksManager: GitHooksManager? = nil,
        fileSystemTypeProvider: @escaping FileSystemTypeProvider = APFSCloner.fileSystemTypeName(at:),
        executableChecker: @escaping ExecutableChecker = { FileManager.default.isExecutableFile(atPath: $0) },
        currentVersion: String = SPMXVersion.current,
        latestVersionProvider: LatestVersionProvider? = nil
    ) {
        self.store = store
        let standardizedHome = homeDirectory.standardizedFileURL
        self.homeDirectory = standardizedHome
        self.compilationCacheURL = (
            compilationCacheURL
                ?? StoreManager.defaultCompilationCacheURL(environment: environment, homeDirectory: homeDirectory)
        ).standardizedFileURL
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.commandRunner = commandRunner
        self.gitHooksManager = gitHooksManager ?? GitHooksManager(homeDirectory: homeDirectory)
        self.fileSystemTypeProvider = fileSystemTypeProvider
        self.executableChecker = executableChecker
        self.currentVersion = currentVersion
        self.latestVersionProvider = latestVersionProvider ?? {
            let upgrader = UpgradeManager(
                homeDirectory: standardizedHome,
                environment: environment,
                commandRunner: commandRunner
            )
            return try? upgrader.checkLatestVersion(currentVersion: currentVersion)
        }
    }

    /// Executes all diagnostic checks and returns a structured ``DoctorReport``.
    public func run() -> DoctorReport {
        let xcodeResult = try? commandRunner("xcodebuild", ["-version"])
        let swiftResult = try? commandRunner("swift", ["--version"])

        let checks: [DoctorCheck] = [
            checkSPMXVersion(),
            checkAPFSSupport(),
            checkXcodebuild(result: xcodeResult),
            checkSwiftAndCompilationCache(swiftResult: swiftResult, xcodeResult: xcodeResult),
            checkPATHOrder(),
            checkStoreAndCacheIntegrity(),
            checkPuroFvmInteroperability(),
            checkGitHooksStatus()
        ]
        return DoctorReport(checks: checks)
    }

    // MARK: - Individual Checks

    private func checkSPMXVersion() -> DoctorCheck {
        let currentSemver = SemanticVersion.parse(currentVersion)
            ?? SemanticVersion(major: 0, minor: 0, patch: 0)
        let installedBinaryURL = homeDirectory
            .appendingPathComponent(".spmx")
            .appendingPathComponent("bin")
            .appendingPathComponent("spmx")
            .standardizedFileURL

        var installedSemver: SemanticVersion?
        if executableChecker(installedBinaryURL.path),
           let binResult = try? commandRunner(installedBinaryURL.path, ["--version"]),
           binResult.exitCode == 0 {
            installedSemver = SemanticVersion.parse(binResult.stdout)
        }

        let latestSemver = latestVersionProvider().flatMap(SemanticVersion.parse)

        if let latestSemver, currentSemver < latestSemver {
            return DoctorCheck(
                name: "spmx Version",
                severity: .warn,
                summary: "spmx v\(currentSemver) is outdated (latest release: v\(latestSemver)).",
                remediation: "Run `spmx upgrade` to update to v\(latestSemver)."
            )
        }

        if let installedSemver, installedSemver != currentSemver {
            return DoctorCheck(
                name: "spmx Version",
                severity: .warn,
                summary: "Running spmx v\(currentSemver), but '\(installedBinaryURL.path)' is at v\(installedSemver).",
                remediation: "Run `spmx upgrade --force` or `spmx setup` to sync '\(installedBinaryURL.path)'."
            )
        }

        if let latestSemver {
            return DoctorCheck(
                name: "spmx Version",
                severity: .pass,
                summary: "spmx v\(currentSemver) is up to date (latest: v\(latestSemver))."
            )
        }

        return DoctorCheck(
            name: "spmx Version",
            severity: .pass,
            summary: "spmx v\(currentSemver) is installed."
        )
    }

    private func checkAPFSSupport() -> DoctorCheck {
        let fsName = fileSystemTypeProvider(store.rootURL)
        guard let fsName, !fsName.isEmpty else {
            return DoctorCheck(
                name: "APFS Filesystem",
                severity: .warn,
                summary: "Unable to determine filesystem type for store path '\(store.rootURL.path)'.",
                remediation: "Verify that '\(store.rootURL.path)' resides on a mounted local APFS volume."
            )
        }

        if fsName.lowercased() == "apfs" {
            return DoctorCheck(
                name: "APFS Filesystem",
                severity: .pass,
                summary: "Store volume uses APFS ('\(store.rootURL.path)'); zero-copy clonefile() CoW is enabled."
            )
        }

        return DoctorCheck(
            name: "APFS Filesystem",
            severity: .warn,
            summary: "Store path '\(store.rootURL.path)' is on '\(fsName)' (non-APFS); spmx will fall back to file copies.",
            remediation: "Set \(GlobalStore.storeDirectoryEnvironmentKey) to a path on an APFS volume for ~0-byte CoW clones."
        )
    }

    private func checkXcodebuild(result: CommandResult?) -> DoctorCheck {
        guard let result else {
            return DoctorCheck(
                name: "Xcode / xcodebuild",
                severity: .warn,
                summary: "Failed to execute `xcodebuild -version`.",
                remediation: "Install Xcode and run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` if building iOS/macOS targets."
            )
        }

        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitCode == 0, !output.isEmpty else {
            let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = err.isEmpty ? "exit code \(result.exitCode)" : err
            return DoctorCheck(
                name: "Xcode / xcodebuild",
                severity: .warn,
                summary: "`xcodebuild` is unavailable (\(detail)).",
                remediation: "Install Xcode or select an active developer directory via `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`."
            )
        }

        let summaryLine = output.split(separator: "\n").joined(separator: " / ")
        return DoctorCheck(
            name: "Xcode / xcodebuild",
            severity: .pass,
            summary: "Detected \(summaryLine)."
        )
    }

    private func checkSwiftAndCompilationCache(
        swiftResult: CommandResult?,
        xcodeResult: CommandResult?
    ) -> DoctorCheck {
        guard let swiftResult, swiftResult.exitCode == 0 else {
            return DoctorCheck(
                name: "Swift & Compilation Cache",
                severity: .fail,
                summary: "Unable to run `swift --version`.",
                remediation: "Install Xcode or the Swift toolchain and ensure `swift` is in PATH."
            )
        }

        let swiftOutput = swiftResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = swiftOutput.split(separator: "\n").first.map(String.init) ?? swiftOutput
        guard !firstLine.isEmpty else {
            return DoctorCheck(
                name: "Swift & Compilation Cache",
                severity: .fail,
                summary: "`swift --version` returned empty output.",
                remediation: "Verify your active Swift toolchain with `xcrun swift --version`."
            )
        }

        let xcodeOutput = (xcodeResult?.exitCode == 0 ? xcodeResult?.stdout : nil)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let supportsCAS = DiagnosticsSupport.supportsCompilationCache(
            swiftVersion: swiftOutput,
            xcodeVersion: xcodeOutput
        )

        if !supportsCAS {
            return DoctorCheck(
                name: "Swift & Compilation Cache",
                severity: .warn,
                summary: "\(firstLine) does not support Xcode 16+ / Swift 6+ LLVM CAS compilation caching.",
                remediation: "Upgrade to Xcode 16+ / Swift 6+ to enable shared compilation caching at '\(compilationCacheURL.path)'."
            )
        }

        if environment["SPMX_NO_COMPILE_CACHE"] == "1" {
            return DoctorCheck(
                name: "Swift & Compilation Cache",
                severity: .warn,
                summary: "\(firstLine) supports LLVM CAS compilation caching, but SPMX_NO_COMPILE_CACHE=1 disables it.",
                remediation: "Unset SPMX_NO_COMPILE_CACHE to re-enable shared compilation caching."
            )
        }

        return DoctorCheck(
            name: "Swift & Compilation Cache",
            severity: .pass,
            summary: "\(firstLine) supports LLVM CAS compilation caching (cache dir: '\(compilationCacheURL.path)')."
        )
    }

    private func checkPATHOrder() -> DoctorCheck {
        let shimsDir = expectedShimsDirectory().path
        let pathEntries = normalizedPathEntries()

        guard let shimsIndex = pathEntries.firstIndex(of: shimsDir) else {
            return DoctorCheck(
                name: "PATH Shims Ordering",
                severity: .fail,
                summary: "Shims directory '\(shimsDir)' is missing from PATH.",
                remediation: "Run `spmx setup` or add `export PATH=\"$HOME/.spmx/shims:$HOME/.spmx/bin:$PATH\"` to your shell profile."
            )
        }

        let missingShims = SetupManager.shimNames.filter { name in
            let shimPath = URL(fileURLWithPath: shimsDir).appendingPathComponent(name).path
            return !executableChecker(shimPath)
        }
        if !missingShims.isEmpty {
            return DoctorCheck(
                name: "PATH Shims Ordering",
                severity: .fail,
                summary: "Missing or non-executable shim(s) in '\(shimsDir)': \(missingShims.joined(separator: ", ")).",
                remediation: "Run `spmx setup` to create executable shims in '\(shimsDir)'."
            )
        }

        let precedingEntries = Array(pathEntries[..<shimsIndex])
        var shadowedTools: [String] = []
        for tool in SetupManager.shimNames {
            for dir in precedingEntries where dir != shimsDir {
                let candidate = URL(fileURLWithPath: dir).appendingPathComponent(tool).path
                if executableChecker(candidate) {
                    shadowedTools.append("\(tool) (\(candidate))")
                    break
                }
            }
        }

        if !shadowedTools.isEmpty {
            return DoctorCheck(
                name: "PATH Shims Ordering",
                severity: .fail,
                summary: "Shims in '\(shimsDir)' are shadowed by earlier PATH entries: \(shadowedTools.joined(separator: ", ")).",
                remediation: "Move '\(shimsDir)' before other toolchain directories in PATH."
            )
        }

        if environment["SPMX_DISABLE"] == "1" {
            return DoctorCheck(
                name: "PATH Shims Ordering",
                severity: .warn,
                summary: "'\(shimsDir)' is first in PATH, but SPMX_DISABLE=1 is currently bypassing all shims.",
                remediation: "Unset SPMX_DISABLE to re-enable transparent spmx shims."
            )
        }

        return DoctorCheck(
            name: "PATH Shims Ordering",
            severity: .pass,
            summary: "'\(shimsDir)' precedes flutter, xcodebuild, and swift in PATH."
        )
    }

    private func checkStoreAndCacheIntegrity() -> DoctorCheck {
        let fileManager = FileManager.default

        if !DiagnosticsSupport.isDirectory(atPath: store.rootURL.path, fileManager: fileManager) {
            return DoctorCheck(
                name: "Store & Cache Integrity",
                severity: .warn,
                summary: "Global store directory does not exist yet at '\(store.rootURL.path)'.",
                remediation: "Run `spmx setup` or `spmx hydrate` to initialize the store."
            )
        }

        let requiredSubdirs = [
            ("checkouts", store.checkoutsDirectory),
            ("artifacts", store.artifactsDirectory),
            ("prebuilts", store.prebuiltsDirectory)
        ]
        let missingSubdirs = requiredSubdirs
            .filter { !DiagnosticsSupport.isDirectory(atPath: $0.1.path, fileManager: fileManager) }
            .map(\.0)

        if fileManager.fileExists(atPath: store.indexURL.path) {
            do {
                let index = try store.readIndex()
                if index.schemaVersion > StoreIndex.currentSchemaVersion {
                    return DoctorCheck(
                        name: "Store & Cache Integrity",
                        severity: .warn,
                        summary: "Store index schema v\(index.schemaVersion) is newer than supported v\(StoreIndex.currentSchemaVersion).",
                        remediation: "Upgrade spmx to a newer version."
                    )
                }
            } catch {
                return DoctorCheck(
                    name: "Store & Cache Integrity",
                    severity: .fail,
                    summary: "Store index '\(store.indexURL.path)' is unreadable or corrupted: \(error.localizedDescription)",
                    remediation: "Back up and remove '\(store.indexURL.path)', then re-run `spmx harvest` in active worktrees."
                )
            }
        }

        if !fileManager.isWritableFile(atPath: store.rootURL.path) {
            return DoctorCheck(
                name: "Store & Cache Integrity",
                severity: .fail,
                summary: "Global store '\(store.rootURL.path)' is not writable.",
                remediation: "Check directory permissions on '\(store.rootURL.path)'."
            )
        }

        if !missingSubdirs.isEmpty {
            return DoctorCheck(
                name: "Store & Cache Integrity",
                severity: .warn,
                summary: "Store '\(store.rootURL.path)' is missing subdirectories: \(missingSubdirs.joined(separator: ", ")).",
                remediation: "Run `spmx setup` or `spmx hydrate` to recreate missing store directories."
            )
        }

        if !DiagnosticsSupport.isDirectory(atPath: compilationCacheURL.path, fileManager: fileManager) {
            return DoctorCheck(
                name: "Store & Cache Integrity",
                severity: .warn,
                summary: "Store '\(store.rootURL.path)' is healthy, but compilation cache directory '\(compilationCacheURL.path)' does not exist yet.",
                remediation: "Run `spmx setup` to create '\(compilationCacheURL.path)'."
            )
        }

        if !fileManager.isWritableFile(atPath: compilationCacheURL.path) {
            return DoctorCheck(
                name: "Store & Cache Integrity",
                severity: .fail,
                summary: "Compilation cache directory '\(compilationCacheURL.path)' is not writable.",
                remediation: "Check directory permissions on '\(compilationCacheURL.path)'."
            )
        }

        return DoctorCheck(
            name: "Store & Cache Integrity",
            severity: .pass,
            summary: "Store '\(store.rootURL.path)', index.json, and compilation cache '\(compilationCacheURL.path)' are valid and writable."
        )
    }

    private func checkPuroFvmInteroperability() -> DoctorCheck {
        let fileManager = FileManager.default
        let shimsDir = expectedShimsDirectory().path
        let pathEntries = normalizedPathEntries()
        let shimsIndex = pathEntries.firstIndex(of: shimsDir)

        let puroExec = findExecutableInPath("puro", pathEntries: pathEntries, excludingDir: shimsDir)
        let fvmExec = findExecutableInPath("fvm", pathEntries: pathEntries, excludingDir: shimsDir)

        let puroRootPath = expandAndStandardize(environment["PURO_ROOT"] ?? homeDirectory.appendingPathComponent(".puro").path)
        let fvmHomePath = expandAndStandardize(
            environment["FVM_HOME"]
                ?? environment["FVM_CACHE_PATH"]
                ?? homeDirectory.appendingPathComponent("fvm").path
        )
        let fvmDotPath = homeDirectory.appendingPathComponent(".fvm").path

        let hasPuro = puroExec != nil || DiagnosticsSupport.isDirectory(atPath: puroRootPath, fileManager: fileManager)
        let hasFvm = fvmExec != nil
            || DiagnosticsSupport.isDirectory(atPath: fvmHomePath, fileManager: fileManager)
            || DiagnosticsSupport.isDirectory(atPath: fvmDotPath, fileManager: fileManager)

        var detectedTools: [String] = []
        if hasPuro { detectedTools.append("puro") }
        if hasFvm { detectedTools.append("fvm") }

        guard !detectedTools.isEmpty else {
            return DoctorCheck(
                name: "puro / fvm Interoperability",
                severity: .pass,
                summary: "No puro or fvm installation detected; standard PATH shim resolution applies."
            )
        }

        var shadowingDirs: [String] = []
        if let shimsIndex {
            for dir in pathEntries[..<shimsIndex] where dir != shimsDir {
                let lower = dir.lowercased()
                if lower.contains("puro") || lower.contains("fvm") {
                    let flutterCandidate = URL(fileURLWithPath: dir).appendingPathComponent("flutter").path
                    if executableChecker(flutterCandidate) {
                        shadowingDirs.append(dir)
                    }
                }
            }
        }

        let toolsLabel = detectedTools.joined(separator: " & ")
        if !shadowingDirs.isEmpty {
            return DoctorCheck(
                name: "puro / fvm Interoperability",
                severity: .warn,
                summary: "Detected \(toolsLabel) ahead of '\(shimsDir)' in PATH (\(shadowingDirs.joined(separator: ", "))); `flutter` commands will bypass the flutter shim.",
                remediation: "Place '\(shimsDir)' before \(toolsLabel) in PATH. Note: even with `puro flutter run`, `~/.spmx/shims/xcodebuild` still intercepts Xcode/SPM builds."
            )
        }

        return DoctorCheck(
            name: "puro / fvm Interoperability",
            severity: .pass,
            summary: "Detected \(toolsLabel) after '\(shimsDir)' in PATH (compatible; note that invoking `puro flutter ...` directly bypasses the flutter shim, while `~/.spmx/shims/xcodebuild` still caches Apple SPM builds)."
        )
    }

    private func checkGitHooksStatus() -> DoctorCheck {
        do {
            let status = try gitHooksManager.status(workingDirectory: workingDirectory)
            let repoLabel: String
            if !status.repo.isAvailable {
                repoLabel = "repo: N/A (not in a Git repo)"
            } else if status.repo.isActive {
                let mode = status.repo.isAsync ? "async" : "sync"
                repoLabel = "repo: active (\(mode))"
            } else {
                repoLabel = "repo: inactive"
            }

            let globalLabel: String
            if status.global.isActive {
                let mode = status.global.isAsync ? "async" : "sync"
                globalLabel = "global: active (\(mode))"
            } else {
                globalLabel = "global: inactive"
            }

            if status.repo.isActive && !status.repo.isExecutable {
                return DoctorCheck(
                    name: "Git Hooks",
                    severity: .warn,
                    summary: "Repository post-checkout hook at '\(status.repo.hookFilePath ?? "")' is not executable (\(repoLabel), \(globalLabel)).",
                    remediation: "Run `chmod +x \"\(status.repo.hookFilePath ?? ".git/hooks/post-checkout")\"`."
                )
            }

            if status.global.isActive && !status.global.isExecutable {
                return DoctorCheck(
                    name: "Git Hooks",
                    severity: .warn,
                    summary: "Global post-checkout hook at '\(status.global.hookFilePath ?? "")' is not executable (\(repoLabel), \(globalLabel)).",
                    remediation: "Run `chmod +x \"\(status.global.hookFilePath ?? "~/.spmx/git-hooks/post-checkout")\"`."
                )
            }

            if status.repo.isActive || status.global.isActive {
                return DoctorCheck(
                    name: "Git Hooks",
                    severity: .pass,
                    summary: "Git post-checkout hook status: \(repoLabel), \(globalLabel)."
                )
            }

            return DoctorCheck(
                name: "Git Hooks",
                severity: .pass,
                summary: "Git post-checkout hooks are inactive by default (\(repoLabel), \(globalLabel)).",
                remediation: "Optional: run `spmx hooks enable --global` to pre-warm SourcePackages on `git worktree add`."
            )
        } catch {
            return DoctorCheck(
                name: "Git Hooks",
                severity: .warn,
                summary: "Failed to inspect Git hooks: \(error.localizedDescription)",
                remediation: "Run `spmx hooks status` to inspect hook files."
            )
        }
    }

    // MARK: - Private Path Helpers

    private func expectedShimsDirectory() -> URL {
        homeDirectory
            .appendingPathComponent(".spmx")
            .appendingPathComponent("shims")
            .standardizedFileURL
    }

    private func normalizedPathEntries() -> [String] {
        guard let rawPath = environment["PATH"], !rawPath.isEmpty else {
            return []
        }
        return rawPath
            .split(separator: ":", omittingEmptySubsequences: true)
            .map { expandAndStandardize(String($0)) }
    }

    private func expandAndStandardize(_ raw: String) -> String {
        let expanded: String
        if raw == "~" {
            expanded = homeDirectory.path
        } else if raw.hasPrefix("~/") {
            expanded = homeDirectory.appendingPathComponent(String(raw.dropFirst(2))).path
        } else {
            expanded = (raw as NSString).expandingTildeInPath
        }
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    private func findExecutableInPath(
        _ name: String,
        pathEntries: [String],
        excludingDir: String
    ) -> String? {
        for dir in pathEntries where dir != excludingDir {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent(name).path
            if executableChecker(candidate) {
                return candidate
            }
        }
        return nil
    }
}

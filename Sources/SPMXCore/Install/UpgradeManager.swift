import CryptoKit
import Foundation

/// Single source of truth for the active `spmx` CLI version inside `SPMXCore`.
public enum SPMXVersion {
    public static let current = "0.2.4"
}

/// Three-component semantic version (`major.minor.patch`).
public struct SemanticVersion: Sendable, Equatable, Comparable, CustomStringConvertible, Codable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    /// Parses a semantic version from strings such as `"0.2.2"`, `"v0.2.2"`, or `"spmx 0.2.2"`.
    public static func parse(_ raw: String) -> SemanticVersion? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let regex = try? NSRegularExpression(pattern: #"(?:^|\b)[vV]?(\d+)\.(\d+)\.(\d+)(?:\b|$)"#) else {
            return nil
        }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range),
              let majorRange = Range(match.range(at: 1), in: trimmed),
              let minorRange = Range(match.range(at: 2), in: trimmed),
              let patchRange = Range(match.range(at: 3), in: trimmed),
              let major = Int(trimmed[majorRange]),
              let minor = Int(trimmed[minorRange]),
              let patch = Int(trimmed[patchRange]) else {
            return nil
        }
        return SemanticVersion(major: major, minor: minor, patch: patch)
    }
}

/// Errors raised by ``UpgradeManager``.
public enum UpgradeError: Error, LocalizedError, Sendable, Equatable {
    case invalidVersion(String)
    case latestVersionUnavailable(String)
    case downloadFailed(url: String, details: String)
    case checksumMismatch(expected: String, actual: String)
    case extractionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidVersion(let raw):
            return "Invalid version '\(raw)'. Expected semantic version like 0.2.2 or v0.2.2."
        case .latestVersionUnavailable(let details):
            return "Unable to determine latest spmx release version (\(details))."
        case .downloadFailed(let url, let details):
            return "Failed to download release asset from '\(url)' (\(details))."
        case .checksumMismatch(let expected, let actual):
            return "SHA-256 checksum verification failed (expected \(expected), got \(actual))."
        case .extractionFailed(let details):
            return "Failed to extract spmx archive (\(details))."
        }
    }
}

/// Step progress notifications emitted during ``UpgradeManager/upgrade(options:stepObserver:)``.
public enum UpgradeStepEvent: Sendable, Equatable {
    case running(step: String, detail: String?)
    case completed(step: String, detail: String?)
    case skipped(step: String, detail: String?)
}

/// Configuration options for ``UpgradeManager/upgrade(options:stepObserver:)``.
public struct UpgradeOptions: Sendable {
    public var checkOnly: Bool
    public var force: Bool
    public var targetVersion: String?
    public var noModifyPath: Bool
    public var currentVersion: String
    public var currentExecutableURL: URL?

    public init(
        checkOnly: Bool = false,
        force: Bool = false,
        targetVersion: String? = nil,
        noModifyPath: Bool = false,
        currentVersion: String = SPMXVersion.current,
        currentExecutableURL: URL? = nil
    ) {
        self.checkOnly = checkOnly
        self.force = force
        self.targetVersion = targetVersion
        self.noModifyPath = noModifyPath
        self.currentVersion = currentVersion
        self.currentExecutableURL = currentExecutableURL
    }
}

/// Outcome returned by ``UpgradeManager/upgrade(options:stepObserver:)``.
public struct UpgradeResult: Sendable, Equatable, Codable {
    public let currentVersion: String
    public let targetVersion: String
    public let tag: String
    public let upToDate: Bool
    public let checkOnly: Bool
    public let upgraded: Bool
    public let binaryPath: String?
    public let checksum: String?

    public init(
        currentVersion: String,
        targetVersion: String,
        tag: String,
        upToDate: Bool,
        checkOnly: Bool,
        upgraded: Bool,
        binaryPath: String?,
        checksum: String?
    ) {
        self.currentVersion = currentVersion
        self.targetVersion = targetVersion
        self.tag = tag
        self.upToDate = upToDate
        self.checkOnly = checkOnly
        self.upgraded = upgraded
        self.binaryPath = binaryPath
        self.checksum = checksum
    }
}

/// Checks for newer `spmx` releases and upgrades the local installation.
public struct UpgradeManager: Sendable {
    public typealias CommandRunner = ToolchainFingerprint.CommandRunner

    public static let repository = "LuisRibeiroo/spmx"
    public static let archiveName = "spmx-macos-universal.tar.gz"
    public static let checksumName = "spmx-macos-universal.tar.gz.sha256"

    private struct SendableFileManager: @unchecked Sendable {
        let value: FileManager
    }

    private let homeDirectory: URL
    private let shell: String?
    private let environment: [String: String]
    private let commandRunner: CommandRunner
    private let fileManagerBox: SendableFileManager

    private var fileManager: FileManager {
        fileManagerBox.value
    }

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        shell: String? = ProcessInfo.processInfo.environment["SHELL"],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        commandRunner: @escaping CommandRunner = UpgradeManager.defaultCommandRunner
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.shell = shell
        self.environment = environment
        self.fileManagerBox = SendableFileManager(value: fileManager)
        self.commandRunner = commandRunner
    }

    public static let defaultCommandRunner: CommandRunner = ToolchainFingerprint.defaultCommandRunner

    /// Queries GitHub Releases for the latest published `spmx` version string (e.g. `"0.2.2"`).
    public func checkLatestVersion(currentVersion: String = SPMXVersion.current) throws -> String {
        let userAgent = "spmx-cli/\(currentVersion)"
        let apiURL = "https://api.github.com/repos/\(Self.repository)/releases/latest"

        if let apiResult = try? commandRunner(
            "/usr/bin/curl",
            [
                "-fsSL",
                "--max-time", "8",
                "-H", "Accept: application/vnd.github+json",
                "-A", userAgent,
                apiURL
            ]
        ), apiResult.exitCode == 0 {
            if let version = Self.extractVersionFromReleaseJSON(apiResult.stdout) {
                return version
            }
        }

        // Fallback: resolve redirect from github.com/<repo>/releases/latest -> .../releases/tag/vX.Y.Z
        let redirectURL = "https://github.com/\(Self.repository)/releases/latest"
        let redirectResult: CommandResult
        do {
            redirectResult = try commandRunner(
                "/usr/bin/curl",
                [
                    "-fsSLI",
                    "--max-time", "8",
                    "-o", "/dev/null",
                    "-w", "%{url_effective}",
                    "-A", userAgent,
                    redirectURL
                ]
            )
        } catch {
            throw UpgradeError.latestVersionUnavailable(error.localizedDescription)
        }

        guard redirectResult.exitCode == 0 else {
            let err = redirectResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpgradeError.latestVersionUnavailable(err.isEmpty ? "curl exit code \(redirectResult.exitCode)" : err)
        }

        if let version = Self.extractVersionFromRedirectURL(redirectResult.stdout) {
            return version
        }

        throw UpgradeError.latestVersionUnavailable("no release tag found at \(redirectURL)")
    }

    /// Checks for a newer `spmx` release and updates the local installation when needed.
    public func upgrade(
        options: UpgradeOptions = UpgradeOptions(),
        stepObserver: (@Sendable (UpgradeStepEvent) -> Void)? = nil
    ) throws -> UpgradeResult {
        guard let currentSemver = SemanticVersion.parse(options.currentVersion) else {
            throw UpgradeError.invalidVersion(options.currentVersion)
        }

        let targetSemver: SemanticVersion
        if let explicitTarget = options.targetVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicitTarget.isEmpty {
            guard let parsed = SemanticVersion.parse(explicitTarget) else {
                throw UpgradeError.invalidVersion(explicitTarget)
            }
            targetSemver = parsed
            stepObserver?(.completed(step: "Target version", detail: "v\(parsed.description)"))
        } else {
            stepObserver?(.running(step: "Checking for updates", detail: "github.com/\(Self.repository)"))
            let latestRaw = try checkLatestVersion(currentVersion: currentSemver.description)
            guard let parsed = SemanticVersion.parse(latestRaw) else {
                throw UpgradeError.latestVersionUnavailable("unrecognized version '\(latestRaw)'")
            }
            targetSemver = parsed
            stepObserver?(.completed(
                step: "Checked latest release",
                detail: "v\(parsed.description) (installed: v\(currentSemver.description))"
            ))
        }

        let tag = "v\(targetSemver.description)"
        let installedBinaryURL = homeDirectory
            .appendingPathComponent(".spmx")
            .appendingPathComponent("bin")
            .appendingPathComponent("spmx")

        var installedSemver: SemanticVersion?
        if fileManager.isExecutableFile(atPath: installedBinaryURL.path),
           let binResult = try? commandRunner(installedBinaryURL.path, ["--version"]),
           binResult.exitCode == 0 {
            installedSemver = SemanticVersion.parse(binResult.stdout)
        }
        let installedMatchesTarget = installedSemver == nil || installedSemver == targetSemver

        let isUpToDate: Bool
        if options.targetVersion != nil {
            isUpToDate = (currentSemver == targetSemver)
                && fileManager.isExecutableFile(atPath: installedBinaryURL.path)
                && installedMatchesTarget
        } else {
            isUpToDate = (currentSemver >= targetSemver)
                && fileManager.isExecutableFile(atPath: installedBinaryURL.path)
                && installedMatchesTarget
        }

        if options.checkOnly {
            return UpgradeResult(
                currentVersion: currentSemver.description,
                targetVersion: targetSemver.description,
                tag: tag,
                upToDate: currentSemver >= targetSemver,
                checkOnly: true,
                upgraded: false,
                binaryPath: fileManager.isExecutableFile(atPath: installedBinaryURL.path) ? installedBinaryURL.path : nil,
                checksum: nil
            )
        }

        if isUpToDate && !options.force {
            stepObserver?(.skipped(step: "Already up to date", detail: "v\(currentSemver.description)"))
            return UpgradeResult(
                currentVersion: currentSemver.description,
                targetVersion: targetSemver.description,
                tag: tag,
                upToDate: true,
                checkOnly: false,
                upgraded: false,
                binaryPath: installedBinaryURL.path,
                checksum: nil
            )
        }

        let tempDir = fileManager.temporaryDirectory
            .appendingPathComponent("spmx-upgrade-\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let archiveURL = tempDir.appendingPathComponent(Self.archiveName)
        let checksumURL = tempDir.appendingPathComponent(Self.checksumName)
        let installerUA = "spmx-installer/1.0 (Darwin; \(Self.currentArchitecture()))"

        let primaryBase = "https://get.spmx.io/releases/download/\(tag)"
        let fallbackBase = "https://github.com/\(Self.repository)/releases/download/\(tag)"

        stepObserver?(.running(step: "Downloading spmx \(tag)", detail: Self.archiveName))
        try downloadAsset(
            named: Self.archiveName,
            primaryBaseURL: primaryBase,
            fallbackBaseURL: fallbackBase,
            userAgent: installerUA,
            destinationURL: archiveURL
        )
        try downloadAsset(
            named: Self.checksumName,
            primaryBaseURL: primaryBase,
            fallbackBaseURL: fallbackBase,
            userAgent: installerUA,
            destinationURL: checksumURL
        )
        stepObserver?(.completed(step: "Downloaded archive", detail: "\(Self.archiveName) (\(tag))"))

        stepObserver?(.running(step: "Verifying SHA-256 checksum", detail: nil))
        let actualChecksum = try verifyChecksum(archiveURL: archiveURL, checksumFileURL: checksumURL)
        stepObserver?(.completed(step: "Checksum verified", detail: actualChecksum))

        stepObserver?(.running(step: "Extracting and installing binary", detail: installedBinaryURL.path))
        let extractResult = try commandRunner(
            "/usr/bin/tar",
            ["-xzf", archiveURL.path, "-C", tempDir.path]
        )
        guard extractResult.exitCode == 0 else {
            let err = extractResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpgradeError.extractionFailed(err.isEmpty ? "tar exit code \(extractResult.exitCode)" : err)
        }

        let extractedBinaryURL = tempDir.appendingPathComponent("spmx")
        guard fileManager.fileExists(atPath: extractedBinaryURL.path) else {
            throw UpgradeError.extractionFailed("extracted archive did not contain 'spmx' binary")
        }
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: extractedBinaryURL.path)

        let setupResult = try SetupManager.setup(
            noModifyPath: options.noModifyPath,
            binaryPath: extractedBinaryURL,
            homeDirectory: homeDirectory,
            shell: shell,
            environment: environment,
            fileManager: fileManager
        )

        // If the user invoked `spmx` from another standalone binary location (e.g. /opt/homebrew/bin/spmx or /usr/local/bin/spmx),
        // atomically update that binary too when writable so `spmx --version` reflects the upgrade immediately.
        if let activeExec = options.currentExecutableURL {
            let resolvedActive = activeExec.standardizedFileURL.resolvingSymlinksInPath()
            let resolvedInstalled = setupResult.binaryPath.standardizedFileURL.resolvingSymlinksInPath()
            if resolvedActive.path != resolvedInstalled.path,
               fileManager.isWritableFile(atPath: resolvedActive.deletingLastPathComponent().path) {
                try? replaceBinaryAtomically(from: extractedBinaryURL, to: resolvedActive)
            }
        }

        stepObserver?(.completed(step: "Installed spmx \(tag)", detail: setupResult.binaryPath.path))

        return UpgradeResult(
            currentVersion: currentSemver.description,
            targetVersion: targetSemver.description,
            tag: tag,
            upToDate: false,
            checkOnly: false,
            upgraded: true,
            binaryPath: setupResult.binaryPath.path,
            checksum: actualChecksum
        )
    }

    // MARK: - Internal & Parsing Helpers

    static func extractVersionFromReleaseJSON(_ jsonText: String) -> String? {
        guard let data = jsonText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = object["tag_name"] as? String,
              let semver = SemanticVersion.parse(tagName) else {
            return nil
        }
        return semver.description
    }

    static func extractVersionFromRedirectURL(_ urlText: String) -> String? {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: "/releases/tag/") else {
            return nil
        }
        let tail = String(trimmed[range.upperBound...])
            .split(whereSeparator: { $0 == "/" || $0 == "?" || $0 == "#" })
            .first
            .map(String.init) ?? ""
        return SemanticVersion.parse(tail)?.description
    }

    private func downloadAsset(
        named assetName: String,
        primaryBaseURL: String,
        fallbackBaseURL: String,
        userAgent: String,
        destinationURL: URL
    ) throws {
        let primaryURL = "\(primaryBaseURL)/\(assetName)"
        if let primaryResult = try? commandRunner(
            "/usr/bin/curl",
            ["-fsSL", "-A", userAgent, primaryURL, "-o", destinationURL.path]
        ), primaryResult.exitCode == 0, fileManager.fileExists(atPath: destinationURL.path) {
            return
        }

        let fallbackURL = "\(fallbackBaseURL)/\(assetName)"
        let fallbackResult: CommandResult
        do {
            fallbackResult = try commandRunner(
                "/usr/bin/curl",
                ["-fsSL", "-A", userAgent, fallbackURL, "-o", destinationURL.path]
            )
        } catch {
            throw UpgradeError.downloadFailed(url: fallbackURL, details: error.localizedDescription)
        }

        guard fallbackResult.exitCode == 0, fileManager.fileExists(atPath: destinationURL.path) else {
            let err = fallbackResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpgradeError.downloadFailed(
                url: fallbackURL,
                details: err.isEmpty ? "curl exit code \(fallbackResult.exitCode)" : err
            )
        }
    }

    private func verifyChecksum(archiveURL: URL, checksumFileURL: URL) throws -> String {
        let checksumText = (try? String(contentsOf: checksumFileURL, encoding: .utf8)) ?? ""
        let expected = checksumText
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .first
            .map { String($0).lowercased() } ?? ""

        let archiveData = try Data(contentsOf: archiveURL)
        let actual = SHA256.hash(data: archiveData)
            .map { String(format: "%02x", $0) }
            .joined()

        guard !expected.isEmpty, expected == actual else {
            throw UpgradeError.checksumMismatch(
                expected: expected.isEmpty ? "<empty>" : expected,
                actual: actual
            )
        }
        return actual
    }

    private func replaceBinaryAtomically(from sourceURL: URL, to destinationURL: URL) throws {
        let tempURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".spmx.upgrade.\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: tempURL) }

        try fileManager.copyItem(at: sourceURL, to: tempURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempURL.path)
        if (try? fileManager.attributesOfItem(atPath: destinationURL.path)) != nil {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: tempURL, to: destinationURL)
    }

    private static func currentArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}

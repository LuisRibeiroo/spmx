import Foundation

/// Errors thrown during Git hook management operations.
public enum GitHooksError: Error, LocalizedError, Equatable, Sendable {
    case notInGitRepository(String)
    case gitCommandFailed(command: String, exitCode: Int32, stderr: String)
    case malformedHookBlock(String)

    public var errorDescription: String? {
        switch self {
        case .notInGitRepository(let path):
            return "Not inside a Git repository at '\(path)'. Pass --global to manage global Git hooks."
        case .gitCommandFailed(let command, let exitCode, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Git command '\(command)' failed with exit code \(exitCode)."
            }
            return "Git command '\(command)' failed with exit code \(exitCode): \(trimmed)"
        case .malformedHookBlock(let path):
            return "Found an incomplete pspm hook block in '\(path)'. Please ensure both '\(GitHooksManager.blockStartMarker)' and '\(GitHooksManager.blockEndMarker)' markers match."
        }
    }
}

/// Output captured from executing a Git command.
public struct GitCommandResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Abstraction for executing Git commands, enabling isolated unit testing.
public protocol GitCommandRunning: Sendable {
    func runGit(arguments: [String], workingDirectory: String?) throws -> GitCommandResult
}

/// Default `GitCommandRunning` implementation backed by `Process` invoking `git`.
public struct SystemGitRunner: GitCommandRunning {
    public init() {}

    public func runGit(arguments: [String], workingDirectory: String?) throws -> GitCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return GitCommandResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}

/// Target scope for Git `post-checkout` hook management.
public enum HookScope: String, Sendable, Equatable {
    case repo
    case global
}

/// Options controlling how the `pspm` `post-checkout` hook runs.
public struct HookEnableOptions: Sendable, Equatable {
    public var async: Bool

    public init(async: Bool = false) {
        self.async = async
    }
}

/// Result returned by `GitHooksManager.enable`.
public struct HookEnableResult: Sendable, Equatable {
    public let scope: HookScope
    public let hookFilePath: String
    public let hooksDirectoryPath: String
    public let chainedExistingHooksPath: String?
    public let configuredGlobalHooksPath: Bool
    public let alreadyInstalled: Bool
    public let async: Bool
    public let notice: String?

    public init(
        scope: HookScope,
        hookFilePath: String,
        hooksDirectoryPath: String,
        chainedExistingHooksPath: String? = nil,
        configuredGlobalHooksPath: Bool = false,
        alreadyInstalled: Bool = false,
        async: Bool = false,
        notice: String? = nil
    ) {
        self.scope = scope
        self.hookFilePath = hookFilePath
        self.hooksDirectoryPath = hooksDirectoryPath
        self.chainedExistingHooksPath = chainedExistingHooksPath
        self.configuredGlobalHooksPath = configuredGlobalHooksPath
        self.alreadyInstalled = alreadyInstalled
        self.async = async
        self.notice = notice
    }
}

/// Result returned by `GitHooksManager.disable`.
public struct HookDisableResult: Sendable, Equatable {
    public let scope: HookScope
    public let hookFilePath: String?
    public let removed: Bool
    public let preservedOtherContent: Bool
    public let unsetGlobalHooksPath: Bool
    public let notice: String?

    public init(
        scope: HookScope,
        hookFilePath: String?,
        removed: Bool,
        preservedOtherContent: Bool,
        unsetGlobalHooksPath: Bool = false,
        notice: String? = nil
    ) {
        self.scope = scope
        self.hookFilePath = hookFilePath
        self.removed = removed
        self.preservedOtherContent = preservedOtherContent
        self.unsetGlobalHooksPath = unsetGlobalHooksPath
        self.notice = notice
    }
}

/// Status of the `pspm` `post-checkout` hook for a single scope.
public struct ScopedHookStatus: Sendable, Equatable {
    public let scope: HookScope
    public let isAvailable: Bool
    public let isActive: Bool
    public let isExecutable: Bool
    public let isAsync: Bool
    public let hooksDirectoryPath: String?
    public let hookFilePath: String?
    public let gitCommonDirPath: String?
    public let configuredHooksPath: String?
    public let isChainedWithExistingHooks: Bool
    public let chainsExistingGlobalHooksPath: Bool

    public init(
        scope: HookScope,
        isAvailable: Bool,
        isActive: Bool,
        isExecutable: Bool,
        isAsync: Bool,
        hooksDirectoryPath: String?,
        hookFilePath: String?,
        gitCommonDirPath: String? = nil,
        configuredHooksPath: String? = nil,
        isChainedWithExistingHooks: Bool = false,
        chainsExistingGlobalHooksPath: Bool = false
    ) {
        self.scope = scope
        self.isAvailable = isAvailable
        self.isActive = isActive
        self.isExecutable = isExecutable
        self.isAsync = isAsync
        self.hooksDirectoryPath = hooksDirectoryPath
        self.hookFilePath = hookFilePath
        self.gitCommonDirPath = gitCommonDirPath
        self.configuredHooksPath = configuredHooksPath
        self.isChainedWithExistingHooks = isChainedWithExistingHooks
        self.chainsExistingGlobalHooksPath = chainsExistingGlobalHooksPath
    }
}

/// Combined status for both repository and global `post-checkout` hooks.
public struct HookStatusReport: Sendable, Equatable {
    public let repo: ScopedHookStatus
    public let global: ScopedHookStatus

    public init(repo: ScopedHookStatus, global: ScopedHookStatus) {
        self.repo = repo
        self.global = global
    }
}

/// Manages opt-in Git `post-checkout` hooks for repository (worktree-aware) and global scopes.
public struct GitHooksManager: Sendable {
    public static let blockStartMarker = "# >>> pspm hook >>>"
    public static let blockEndMarker = "# <<< pspm hook <<<"
    public static let postCheckoutFileName = "post-checkout"

    private let gitRunner: any GitCommandRunning
    private let defaultGlobalHooksDirectory: URL
    private let homeDirectory: URL

    public init(
        gitRunner: any GitCommandRunning = SystemGitRunner(),
        defaultGlobalHooksDirectory: URL? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.gitRunner = gitRunner
        self.homeDirectory = homeDirectory
        self.defaultGlobalHooksDirectory = (
            defaultGlobalHooksDirectory
                ?? homeDirectory
                    .appendingPathComponent(".pspm")
                    .appendingPathComponent("git-hooks")
        ).standardized
    }

    /// Renders the delimited POSIX shell block injected into `post-checkout`.
    public static func renderHookBlock(async: Bool = false) -> String {
        let hydrateCommand = async
            ? "pspm hydrate --quiet >/dev/null 2>&1 &"
            : "pspm hydrate --quiet || true"
        let fallbackCommand = async
            ? "\"$HOME/.pspm/bin/pspm\" hydrate --quiet >/dev/null 2>&1 &"
            : "\"$HOME/.pspm/bin/pspm\" hydrate --quiet || true"

        return """
        \(blockStartMarker)
        if [ "$3" = "1" ]; then
          _pspm_should_hydrate=0
          if [ -f "pubspec.yaml" ] || [ -f "Package.swift" ]; then
            _pspm_should_hydrate=1
          else
            for _pspm_entry in *.xcworkspace *.xcodeproj; do
              if [ -e "$_pspm_entry" ]; then
                _pspm_should_hydrate=1
                break
              fi
            done
          fi
          if [ "$_pspm_should_hydrate" = "1" ]; then
            if command -v pspm >/dev/null 2>&1; then
              \(hydrateCommand)
            elif [ -x "$HOME/.pspm/bin/pspm" ]; then
              \(fallbackCommand)
            fi
          fi
          unset _pspm_should_hydrate _pspm_entry
        fi
        \(blockEndMarker)
        """
    }

    /// Enables the `pspm` `post-checkout` hook in the specified scope (defaults to `.repo` when inside a Git repo).
    public func enable(
        scope: HookScope? = nil,
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        options: HookEnableOptions = HookEnableOptions()
    ) throws -> HookEnableResult {
        let resolvedScope = try resolveScope(scope, workingDirectory: workingDirectory)
        let block = Self.renderHookBlock(async: options.async)

        switch resolvedScope {
        case .repo:
            let repoInfo = try resolveRepositoryHooksInfo(workingDirectory: workingDirectory)
            let alreadyInstalled = try installHookBlock(block, at: repoInfo.hookFileURL)
            let existingOtherContent = try hasOtherHookContent(at: repoInfo.hookFileURL)
            let notice = existingOtherContent
                ? "Chained pspm into existing repository hook at '\(repoInfo.hookFileURL.path)'."
                : nil
            return HookEnableResult(
                scope: .repo,
                hookFilePath: repoInfo.hookFileURL.path,
                hooksDirectoryPath: repoInfo.hooksDirectoryURL.path,
                chainedExistingHooksPath: nil,
                configuredGlobalHooksPath: false,
                alreadyInstalled: alreadyInstalled,
                async: options.async,
                notice: notice
            )

        case .global:
            let existingRawPath = try readGlobalHooksPath()
            let hooksDirectoryURL: URL
            let configuredGlobalHooksPath: Bool
            let chainedExistingHooksPath: String?
            var notice: String?

            if let existingRawPath {
                let expandedURL = resolveHooksDirectoryURL(from: existingRawPath)
                hooksDirectoryURL = expandedURL
                configuredGlobalHooksPath = false
                if expandedURL.standardized.path != defaultGlobalHooksDirectory.standardized.path {
                    chainedExistingHooksPath = expandedURL.path
                    notice = "Existing global core.hooksPath detected at '\(expandedURL.path)'. Chained pspm into '\(expandedURL.appendingPathComponent(Self.postCheckoutFileName).path)' without modifying core.hooksPath."
                } else {
                    chainedExistingHooksPath = nil
                }
            } else {
                hooksDirectoryURL = defaultGlobalHooksDirectory
                try FileManager.default.createDirectory(at: hooksDirectoryURL, withIntermediateDirectories: true)
                try writeGlobalHooksPath(hooksDirectoryURL.path)
                configuredGlobalHooksPath = true
                chainedExistingHooksPath = nil
            }

            let hookFileURL = hooksDirectoryURL.appendingPathComponent(Self.postCheckoutFileName)
            let alreadyInstalled = try installHookBlock(block, at: hookFileURL)

            if notice == nil, try hasOtherHookContent(at: hookFileURL) {
                notice = "Chained pspm into existing global hook at '\(hookFileURL.path)'."
            }

            return HookEnableResult(
                scope: .global,
                hookFilePath: hookFileURL.path,
                hooksDirectoryPath: hooksDirectoryURL.path,
                chainedExistingHooksPath: chainedExistingHooksPath,
                configuredGlobalHooksPath: configuredGlobalHooksPath,
                alreadyInstalled: alreadyInstalled,
                async: options.async,
                notice: notice
            )
        }
    }

    /// Disables the `pspm` `post-checkout` hook by removing only the delimited `pspm` block.
    public func disable(
        scope: HookScope? = nil,
        workingDirectory: String = FileManager.default.currentDirectoryPath
    ) throws -> HookDisableResult {
        let resolvedScope = try resolveScope(scope, workingDirectory: workingDirectory)

        switch resolvedScope {
        case .repo:
            let repoInfo = try resolveRepositoryHooksInfo(workingDirectory: workingDirectory)
            let removal = try removeHookBlockFromFile(at: repoInfo.hookFileURL)
            return HookDisableResult(
                scope: .repo,
                hookFilePath: repoInfo.hookFileURL.path,
                removed: removal.removed,
                preservedOtherContent: removal.preservedOtherContent,
                unsetGlobalHooksPath: false,
                notice: nil
            )

        case .global:
            guard let existingRawPath = try readGlobalHooksPath() else {
                return HookDisableResult(
                    scope: .global,
                    hookFilePath: nil,
                    removed: false,
                    preservedOtherContent: false,
                    unsetGlobalHooksPath: false,
                    notice: nil
                )
            }

            let hooksDirectoryURL = resolveHooksDirectoryURL(from: existingRawPath)
            let hookFileURL = hooksDirectoryURL.appendingPathComponent(Self.postCheckoutFileName)
            let removal = try removeHookBlockFromFile(at: hookFileURL)

            var unsetGlobalHooksPath = false
            var notice: String?
            let isDefaultDirectory = hooksDirectoryURL.standardized.path == defaultGlobalHooksDirectory.standardized.path

            if isDefaultDirectory && !removal.preservedOtherContent {
                let remainingEntries = (try? FileManager.default.contentsOfDirectory(atPath: hooksDirectoryURL.path)) ?? []
                if remainingEntries.isEmpty {
                    try unsetGlobalHooksPathConfig()
                    unsetGlobalHooksPath = true
                }
            } else if !isDefaultDirectory && removal.removed {
                notice = "Preserved existing global core.hooksPath at '\(hooksDirectoryURL.path)'."
            }

            return HookDisableResult(
                scope: .global,
                hookFilePath: hookFileURL.path,
                removed: removal.removed,
                preservedOtherContent: removal.preservedOtherContent,
                unsetGlobalHooksPath: unsetGlobalHooksPath,
                notice: notice
            )
        }
    }

    /// Returns structured status for both repository and global `post-checkout` hooks.
    public func status(
        workingDirectory: String = FileManager.default.currentDirectoryPath
    ) throws -> HookStatusReport {
        let repoStatus = try inspectRepoStatus(workingDirectory: workingDirectory)
        let globalStatus = try inspectGlobalStatus()
        return HookStatusReport(repo: repoStatus, global: globalStatus)
    }

    // MARK: - Private Helpers

    private struct RepositoryHooksInfo {
        let commonDirURL: URL
        let hooksDirectoryURL: URL
        let hookFileURL: URL
    }

    private func resolveScope(_ scope: HookScope?, workingDirectory: String) throws -> HookScope {
        if let scope {
            return scope
        }
        if (try? resolveRepositoryHooksInfo(workingDirectory: workingDirectory)) != nil {
            return .repo
        }
        throw GitHooksError.notInGitRepository(workingDirectory)
    }

    private func resolveRepositoryHooksInfo(workingDirectory: String) throws -> RepositoryHooksInfo {
        let result = try gitRunner.runGit(
            arguments: ["rev-parse", "--git-common-dir"],
            workingDirectory: workingDirectory
        )
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitCode == 0, !trimmed.isEmpty else {
            throw GitHooksError.notInGitRepository(workingDirectory)
        }

        let commonDirURL: URL
        if trimmed.hasPrefix("/") {
            commonDirURL = URL(fileURLWithPath: trimmed).standardized
        } else {
            commonDirURL = URL(fileURLWithPath: workingDirectory)
                .appendingPathComponent(trimmed)
                .standardized
        }

        let hooksDirectoryURL = commonDirURL.appendingPathComponent("hooks")
        let hookFileURL = hooksDirectoryURL.appendingPathComponent(Self.postCheckoutFileName)
        return RepositoryHooksInfo(
            commonDirURL: commonDirURL,
            hooksDirectoryURL: hooksDirectoryURL,
            hookFileURL: hookFileURL
        )
    }

    private func readGlobalHooksPath() throws -> String? {
        let result = try gitRunner.runGit(
            arguments: ["config", "--global", "--get", "core.hooksPath"],
            workingDirectory: nil
        )
        if result.exitCode == 1 && result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        guard result.exitCode == 0 else {
            throw GitHooksError.gitCommandFailed(
                command: "git config --global --get core.hooksPath",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func writeGlobalHooksPath(_ path: String) throws {
        let result = try gitRunner.runGit(
            arguments: ["config", "--global", "core.hooksPath", path],
            workingDirectory: nil
        )
        guard result.exitCode == 0 else {
            throw GitHooksError.gitCommandFailed(
                command: "git config --global core.hooksPath \(path)",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
    }

    private func unsetGlobalHooksPathConfig() throws {
        let result = try gitRunner.runGit(
            arguments: ["config", "--global", "--unset", "core.hooksPath"],
            workingDirectory: nil
        )
        if result.exitCode == 5 {
            return
        }
        guard result.exitCode == 0 else {
            throw GitHooksError.gitCommandFailed(
                command: "git config --global --unset core.hooksPath",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
    }

    private func resolveHooksDirectoryURL(from rawPath: String) -> URL {
        let expanded: String
        if rawPath == "~" {
            expanded = homeDirectory.path
        } else if rawPath.hasPrefix("~/") {
            let suffix = String(rawPath.dropFirst(2))
            expanded = homeDirectory.appendingPathComponent(suffix).path
        } else {
            expanded = (rawPath as NSString).expandingTildeInPath
        }

        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardized
        }
        return homeDirectory.appendingPathComponent(expanded).standardized
    }

    private func installHookBlock(_ block: String, at hookFileURL: URL) throws -> Bool {
        let fileManager = FileManager.default
        let hooksDirectoryURL = hookFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: hooksDirectoryURL, withIntermediateDirectories: true)

        let existingContent: String?
        if fileManager.fileExists(atPath: hookFileURL.path) {
            existingContent = try String(contentsOf: hookFileURL, encoding: .utf8)
        } else {
            existingContent = nil
        }

        let (updatedContent, alreadyInstalled) = try upsertHookBlock(
            in: existingContent,
            block: block,
            hookFilePath: hookFileURL.path
        )

        try updatedContent.write(to: hookFileURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: hookFileURL.path
        )
        return alreadyInstalled
    }

    private func upsertHookBlock(
        in existingContent: String?,
        block: String,
        hookFilePath: String
    ) throws -> (content: String, alreadyInstalled: Bool) {
        guard let existingContent,
              !existingContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return ("#!/bin/sh\n\n\(block)\n", false)
        }

        if let bounds = try findHookBlockBounds(in: existingContent, hookFilePath: hookFilePath) {
            var updated = existingContent
            updated.replaceSubrange(bounds.lineStart..<bounds.lineEnd, with: block)
            if !updated.hasSuffix("\n") {
                updated.append("\n")
            }
            return (updated, true)
        }

        var updated = existingContent
        if !updated.hasSuffix("\n") {
            updated.append("\n")
        }
        if !updated.hasSuffix("\n\n") {
            updated.append("\n")
        }
        updated.append(block)
        updated.append("\n")
        return (updated, false)
    }

    private func removeHookBlockFromFile(at hookFileURL: URL) throws -> (removed: Bool, preservedOtherContent: Bool) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: hookFileURL.path) else {
            return (false, false)
        }

        let existingContent = try String(contentsOf: hookFileURL, encoding: .utf8)
        guard let bounds = try findHookBlockBounds(in: existingContent, hookFilePath: hookFileURL.path) else {
            let hasOther = containsMeaningfulHookLines(existingContent)
            return (false, hasOther)
        }

        var before = String(existingContent[..<bounds.lineStart])
        var after = String(existingContent[bounds.removalEnd...])

        if after.isEmpty {
            while before.hasSuffix("\n\n") {
                before.removeLast()
            }
        } else {
            if before.hasSuffix("\n\n") && after.hasPrefix("\n") {
                after.removeFirst()
            } else if before.isEmpty && after.hasPrefix("\n") {
                after.removeFirst()
            }
        }

        var remaining = before + after
        if !remaining.isEmpty && !remaining.hasSuffix("\n") {
            remaining.append("\n")
        }

        let hasOther = containsMeaningfulHookLines(remaining)
        if hasOther {
            try remaining.write(to: hookFileURL, atomically: true, encoding: .utf8)
        } else {
            try fileManager.removeItem(at: hookFileURL)
        }

        return (true, hasOther)
    }

    private struct HookBlockBounds {
        let lineStart: String.Index
        let lineEnd: String.Index
        let removalEnd: String.Index
    }

    private func findHookBlockBounds(in content: String, hookFilePath: String) throws -> HookBlockBounds? {
        let startRange = content.range(of: Self.blockStartMarker)
        let endRange = content.range(of: Self.blockEndMarker)

        switch (startRange, endRange) {
        case (nil, nil):
            return nil
        case (.some, nil), (nil, .some):
            throw GitHooksError.malformedHookBlock(hookFilePath)
        case (.some(let sRange), .some(let eRange)):
            guard sRange.upperBound <= eRange.lowerBound else {
                throw GitHooksError.malformedHookBlock(hookFilePath)
            }
            let lineStart = content.lineRange(for: sRange).lowerBound
            let endLineRange = content.lineRange(for: eRange)
            var lineEnd = endLineRange.upperBound
            if lineEnd > content.startIndex && content[content.index(before: lineEnd)] == "\n" {
                lineEnd = content.index(before: lineEnd)
            }
            return HookBlockBounds(
                lineStart: lineStart,
                lineEnd: lineEnd,
                removalEnd: endLineRange.upperBound
            )
        }
    }

    private func hasOtherHookContent(at hookFileURL: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: hookFileURL.path) else {
            return false
        }
        let content = try String(contentsOf: hookFileURL, encoding: .utf8)
        if let bounds = try findHookBlockBounds(in: content, hookFilePath: hookFileURL.path) {
            let outside = String(content[..<bounds.lineStart]) + String(content[bounds.removalEnd...])
            return containsMeaningfulHookLines(outside)
        }
        return containsMeaningfulHookLines(content)
    }

    private func containsMeaningfulHookLines(_ content: String) -> Bool {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#!") {
                continue
            }
            return true
        }
        return false
    }

    private func inspectRepoStatus(workingDirectory: String) throws -> ScopedHookStatus {
        guard let repoInfo = try? resolveRepositoryHooksInfo(workingDirectory: workingDirectory) else {
            return ScopedHookStatus(
                scope: .repo,
                isAvailable: false,
                isActive: false,
                isExecutable: false,
                isAsync: false,
                hooksDirectoryPath: nil,
                hookFilePath: nil,
                gitCommonDirPath: nil
            )
        }

        let inspected = try inspectHookFile(at: repoInfo.hookFileURL)
        return ScopedHookStatus(
            scope: .repo,
            isAvailable: true,
            isActive: inspected.hasPSPMBlock,
            isExecutable: inspected.isExecutable,
            isAsync: inspected.isAsync,
            hooksDirectoryPath: repoInfo.hooksDirectoryURL.path,
            hookFilePath: repoInfo.hookFileURL.path,
            gitCommonDirPath: repoInfo.commonDirURL.path,
            configuredHooksPath: nil,
            isChainedWithExistingHooks: inspected.hasOtherContent,
            chainsExistingGlobalHooksPath: false
        )
    }

    private func inspectGlobalStatus() throws -> ScopedHookStatus {
        guard let rawPath = try readGlobalHooksPath() else {
            return ScopedHookStatus(
                scope: .global,
                isAvailable: true,
                isActive: false,
                isExecutable: false,
                isAsync: false,
                hooksDirectoryPath: nil,
                hookFilePath: nil,
                gitCommonDirPath: nil,
                configuredHooksPath: nil,
                isChainedWithExistingHooks: false,
                chainsExistingGlobalHooksPath: false
            )
        }

        let hooksDirectoryURL = resolveHooksDirectoryURL(from: rawPath)
        let hookFileURL = hooksDirectoryURL.appendingPathComponent(Self.postCheckoutFileName)
        let inspected = try inspectHookFile(at: hookFileURL)
        let chainsCustomPath = hooksDirectoryURL.standardized.path != defaultGlobalHooksDirectory.standardized.path

        return ScopedHookStatus(
            scope: .global,
            isAvailable: true,
            isActive: inspected.hasPSPMBlock,
            isExecutable: inspected.isExecutable,
            isAsync: inspected.isAsync,
            hooksDirectoryPath: hooksDirectoryURL.path,
            hookFilePath: hookFileURL.path,
            gitCommonDirPath: nil,
            configuredHooksPath: rawPath,
            isChainedWithExistingHooks: inspected.hasOtherContent || chainsCustomPath,
            chainsExistingGlobalHooksPath: chainsCustomPath
        )
    }

    private struct InspectedHookFile {
        let hasPSPMBlock: Bool
        let isExecutable: Bool
        let isAsync: Bool
        let hasOtherContent: Bool
    }

    private func inspectHookFile(at hookFileURL: URL) throws -> InspectedHookFile {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: hookFileURL.path) else {
            return InspectedHookFile(
                hasPSPMBlock: false,
                isExecutable: false,
                isAsync: false,
                hasOtherContent: false
            )
        }

        let isExecutable = fileManager.isExecutableFile(atPath: hookFileURL.path)
        let content = try String(contentsOf: hookFileURL, encoding: .utf8)

        if let bounds = try findHookBlockBounds(in: content, hookFilePath: hookFileURL.path) {
            let blockText = String(content[bounds.lineStart..<bounds.lineEnd])
            let outside = String(content[..<bounds.lineStart]) + String(content[bounds.removalEnd...])
            return InspectedHookFile(
                hasPSPMBlock: true,
                isExecutable: isExecutable,
                isAsync: blockText.contains(">/dev/null 2>&1 &"),
                hasOtherContent: containsMeaningfulHookLines(outside)
            )
        }

        return InspectedHookFile(
            hasPSPMBlock: false,
            isExecutable: isExecutable,
            isAsync: false,
            hasOtherContent: containsMeaningfulHookLines(content)
        )
    }
}

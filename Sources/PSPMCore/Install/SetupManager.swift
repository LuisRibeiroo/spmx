import Foundation

/// Errors raised during `pspm setup` or `pspm uninstall`.
public enum SetupError: Error, LocalizedError, Sendable, Equatable {
    case emptyBinaryPath

    public var errorDescription: String? {
        switch self {
        case .emptyBinaryPath:
            return "Binary path for pspm shim symlink cannot be empty."
        }
    }
}

/// Supported interactive shells for `PATH` configuration.
public enum ShellKind: String, Sendable, CaseIterable, Equatable {
    case zsh
    case bash
    case fish

    /// Detects the shell kind from a `SHELL` path or name, defaulting to `.zsh` on macOS.
    public static func detect(from shell: String?) -> ShellKind {
        guard let shell, !shell.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .zsh
        }
        let name = URL(fileURLWithPath: shell).lastPathComponent.lowercased()
        if name.contains("fish") {
            return .fish
        }
        if name.contains("bash") {
            return .bash
        }
        return .zsh
    }

    /// Relative path from `$HOME` to the shell's RC file.
    public var rcRelativePath: String {
        switch self {
        case .zsh:
            return ".zshrc"
        case .bash:
            return ".bashrc"
        case .fish:
            return ".config/fish/config.fish"
        }
    }

    /// Display path with `~/` prefix.
    public var displayRCPath: String {
        "~/\(rcRelativePath)"
    }

    /// Command the user runs to activate the updated `PATH` in the current shell session.
    public var activationCommand: String {
        "source \(displayRCPath)"
    }

    /// Returns the URL of the RC file inside the given home directory.
    public func rcFileURL(homeDirectory: URL) -> URL {
        homeDirectory.appendingPathComponent(rcRelativePath)
    }

    /// Returns the shell-specific PATH configuration lines to place inside the managed block.
    public func pathExportLines() -> String {
        switch self {
        case .zsh, .bash:
            return #"export PATH="$HOME/.pspm/shims:$HOME/.pspm/bin:$PATH""#
        case .fish:
            return #"set -gx PATH "$HOME/.pspm/shims" "$HOME/.pspm/bin" $PATH"#
        }
    }

    /// Returns the full `# >>> pspm >>>` ... `# <<< pspm <<<` block for this shell.
    public func managedBlock() -> String {
        """
        \(SetupManager.blockStartMarker)
        \(pathExportLines())
        \(SetupManager.blockEndMarker)
        """
    }
}

/// Result returned by `SetupManager.setup(...)`.
public struct SetupResult: Sendable, Equatable {
    public let pspmDirectory: URL
    public let binDirectory: URL
    public let shimsDirectory: URL
    public let storeDirectory: URL
    public let compilationCacheDirectory: URL
    public let binaryPath: URL
    public let shimPaths: [URL]
    public let detectedShell: ShellKind
    public let modifiedShellRC: URL?
    public let activationCommand: String

    public init(
        pspmDirectory: URL,
        binDirectory: URL,
        shimsDirectory: URL,
        storeDirectory: URL,
        compilationCacheDirectory: URL,
        binaryPath: URL,
        shimPaths: [URL],
        detectedShell: ShellKind,
        modifiedShellRC: URL?,
        activationCommand: String
    ) {
        self.pspmDirectory = pspmDirectory
        self.binDirectory = binDirectory
        self.shimsDirectory = shimsDirectory
        self.storeDirectory = storeDirectory
        self.compilationCacheDirectory = compilationCacheDirectory
        self.binaryPath = binaryPath
        self.shimPaths = shimPaths
        self.detectedShell = detectedShell
        self.modifiedShellRC = modifiedShellRC
        self.activationCommand = activationCommand
    }

    /// Human-readable post-install / setup summary banner.
    public func summaryBanner() -> String {
        let shimNames = SetupManager.shimNames.joined(separator: ", ")
        var lines: [String] = [
            "pspm setup complete!",
            "",
            "Directories:",
            "  Store:             \(storeDirectory.path)",
            "  Compilation Cache: \(compilationCacheDirectory.path)",
            "  Shims:             \(shimsDirectory.path)",
            "",
            "Shims (active by default):",
            "  \(shimNames) -> \(binaryPath.path)",
            "  Existing and new Flutter, Xcode, and SwiftPM builds will use the global cache automatically.",
            ""
        ]

        if let modifiedShellRC {
            lines.append("Shell PATH configured:")
            lines.append("  Updated \(modifiedShellRC.path)")
            lines.append("  Activate now by running: \(activationCommand)")
        } else {
            lines.append("Shell PATH was not modified (--no-modify-path):")
            lines.append("  Add shims to your PATH manually by running:")
            lines.append("    \(activationCommand)")
        }

        lines.append("")
        lines.append("Git Hooks (disabled by default):")
        lines.append("  pspm never modifies your Git hooks without consent.")
        lines.append("  Enable optional post-checkout hooks so `git worktree add` pre-warms SourcePackages")
        lines.append("  immediately (even before opening Xcode GUI):")
        lines.append("    pspm hooks enable --global")

        return lines.joined(separator: "\n")
    }
}

/// Result returned by `SetupManager.uninstall(...)`.
public struct UninstallResult: Sendable, Equatable {
    public let removedShimsDirectory: Bool
    public let removedBinary: Bool
    public let cleanedShellRCs: [URL]
    public let purgedStore: Bool
    public let purgedCompilationCache: Bool

    public init(
        removedShimsDirectory: Bool,
        removedBinary: Bool,
        cleanedShellRCs: [URL],
        purgedStore: Bool,
        purgedCompilationCache: Bool
    ) {
        self.removedShimsDirectory = removedShimsDirectory
        self.removedBinary = removedBinary
        self.cleanedShellRCs = cleanedShellRCs
        self.purgedStore = purgedStore
        self.purgedCompilationCache = purgedCompilationCache
    }
}

/// Manages global `pspm` directory initialization, shim symlinks, shell RC integration, and uninstall.
public struct SetupManager: Sendable {
    public static let shimNames: [String] = ["flutter", "xcodebuild", "swift"]
    public static let blockStartMarker = "# >>> pspm >>>"
    public static let blockEndMarker = "# <<< pspm <<<"

    public init() {}

    /// Initializes `~/.pspm/{bin,shims,store,compilation-cache}`, creates/updates shim symlinks,
    /// and idempotently injects PATH setup into the detected shell profile unless `noModifyPath` is true.
    public static func setup(
        noModifyPath: Bool = false,
        binaryPath: URL? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        shell: String? = ProcessInfo.processInfo.environment["SHELL"],
        fileManager: FileManager = .default
    ) throws -> SetupResult {
        let pspmDir = homeDirectory.appendingPathComponent(".pspm")
        let binDir = pspmDir.appendingPathComponent("bin")
        let shimsDir = pspmDir.appendingPathComponent("shims")
        let storeDir = pspmDir.appendingPathComponent("store")
        let compilationCacheDir = pspmDir.appendingPathComponent("compilation-cache")

        for directory in [binDir, shimsDir, storeDir, compilationCacheDir] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let targetBinary = binaryPath ?? binDir.appendingPathComponent("pspm")
        guard !targetBinary.path.isEmpty else {
            throw SetupError.emptyBinaryPath
        }

        var createdShims: [URL] = []
        for shimName in shimNames {
            let shimURL = shimsDir.appendingPathComponent(shimName)
            try createOrUpdateSymlink(at: shimURL, destination: targetBinary, fileManager: fileManager)
            createdShims.append(shimURL)
        }

        let detectedShell = ShellKind.detect(from: shell)
        let modifiedRC: URL?
        let activationCommand: String

        if noModifyPath {
            modifiedRC = nil
            activationCommand = detectedShell.pathExportLines()
        } else {
            let rcURL = detectedShell.rcFileURL(homeDirectory: homeDirectory)
            try upsertBlock(detectedShell.managedBlock(), in: rcURL, fileManager: fileManager)
            modifiedRC = rcURL
            activationCommand = detectedShell.activationCommand
        }

        return SetupResult(
            pspmDirectory: pspmDir,
            binDirectory: binDir,
            shimsDirectory: shimsDir,
            storeDirectory: storeDir,
            compilationCacheDirectory: compilationCacheDir,
            binaryPath: targetBinary,
            shimPaths: createdShims,
            detectedShell: detectedShell,
            modifiedShellRC: modifiedRC,
            activationCommand: activationCommand
        )
    }

    /// Removes `~/.pspm/shims`, `~/.pspm/bin/pspm`, and `# >>> pspm >>>` blocks from shell RC files.
    /// Removes `~/.pspm/store` and `~/.pspm/compilation-cache` only when `purge` is `true`.
    public static func uninstall(
        purge: Bool = false,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) throws -> UninstallResult {
        let pspmDir = homeDirectory.appendingPathComponent(".pspm")
        let shimsDir = pspmDir.appendingPathComponent("shims")
        let binaryURL = pspmDir.appendingPathComponent("bin").appendingPathComponent("pspm")
        let storeDir = pspmDir.appendingPathComponent("store")
        let compilationCacheDir = pspmDir.appendingPathComponent("compilation-cache")

        let removedShims = try removeIfExists(at: shimsDir, fileManager: fileManager)
        let removedBinary = try removeIfExists(at: binaryURL, fileManager: fileManager)

        var cleanedRCs: [URL] = []
        for shellKind in ShellKind.allCases {
            let rcURL = shellKind.rcFileURL(homeDirectory: homeDirectory)
            if try removeManagedBlock(from: rcURL, fileManager: fileManager) {
                cleanedRCs.append(rcURL)
            }
        }

        var purgedStore = false
        var purgedCompilationCache = false
        if purge {
            purgedStore = try removeIfExists(at: storeDir, fileManager: fileManager)
            purgedCompilationCache = try removeIfExists(at: compilationCacheDir, fileManager: fileManager)
        }

        return UninstallResult(
            removedShimsDirectory: removedShims,
            removedBinary: removedBinary,
            cleanedShellRCs: cleanedRCs,
            purgedStore: purgedStore,
            purgedCompilationCache: purgedCompilationCache
        )
    }

    // MARK: - Helpers

    private static func createOrUpdateSymlink(
        at shimURL: URL,
        destination: URL,
        fileManager: FileManager
    ) throws {
        // Use attributesOfItem (lstat) so dangling symlinks are detected and replaced cleanly.
        if (try? fileManager.attributesOfItem(atPath: shimURL.path)) != nil {
            if let existingDest = try? fileManager.destinationOfSymbolicLink(atPath: shimURL.path),
               existingDest == destination.path {
                return
            }
            try fileManager.removeItem(at: shimURL)
        }
        try fileManager.createSymbolicLink(
            atPath: shimURL.path,
            withDestinationPath: destination.path
        )
    }

    private static func removeIfExists(at url: URL, fileManager: FileManager) throws -> Bool {
        guard (try? fileManager.attributesOfItem(atPath: url.path)) != nil else {
            return false
        }
        try fileManager.removeItem(at: url)
        return true
    }

    private static func upsertBlock(
        _ block: String,
        in rcURL: URL,
        fileManager: FileManager
    ) throws {
        let parentDir = rcURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let existingContent: String
        if fileManager.fileExists(atPath: rcURL.path) {
            existingContent = try String(contentsOf: rcURL, encoding: .utf8)
        } else {
            existingContent = ""
        }

        let updatedContent = upsertManagedBlock(block, in: existingContent)
        try updatedContent.write(to: rcURL, atomically: true, encoding: .utf8)
    }

    private static func removeManagedBlock(
        from rcURL: URL,
        fileManager: FileManager
    ) throws -> Bool {
        guard fileManager.fileExists(atPath: rcURL.path) else {
            return false
        }

        let existingContent = try String(contentsOf: rcURL, encoding: .utf8)
        let (updatedContent, didModify) = stripManagedBlock(from: existingContent)
        guard didModify else {
            return false
        }

        try updatedContent.write(to: rcURL, atomically: true, encoding: .utf8)
        return true
    }

    static func upsertManagedBlock(_ block: String, in existingContent: String) -> String {
        if existingContent.isEmpty {
            return block + "\n"
        }

        var lines = existingContent.components(separatedBy: "\n")
        if let (startIdx, endIdx) = findMarkerRange(in: lines) {
            let blockLines = block.components(separatedBy: "\n")
            lines.replaceSubrange(startIdx...endIdx, with: blockLines)
            var result = lines.joined(separator: "\n")
            if !result.hasSuffix("\n") {
                result.append("\n")
            }
            return result
        }

        var base = existingContent
        if !base.hasSuffix("\n") {
            base.append("\n")
        }
        if !base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !base.hasSuffix("\n\n") {
            base.append("\n")
        }
        return base + block + "\n"
    }

    static func stripManagedBlock(from existingContent: String) -> (content: String, didModify: Bool) {
        var lines = existingContent.components(separatedBy: "\n")
        var didModify = false

        while let (startIdx, endIdx) = findMarkerRange(in: lines) {
            didModify = true
            lines.removeSubrange(startIdx...endIdx)

            // Clean up a single blank separator line left immediately adjacent to the removed block.
            if startIdx > 0 && startIdx - 1 < lines.count && lines[startIdx - 1].isEmpty {
                let trailingIsOnlyEmpty = lines[startIdx...].allSatisfy { $0.isEmpty }
                if trailingIsOnlyEmpty || (startIdx < lines.count && lines[startIdx].isEmpty) {
                    lines.remove(at: startIdx - 1)
                }
            } else if startIdx == 0 && startIdx < lines.count && lines[startIdx].isEmpty {
                let hasContentAfter = lines.contains { !$0.isEmpty }
                if hasContentAfter {
                    lines.remove(at: startIdx)
                }
            }
        }

        guard didModify else {
            return (existingContent, false)
        }

        if lines.allSatisfy({ $0.isEmpty }) {
            return ("", true)
        }

        var result = lines.joined(separator: "\n")
        if !result.hasSuffix("\n") {
            result.append("\n")
        }
        return (result, true)
    }

    private static func findMarkerRange(in lines: [String]) -> (Int, Int)? {
        guard let startIdx = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == blockStartMarker
        }) else {
            return nil
        }

        guard let endIdx = lines[startIdx...].firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == blockEndMarker
        }) else {
            return nil
        }

        return (startIdx, endIdx)
    }
}

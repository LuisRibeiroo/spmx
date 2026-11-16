import Foundation

/// Errors raised during `spmx setup` or `spmx uninstall`.
public enum SetupError: Error, LocalizedError, Sendable, Equatable {
    case emptyBinaryPath

    public var errorDescription: String? {
        switch self {
        case .emptyBinaryPath:
            return "Binary path for spmx shim symlink cannot be empty."
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
            return #"export PATH="$HOME/.spmx/shims:$HOME/.spmx/bin:$PATH""#
        case .fish:
            return #"set -gx PATH "$HOME/.spmx/shims" "$HOME/.spmx/bin" $PATH"#
        }
    }

    /// Returns the full `# >>> spmx >>>` ... `# <<< spmx <<<` block for this shell.
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
    public let spmxDirectory: URL
    public let binDirectory: URL
    public let shimsDirectory: URL
    public let storeDirectory: URL
    public let compilationCacheDirectory: URL
    public let binaryPath: URL
    public let shimPaths: [URL]
    public let detectedShell: ShellKind
    public let modifiedShellRC: URL?
    public let activationCommand: String
    public let localBinSymlink: URL?

    public init(
        spmxDirectory: URL,
        binDirectory: URL,
        shimsDirectory: URL,
        storeDirectory: URL,
        compilationCacheDirectory: URL,
        binaryPath: URL,
        shimPaths: [URL],
        detectedShell: ShellKind,
        modifiedShellRC: URL?,
        activationCommand: String,
        localBinSymlink: URL? = nil
    ) {
        self.spmxDirectory = spmxDirectory
        self.binDirectory = binDirectory
        self.shimsDirectory = shimsDirectory
        self.storeDirectory = storeDirectory
        self.compilationCacheDirectory = compilationCacheDirectory
        self.binaryPath = binaryPath
        self.shimPaths = shimPaths
        self.detectedShell = detectedShell
        self.modifiedShellRC = modifiedShellRC
        self.activationCommand = activationCommand
        self.localBinSymlink = localBinSymlink
    }

    /// Human-readable post-install / setup summary banner.
    public func summaryBanner(style: TerminalStyle = .stdout) -> String {
        let shimNames = SetupManager.shimNames.joined(separator: ", ")
        var lines: [String] = [
            "\(style.successIcon) \(style.successText("spmx setup complete!"))",
            "",
            style.section("Installation:"),
            style.stepSuccess("Directories:", detail: "\(style.primary(spmxDirectory.path)) \(style.gray("(store, compilation-cache, bin, shims)"))"),
            "    \(style.gray("Store:"))             \(style.gray(storeDirectory.path))",
            "    \(style.gray("Compilation Cache:")) \(style.gray(compilationCacheDirectory.path))",
            "    \(style.gray("Shims:"))             \(style.gray(shimsDirectory.path))",
            style.stepSuccess("Shims (active by default):", detail: "\(style.primary(shimNames)) \(style.gray("-> \(binaryPath.path)"))"),
            "    \(style.gray("Existing and new Flutter, Xcode, and SwiftPM builds will use the global cache automatically."))"
        ]

        if let modifiedShellRC {
            lines.append(style.stepSuccess("Shell PATH configured:", detail: style.gray(modifiedShellRC.path)))
        } else {
            lines.append(style.stepSkipped("Shell PATH was not modified (--no-modify-path):", detail: "skipped RC update"))
        }

        lines.append("")
        lines.append(tipsSection(style: style))

        return lines.joined(separator: "\n")
    }

    /// Low-focus gray tips section displayed after setup completes.
    public func tipsSection(style: TerminalStyle = .stdout) -> String {
        var lines: [String] = []
        lines.append(style.tipItalic("Tips:"))

        if modifiedShellRC != nil {
            lines.append("  \(style.tip("›")) \(style.tip("Activate in this shell now:")) \(style.tipCommand("`\(activationCommand)`"))")
        } else {
            lines.append("  \(style.tip("›")) \(style.tip("Add shims to your PATH manually:")) \(style.tipCommand("`\(activationCommand)`"))")
        }

        lines.append("  \(style.tip("›")) \(style.tip("Git Hooks (disabled by default): spmx never modifies your Git hooks without consent."))")
        lines.append("    \(style.formatInlineCode("Pre-warm SourcePackages on `git worktree add` (even before opening Xcode GUI):", baseCodes: ["90", "3"], codeCodes: ["90", "1"]))")
        lines.append("      \(style.tipCommand("`spmx hooks enable --global`"))")
        lines.append("  \(style.tip("›")) \(style.tip("Verify your environment anytime with:")) \(style.tipCommand("`spmx doctor`"))")

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

/// Step progress events emitted during `SetupManager.setup(...)`.
public enum SetupStepEvent: Sendable, Equatable {
    case running(step: String, detail: String?)
    case completed(step: String, detail: String?)
    case skipped(step: String, detail: String?)
}

/// Manages global `spmx` directory initialization, shim symlinks, shell RC integration, and uninstall.
public struct SetupManager: Sendable {
    public static let shimNames: [String] = ["flutter", "xcodebuild", "swift"]
    public static let blockStartMarker = "# >>> spmx >>>"
    public static let blockEndMarker = "# <<< spmx <<<"

    public init() {}

    /// Initializes `~/.spmx/{bin,shims,store,compilation-cache}`, creates/updates shim symlinks,
    /// and idempotently injects PATH setup into the detected shell profile unless `noModifyPath` is true.
    public static func setup(
        noModifyPath: Bool = false,
        binaryPath: URL? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        shell: String? = ProcessInfo.processInfo.environment["SHELL"],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        stepObserver: (@Sendable (SetupStepEvent) -> Void)? = nil
    ) throws -> SetupResult {
        let spmxDir = homeDirectory.appendingPathComponent(".spmx")
        let binDir = spmxDir.appendingPathComponent("bin")
        let shimsDir = spmxDir.appendingPathComponent("shims")
        let storeDir = spmxDir.appendingPathComponent("store")
        let compilationCacheDir = spmxDir.appendingPathComponent("compilation-cache")

        stepObserver?(.running(step: "Initializing directories", detail: spmxDir.path))
        for directory in [binDir, shimsDir, storeDir, compilationCacheDir] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        stepObserver?(.completed(step: "Directories initialized", detail: spmxDir.path))

        let installedBinary = binDir.appendingPathComponent("spmx")
        let requestedBinary = binaryPath ?? installedBinary
        guard !requestedBinary.path.isEmpty else {
            throw SetupError.emptyBinaryPath
        }

        let targetBinary: URL
        let resolvedRequested = requestedBinary.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedInstalled = installedBinary.standardizedFileURL.resolvingSymlinksInPath()

        if resolvedRequested.path == resolvedInstalled.path {
            targetBinary = installedBinary
        } else if fileManager.isExecutableFile(atPath: resolvedRequested.path) {
            stepObserver?(.running(step: "Installing spmx binary", detail: installedBinary.path))
            try installBinary(from: resolvedRequested, to: installedBinary, fileManager: fileManager)
            stepObserver?(.completed(step: "Binary installed", detail: installedBinary.path))
            targetBinary = installedBinary
        } else {
            targetBinary = requestedBinary
        }

        stepObserver?(.running(step: "Linking PATH shims", detail: shimNames.joined(separator: ", ")))
        var createdShims: [URL] = []
        for shimName in shimNames {
            let shimURL = shimsDir.appendingPathComponent(shimName)
            try createOrUpdateSymlink(at: shimURL, destination: targetBinary, fileManager: fileManager)
            createdShims.append(shimURL)
        }
        stepObserver?(.completed(step: "Shims linked", detail: "\(shimNames.joined(separator: ", ")) -> \(targetBinary.path)"))

        var localBinSymlink: URL?
        let localBinDir = homeDirectory.appendingPathComponent(".local/bin").standardizedFileURL
        if fileManager.isExecutableFile(atPath: targetBinary.path),
           isDirectoryOnPATH(localBinDir, environment: environment, homeDirectory: homeDirectory) {
            let localBinLink = localBinDir.appendingPathComponent("spmx")
            if shouldManageLocalBinLink(at: localBinLink, spmxDirectory: spmxDir, fileManager: fileManager) {
                try fileManager.createDirectory(at: localBinDir, withIntermediateDirectories: true)
                try createOrUpdateSymlink(at: localBinLink, destination: targetBinary, fileManager: fileManager)
                localBinSymlink = localBinLink
                stepObserver?(.completed(step: "Linked spmx in PATH", detail: localBinLink.path))
            }
        }

        let detectedShell = ShellKind.detect(from: shell)
        let modifiedRC: URL?
        let activationCommand: String

        if noModifyPath {
            modifiedRC = nil
            activationCommand = detectedShell.pathExportLines()
            stepObserver?(.skipped(step: "Shell PATH configuration", detail: "--no-modify-path"))
        } else {
            let rcURL = detectedShell.rcFileURL(homeDirectory: homeDirectory)
            stepObserver?(.running(step: "Configuring shell PATH", detail: rcURL.path))
            try upsertBlock(detectedShell.managedBlock(), in: rcURL, fileManager: fileManager)
            modifiedRC = rcURL
            activationCommand = detectedShell.activationCommand
            stepObserver?(.completed(step: "Shell PATH configured", detail: rcURL.path))
        }

        return SetupResult(
            spmxDirectory: spmxDir,
            binDirectory: binDir,
            shimsDirectory: shimsDir,
            storeDirectory: storeDir,
            compilationCacheDirectory: compilationCacheDir,
            binaryPath: targetBinary,
            shimPaths: createdShims,
            detectedShell: detectedShell,
            modifiedShellRC: modifiedRC,
            activationCommand: activationCommand,
            localBinSymlink: localBinSymlink
        )
    }

    /// Removes `~/.spmx/shims`, `~/.spmx/bin/spmx`, managed `~/.local/bin/spmx` symlink,
    /// and `# >>> spmx >>>` blocks from shell RC files.
    /// Removes `~/.spmx/store` and `~/.spmx/compilation-cache` only when `purge` is `true`.
    public static func uninstall(
        purge: Bool = false,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) throws -> UninstallResult {
        let spmxDir = homeDirectory.appendingPathComponent(".spmx")
        let shimsDir = spmxDir.appendingPathComponent("shims")
        let binaryURL = spmxDir.appendingPathComponent("bin").appendingPathComponent("spmx")
        let storeDir = spmxDir.appendingPathComponent("store")
        let compilationCacheDir = spmxDir.appendingPathComponent("compilation-cache")

        let removedShims = try removeIfExists(at: shimsDir, fileManager: fileManager)
        let removedBinary = try removeIfExists(at: binaryURL, fileManager: fileManager)

        let localBinLink = homeDirectory.appendingPathComponent(".local/bin/spmx")
        if isSymlinkPointingInside(localBinLink, directory: spmxDir, fileManager: fileManager) {
            _ = try? removeIfExists(at: localBinLink, fileManager: fileManager)
        }

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

    private static func installBinary(
        from sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager
    ) throws {
        let tempURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".spmx.tmp.\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: tempURL) }

        try fileManager.copyItem(at: sourceURL, to: tempURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempURL.path)

        if (try? fileManager.attributesOfItem(atPath: destinationURL.path)) != nil {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: tempURL, to: destinationURL)
    }

    private static func isDirectoryOnPATH(
        _ directoryURL: URL,
        environment: [String: String],
        homeDirectory: URL
    ) -> Bool {
        guard let pathEnv = environment["PATH"], !pathEnv.isEmpty else {
            return false
        }
        let targetResolved = directoryURL.standardizedFileURL.resolvingSymlinksInPath().path
        let targetStandardized = directoryURL.standardizedFileURL.path
        let tildePrefix = "~/"
        let homePath = homeDirectory.path

        for rawEntry in pathEnv.split(separator: ":") {
            var entry = String(rawEntry)
            if entry.hasPrefix(tildePrefix) {
                entry = homePath + "/" + String(entry.dropFirst(tildePrefix.count))
            }
            let entryURL = URL(fileURLWithPath: entry).standardizedFileURL
            if entryURL.path == targetStandardized || entryURL.resolvingSymlinksInPath().path == targetResolved {
                return true
            }
        }
        return false
    }

    private static func shouldManageLocalBinLink(
        at linkURL: URL,
        spmxDirectory: URL,
        fileManager: FileManager
    ) -> Bool {
        guard (try? fileManager.attributesOfItem(atPath: linkURL.path)) != nil else {
            return true
        }
        return isSymlinkPointingInside(linkURL, directory: spmxDirectory, fileManager: fileManager)
    }

    private static func isSymlinkPointingInside(
        _ linkURL: URL,
        directory: URL,
        fileManager: FileManager
    ) -> Bool {
        guard let rawDest = try? fileManager.destinationOfSymbolicLink(atPath: linkURL.path) else {
            return false
        }
        let resolvedDest: URL
        if rawDest.hasPrefix("/") {
            resolvedDest = URL(fileURLWithPath: rawDest).standardizedFileURL
        } else {
            resolvedDest = linkURL.deletingLastPathComponent().appendingPathComponent(rawDest).standardizedFileURL
        }
        let dirPath = directory.standardizedFileURL.path
        return resolvedDest.path == dirPath || resolvedDest.path.hasPrefix(dirPath + "/")
    }

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

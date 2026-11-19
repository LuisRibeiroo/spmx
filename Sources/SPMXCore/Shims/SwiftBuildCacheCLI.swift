import Foundation

/// Shared wrapper for SwiftPM SE-0547 (`swift package build-cache`) CLI subcommands and output parsing.
public enum SwiftBuildCacheCLI {
    public typealias CommandRunner = @Sendable (
        _ executablePath: String,
        _ arguments: [String],
        _ environment: [String: String]
    ) throws -> CommandResult

    public static let defaultSizeLimit = "20G"

    public struct GlobalConfiguration: Equatable, Sendable {
        public let isEnabled: Bool?
        public let path: String?
        public let sizeLimit: String?

        public init(isEnabled: Bool? = nil, path: String? = nil, sizeLimit: String? = nil) {
            self.isEnabled = isEnabled
            self.path = path
            self.sizeLimit = sizeLimit
        }
    }

    public static let defaultRunner: CommandRunner = { executablePath, arguments, environment in
        let result = try CommandExecutor.run(
            executablePath: executablePath,
            arguments: arguments,
            environment: environment
        )
        return CommandResult(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr
        )
    }

    /// Detects whether `swift build --help` advertises SE-0547 (`--enable-build-caching`)
    /// or legacy `--enable-build-cache`.
    public static func detectCapability(fromBuildHelpOutput output: String) -> SwiftBuildCacheCapability {
        if output.contains("--enable-build-caching") {
            return .se0547
        }
        if output.contains("--enable-build-cache") {
            return .legacyBuildCache
        }
        return .unsupported
    }

    /// Probes whether the `swift` executable supports `swift package build-cache --help`.
    public static func isSubcommandSupported(
        swiftPath: String,
        environment: [String: String],
        runner: CommandRunner = defaultRunner
    ) -> Bool {
        guard let result = try? runner(swiftPath, ["package", "build-cache", "--help"], environment),
              result.exitCode == 0
        else {
            return false
        }
        let combined = (result.stdout + "\n" + result.stderr).lowercased()
        return combined.contains("configure")
            || combined.contains("get-configuration")
            || combined.contains("build-cache")
    }

    /// Configures SwiftPM's global SE-0547 build cache via `swift package build-cache configure --global`.
    @discardableResult
    public static func configureGlobal(
        swiftPath: String,
        cachePath: String,
        sizeLimit: String = defaultSizeLimit,
        environment: [String: String],
        runner: CommandRunner = defaultRunner
    ) -> Bool {
        let arguments = [
            "package", "build-cache", "configure",
            "--global",
            "--enable-caching",
            "--path", cachePath,
            "--size-limit", sizeLimit
        ]
        guard let result = try? runner(swiftPath, arguments, environment) else {
            return false
        }
        return result.exitCode == 0
    }

    /// Resets SwiftPM's global SE-0547 build cache configuration via `swift package build-cache reset-configuration --global`.
    @discardableResult
    public static func resetGlobalConfiguration(
        swiftPath: String,
        environment: [String: String],
        runner: CommandRunner = defaultRunner
    ) -> Bool {
        guard let result = try? runner(
            swiftPath,
            ["package", "build-cache", "reset-configuration", "--global"],
            environment
        ) else {
            return false
        }
        return result.exitCode == 0
    }

    /// Invokes `swift package build-cache clean` to clear the configured SwiftPM compilation cache.
    @discardableResult
    public static func clean(
        swiftPath: String,
        environment: [String: String],
        runner: CommandRunner = defaultRunner
    ) -> Bool {
        guard let result = try? runner(
            swiftPath,
            ["package", "build-cache", "clean"],
            environment
        ) else {
            return false
        }
        return result.exitCode == 0
    }

    /// Queries `swift package build-cache get-configuration` and parses its output.
    public static func getGlobalConfiguration(
        swiftPath: String,
        environment: [String: String],
        runner: CommandRunner = defaultRunner
    ) -> GlobalConfiguration? {
        guard let result = try? runner(
            swiftPath,
            ["package", "build-cache", "get-configuration"],
            environment
        ),
              result.exitCode == 0
        else {
            return nil
        }
        let primary = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = primary.isEmpty ? result.stderr : result.stdout
        return parseConfiguration(output: text)
    }

    /// Parses JSON or human-readable key-value output from `swift package build-cache get-configuration`.
    public static func parseConfiguration(output: String) -> GlobalConfiguration? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let lower = trimmed.lowercased()
        if lower.contains("no configuration")
            || lower.contains("not configured")
            || lower.contains("no build cache configuration") {
            return nil
        }

        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let isEnabled = (json["enabled"] as? Bool)
                ?? (json["isEnabled"] as? Bool)
                ?? (json["cachingEnabled"] as? Bool)
                ?? (json["enableCaching"] as? Bool)
            let rawPath = (json["path"] as? String)
                ?? (json["cachePath"] as? String)
                ?? (json["buildCachePath"] as? String)
            let normalizedPath = rawPath.flatMap(normalizeParsedPath)
            let sizeLimit = (json["sizeLimit"] as? String)
                ?? (json["maxSize"] as? String)
            if isEnabled != nil || normalizedPath != nil || sizeLimit != nil {
                return GlobalConfiguration(
                    isEnabled: isEnabled,
                    path: normalizedPath,
                    sizeLimit: sizeLimit
                )
            }
            return nil
        }

        var isEnabled: Bool?
        var path: String?
        var sizeLimit: String?

        for rawLine in trimmed.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard let separatorIndex = line.firstIndex(where: { $0 == ":" || $0 == "=" }) else {
                continue
            }
            let key = line[..<separatorIndex]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let rawValue = String(line[line.index(after: separatorIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawValue.isEmpty else { continue }

            if key.contains("path") {
                if let normalized = normalizeParsedPath(rawValue) {
                    path = normalized
                }
            } else if key.contains("enable") || key.contains("caching") {
                switch rawValue.lowercased() {
                case "true", "yes", "1", "enabled":
                    isEnabled = true
                case "false", "no", "0", "disabled":
                    isEnabled = false
                default:
                    break
                }
            } else if key.contains("limit") || key.contains("size") {
                if !isSentinelNone(rawValue) {
                    sizeLimit = rawValue
                }
            }
        }

        guard isEnabled != nil || path != nil || sizeLimit != nil else {
            return nil
        }
        return GlobalConfiguration(isEnabled: isEnabled, path: path, sizeLimit: sizeLimit)
    }

    /// Returns `true` when two filesystem paths point to the same directory (accounting for `~` and symlinks).
    public static func pathsMatch(_ lhs: String, _ rhs: String) -> Bool {
        let leftExpanded = (lhs as NSString).expandingTildeInPath
        let rightExpanded = (rhs as NSString).expandingTildeInPath
        let leftURL = URL(fileURLWithPath: leftExpanded).standardizedFileURL
        let rightURL = URL(fileURLWithPath: rightExpanded).standardizedFileURL
        if leftURL.path == rightURL.path {
            return true
        }
        return leftURL.resolvingSymlinksInPath().path == rightURL.resolvingSymlinksInPath().path
    }

    private static func normalizeParsedPath(_ raw: String) -> String? {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("\""), cleaned.hasSuffix("\""), cleaned.count >= 2 {
            cleaned = String(cleaned.dropFirst().dropLast())
        }
        guard !cleaned.isEmpty, !isSentinelNone(cleaned) else {
            return nil
        }
        let expanded = (cleaned as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    private static func isSentinelNone(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower == "none" || lower == "nil" || lower == "null" || lower == "(not set)" || lower == "default"
    }
}

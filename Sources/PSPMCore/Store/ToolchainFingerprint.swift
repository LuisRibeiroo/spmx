import CryptoKit
import Foundation

/// Output captured from running a toolchain inspection command.
public struct CommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Errors thrown while resolving the active Swift/Xcode toolchain fingerprint.
public enum ToolchainFingerprintError: Error, LocalizedError, Equatable, Sendable {
    case swiftVersionUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .swiftVersionUnavailable(let details):
            return "Unable to determine active Swift version: \(details)"
        }
    }
}

/// Captures the active Swift and Xcode versions along with a deterministic SHA-256 short hash
/// used to partition ABI/module-sensitive `prebuilts/` entries in the global store.
public struct ToolchainFingerprint: Codable, Equatable, Hashable, Sendable {
    public typealias CommandRunner = @Sendable (_ executable: String, _ arguments: [String]) throws -> CommandResult

    public let swiftVersion: String
    public let xcodeVersion: String?
    public let hash: String

    public init(swiftVersion: String, xcodeVersion: String?, hash: String? = nil) {
        let normalizedSwift = Self.normalizeOutput(swiftVersion)
        let normalizedXcode = xcodeVersion.map(Self.normalizeOutput).flatMap { $0.isEmpty ? nil : $0 }
        self.swiftVersion = normalizedSwift
        self.xcodeVersion = normalizedXcode
        self.hash = hash ?? Self.computeHash(swiftVersion: normalizedSwift, xcodeVersion: normalizedXcode)
    }

    /// Resolves the active toolchain fingerprint by invoking `swift --version` and `xcodebuild -version`.
    public static func current(runner: CommandRunner = defaultCommandRunner) throws -> ToolchainFingerprint {
        let swiftResult: CommandResult
        do {
            swiftResult = try runner("swift", ["--version"])
        } catch {
            throw ToolchainFingerprintError.swiftVersionUnavailable(error.localizedDescription)
        }

        let swiftOutput = normalizeOutput(swiftResult.stdout)
        guard swiftResult.exitCode == 0, !swiftOutput.isEmpty else {
            let err = normalizeOutput(swiftResult.stderr)
            let reason = err.isEmpty ? "exit code \(swiftResult.exitCode)" : err
            throw ToolchainFingerprintError.swiftVersionUnavailable(reason)
        }

        var xcodeOutput: String?
        if let xcodeResult = try? runner("xcodebuild", ["-version"]), xcodeResult.exitCode == 0 {
            let trimmed = normalizeOutput(xcodeResult.stdout)
            if !trimmed.isEmpty {
                xcodeOutput = trimmed
            }
        }

        return ToolchainFingerprint(swiftVersion: swiftOutput, xcodeVersion: xcodeOutput)
    }

    /// Computes a deterministic lowercase SHA-256 short hash from normalized Swift and Xcode versions.
    public static func computeHash(
        swiftVersion: String,
        xcodeVersion: String?,
        length: Int = 16
    ) -> String {
        let normalizedSwift = normalizeOutput(swiftVersion)
        let normalizedXcode = xcodeVersion.map(normalizeOutput) ?? ""
        let payload = "swift:\(normalizedSwift)\nxcode:\(normalizedXcode)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(max(1, length)))
    }

    /// Default command runner executing tools via `Foundation.Process`.
    public static let defaultCommandRunner: CommandRunner = { executable, arguments in
        let process = Process()
        if executable.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments
        }

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

    private static func normalizeOutput(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

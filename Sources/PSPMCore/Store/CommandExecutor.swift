import Darwin
import Foundation

/// Errors thrown by ``CommandExecutor`` when launching or waiting on an external command.
public enum CommandExecutionError: Error, LocalizedError, Equatable, Sendable {
    case launchFailed(executable: String, message: String)
    case timedOut(executable: String, arguments: [String], timeout: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let executable, let message):
            return "Failed to launch '\(executable)': \(message)"
        case .timedOut(let executable, let arguments, let timeout):
            let formatted = timeout.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(timeout))s"
                : String(format: "%.1fs", timeout)
            let cmd = ([URL(fileURLWithPath: executable).lastPathComponent] + arguments).joined(separator: " ")
            return "Command timed out after \(formatted) of inactivity: \(cmd)"
        }
    }
}

/// Captured output and exit status from an external command execution.
public struct CommandExecutionResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Thread-safe inactivity watchdog that fires `onTimeout` if not reset or cancelled before `timeout`.
///
/// Calling ``reset()`` pushes the deadline forward from the current time (restoring the full timeout
/// window whenever progress or output occurs). Calling ``cancel()`` disarms the watchdog completely.
public final class ExecutionWatchdog: @unchecked Sendable {
    private let timeout: TimeInterval
    private let queue: DispatchQueue
    private let lock = NSLock()
    private let onTimeout: @Sendable () -> Void

    private var timer: DispatchSourceTimer?
    private var deadline: Date
    private var isCancelled = false
    private var didFire = false

    public init(timeout: TimeInterval, onTimeout: @escaping @Sendable () -> Void) {
        let safeTimeout = max(0.001, timeout)
        self.timeout = safeTimeout
        self.onTimeout = onTimeout
        self.queue = DispatchQueue(label: "pspm.execution.watchdog.\(UUID().uuidString)")
        self.deadline = Date().addingTimeInterval(safeTimeout)

        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(
            deadline: .now() + safeTimeout,
            repeating: .never,
            leeway: .milliseconds(25)
        )
        source.setEventHandler { [weak self] in
            self?.handleTimerFired()
        }
        self.timer = source
        source.resume()
    }

    /// Restores the timeout countdown to a full `timeout` interval starting now.
    public func reset() {
        lock.lock()
        guard !isCancelled, !didFire, let timer else {
            lock.unlock()
            return
        }
        deadline = Date().addingTimeInterval(timeout)
        timer.schedule(
            deadline: .now() + timeout,
            repeating: .never,
            leeway: .milliseconds(25)
        )
        lock.unlock()
    }

    /// Cancels and disarms the watchdog cleanly.
    public func cancel() {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        isCancelled = true
        let source = timer
        timer = nil
        lock.unlock()
        source?.cancel()
    }

    private func handleTimerFired() {
        lock.lock()
        guard !isCancelled, !didFire else {
            lock.unlock()
            return
        }

        let remaining = deadline.timeIntervalSinceNow
        if remaining > 0.001 {
            timer?.schedule(
                deadline: .now() + remaining,
                repeating: .never,
                leeway: .milliseconds(25)
            )
            lock.unlock()
            return
        }

        didFire = true
        let source = timer
        timer = nil
        lock.unlock()
        source?.cancel()
        onTimeout()
    }

    deinit {
        cancel()
    }
}

/// Executes external processes with concurrent pipe reading, non-interactive `stdin`,
/// and a per-execution timeout that resets whenever the command produces output or returns.
public struct CommandExecutor: Sendable {
    public static let timeoutEnvironmentKey = "PSPM_EXECUTION_TIMEOUT"
    public static let defaultTimeout: TimeInterval = 30.0

    public static func resolveDefaultTimeout(
        override: TimeInterval? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TimeInterval? {
        if let override {
            return override > 0 ? override : nil
        }
        if let raw = environment[timeoutEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let parsed = Double(raw) {
            return parsed > 0 ? parsed : nil
        }
        return defaultTimeout
    }

    public static func run(
        executablePath: String,
        arguments: [String],
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval? = resolveDefaultTimeout(),
        resetTimeoutOnOutput: Bool = true,
        onOutputActivity: (@Sendable () -> Void)? = nil
    ) throws -> CommandExecutionResult {
        let process = Process()
        if executablePath.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executablePath] + arguments
        }
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        if let environment {
            process.environment = environment
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let timedOutState = TimedOutFlag()
        let group = DispatchGroup()
        let stdoutBuffer = PipeBuffer()
        let stderrBuffer = PipeBuffer()

        let effectiveTimeout = (timeout ?? 0) > 0 ? timeout : nil
        var watchdog: ExecutionWatchdog?
        if let effectiveTimeout {
            watchdog = ExecutionWatchdog(timeout: effectiveTimeout) {
                timedOutState.markTimedOut()
                terminateProcessSafely(process)
            }
        }

        let activeWatchdog = watchdog
        let activityCallback: @Sendable () -> Void = {
            if resetTimeoutOnOutput {
                activeWatchdog?.reset()
            }
            onOutputActivity?()
        }

        group.enter()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                if stdoutBuffer.markEOFIfNeeded() {
                    group.leave()
                }
            } else {
                stdoutBuffer.append(chunk)
                activityCallback()
            }
        }

        group.enter()
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                if stderrBuffer.markEOFIfNeeded() {
                    group.leave()
                }
            } else {
                stderrBuffer.append(chunk)
                activityCallback()
            }
        }

        do {
            try process.run()
        } catch {
            watchdog?.cancel()
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            if stdoutBuffer.markEOFIfNeeded() { group.leave() }
            if stderrBuffer.markEOFIfNeeded() { group.leave() }
            throw CommandExecutionError.launchFailed(executable: executablePath, message: error.localizedDescription)
        }

        process.waitUntilExit()
        watchdog?.cancel()

        if timedOutState.isTimedOut, let effectiveTimeout {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            if stdoutBuffer.markEOFIfNeeded() { group.leave() }
            if stderrBuffer.markEOFIfNeeded() { group.leave() }
            throw CommandExecutionError.timedOut(
                executable: executablePath,
                arguments: arguments,
                timeout: effectiveTimeout
            )
        }

        _ = group.wait(timeout: .now() + .seconds(2))
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        if stdoutBuffer.markEOFIfNeeded() { group.leave() }
        if stderrBuffer.markEOFIfNeeded() { group.leave() }

        let stdout = String(data: stdoutBuffer.snapshot(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrBuffer.snapshot(), encoding: .utf8) ?? ""
        return CommandExecutionResult(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
    }

    private static func terminateProcessSafely(_ process: Process) {
        let pid = process.processIdentifier
        if process.isRunning {
            process.terminate()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25) {
            if pid > 0 && process.isRunning {
                _ = Darwin.kill(pid, SIGKILL)
            }
        }
    }
}

private final class TimedOutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flagged = false

    func markTimedOut() {
        lock.lock()
        flagged = true
        lock.unlock()
    }

    var isTimedOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flagged
    }
}

private final class PipeBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var eofSignaled = false

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func markEOFIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if eofSignaled {
            return false
        }
        eofSignaled = true
        return true
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

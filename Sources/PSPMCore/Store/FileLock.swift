import Darwin
import Foundation

@_silgen_name("flock")
private func posixFlock(_ fd: Int32, _ operation: Int32) -> Int32

/// Errors thrown by ``FileLock`` when acquiring a POSIX advisory lock.
public enum FileLockError: Error, LocalizedError, Equatable, Sendable {
    case openFailed(path: String, errno: Int32, message: String)
    case timeout(path: String, timeout: TimeInterval)
    case lockFailed(path: String, errno: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let path, let code, let message):
            return "Failed to open lock file '\(path)' (errno \(code): \(message))."
        case .timeout(let path, let timeout):
            return "Timed out after \(String(format: "%.2f", timeout))s waiting for lock '\(path)'."
        case .lockFailed(let path, let code, let message):
            return "Failed to acquire flock on '\(path)' (errno \(code): \(message))."
        }
    }
}

/// Per-resource POSIX `flock(2)` wrapper with non-blocking retry loop (`LOCK_EX | LOCK_NB`)
/// and configurable timeout.
public struct FileLock: Sendable {
    /// RAII lock guard that releases the `flock` and closes the file descriptor on `deinit`.
    public final class Guard {
        private var fileDescriptor: Int32

        fileprivate init(fileDescriptor: Int32) {
            self.fileDescriptor = fileDescriptor
        }

        /// Explicitly releases the lock and closes the underlying file descriptor.
        public func release() {
            guard fileDescriptor >= 0 else { return }
            let fd = fileDescriptor
            fileDescriptor = -1
            _ = posixFlock(fd, LOCK_UN)
            _ = Darwin.close(fd)
        }

        deinit {
            release()
        }
    }

    public let lockFileURL: URL
    public let timeout: TimeInterval
    public let pollInterval: TimeInterval

    public init(
        lockFileURL: URL,
        timeout: TimeInterval = 30.0,
        pollInterval: TimeInterval = 0.02
    ) {
        self.lockFileURL = lockFileURL.standardizedFileURL
        self.timeout = max(0, timeout)
        self.pollInterval = max(0.001, pollInterval)
    }

    /// Acquires the exclusive lock synchronously and returns an RAII ``Guard`` that unlocks on scope exit.
    public func acquire() throws -> Guard {
        let fd = try acquireFileDescriptorSync()
        return Guard(fileDescriptor: fd)
    }

    /// Executes `body` while holding the exclusive lock synchronously, releasing it on scope exit.
    public func withLock<T>(_ body: () throws -> T) throws -> T {
        let fd = try acquireFileDescriptorSync()
        defer {
            _ = posixFlock(fd, LOCK_UN)
            _ = Darwin.close(fd)
        }
        return try body()
    }

    /// Executes `body` while holding the exclusive lock asynchronously, yielding while waiting for contention.
    public func withLock<T>(_ body: () async throws -> T) async throws -> T {
        let fd = try await acquireFileDescriptorAsync()
        defer {
            _ = posixFlock(fd, LOCK_UN)
            _ = Darwin.close(fd)
        }
        return try await body()
    }

    /// Convenience helper to execute a synchronous critical section under a lock at `lockFileURL`.
    public static func withLock<T>(
        at lockFileURL: URL,
        timeout: TimeInterval = 30.0,
        pollInterval: TimeInterval = 0.02,
        _ body: () throws -> T
    ) throws -> T {
        try FileLock(lockFileURL: lockFileURL, timeout: timeout, pollInterval: pollInterval).withLock(body)
    }

    /// Convenience helper to execute an asynchronous critical section under a lock at `lockFileURL`.
    public static func withLock<T>(
        at lockFileURL: URL,
        timeout: TimeInterval = 30.0,
        pollInterval: TimeInterval = 0.02,
        _ body: () async throws -> T
    ) async throws -> T {
        try await FileLock(lockFileURL: lockFileURL, timeout: timeout, pollInterval: pollInterval).withLock(body)
    }

    // MARK: - Private Helpers

    private func openLockFile() throws -> Int32 {
        let parentDirectory = lockFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        let fd = Darwin.open(lockFileURL.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        if fd < 0 {
            let code = Darwin.errno
            throw FileLockError.openFailed(
                path: lockFileURL.path,
                errno: code,
                message: String(cString: Darwin.strerror(code))
            )
        }
        return fd
    }

    private enum FlockAttemptOutcome {
        case acquired
        case retryImmediately
        case wait(seconds: TimeInterval)
    }

    private func evaluateFlockAttempt(
        fd: Int32,
        clock: ContinuousClock,
        deadline: ContinuousClock.Instant
    ) throws -> FlockAttemptOutcome {
        if posixFlock(fd, LOCK_EX | LOCK_NB) == 0 {
            return .acquired
        }

        let code = Darwin.errno
        if code == EINTR {
            return .retryImmediately
        }

        if code == EWOULDBLOCK || code == EAGAIN {
            let now = clock.now
            if now >= deadline {
                _ = Darwin.close(fd)
                throw FileLockError.timeout(path: lockFileURL.path, timeout: timeout)
            }

            let remaining = now.duration(to: deadline)
            let remainingSeconds = Double(remaining.components.seconds)
                + Double(remaining.components.attoseconds) / 1_000_000_000_000_000_000.0
            return .wait(seconds: min(pollInterval, max(0.001, remainingSeconds)))
        }

        _ = Darwin.close(fd)
        throw FileLockError.lockFailed(
            path: lockFileURL.path,
            errno: code,
            message: String(cString: Darwin.strerror(code))
        )
    }

    private func acquireFileDescriptorSync() throws -> Int32 {
        let fd = try openLockFile()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))

        while true {
            switch try evaluateFlockAttempt(fd: fd, clock: clock, deadline: deadline) {
            case .acquired:
                return fd
            case .retryImmediately:
                continue
            case .wait(let sleepSeconds):
                Thread.sleep(forTimeInterval: sleepSeconds)
            }
        }
    }

    private func acquireFileDescriptorAsync() async throws -> Int32 {
        let fd = try openLockFile()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))

        while true {
            switch try evaluateFlockAttempt(fd: fd, clock: clock, deadline: deadline) {
            case .acquired:
                return fd
            case .retryImmediately:
                continue
            case .wait(let sleepSeconds):
                do {
                    try await Task.sleep(for: .seconds(sleepSeconds))
                } catch {
                    _ = Darwin.close(fd)
                    throw error
                }
            }
        }
    }
}

import Foundation
import Testing
@testable import PSPMCore

@Suite("CommandExecutor & ExecutionWatchdog")
struct CommandExecutorTests {
    @Test("times out and terminates a hung command that produces no output")
    func timesOutHungSilentCommand() throws {
        do {
            _ = try CommandExecutor.run(
                executablePath: "/bin/sh",
                arguments: ["-c", "sleep 5"],
                timeout: 0.2
            )
            Issue.record("Expected CommandExecutionError.timedOut")
        } catch let error as CommandExecutionError {
            guard case .timedOut(let executable, _, let timeout) = error else {
                Issue.record("Unexpected CommandExecutionError case: \(error)")
                return
            }
            #expect(executable == "/bin/sh")
            #expect(timeout == 0.2)
        }
    }

    @Test("resets timeout while command keeps emitting output and restores full budget between runs")
    func resetsTimeoutOnOutputAndRestoresBetweenCommands() throws {
        let activityCounter = ActivityCounter()
        // Total runtime (~1.0s) exceeds the 0.6s timeout, but each output chunk (~0.25s apart) resets the watchdog.
        let result = try CommandExecutor.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "echo tick1; sleep 0.25; echo tick2; sleep 0.25; echo tick3; sleep 0.25; echo tick4; sleep 0.25; echo done"],
            timeout: 0.6,
            resetTimeoutOnOutput: true,
            onOutputActivity: { activityCounter.increment() }
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("done"))
        #expect(activityCounter.count >= 2)

        // Sequential invocations do not share elapsed time; returning restores full timeout for the next command (~0.7s total > 0.55s).
        let first = try CommandExecutor.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "sleep 0.35; echo first"],
            timeout: 0.55
        )
        let second = try CommandExecutor.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "sleep 0.35; echo second"],
            timeout: 0.55
        )
        #expect(first.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "first")
        #expect(second.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "second")
    }

    @Test("resolveDefaultTimeout honors override and environment variable")
    func resolvesTimeoutConfiguration() {
        #expect(CommandExecutor.resolveDefaultTimeout(override: 0, environment: [:]) == nil)
        #expect(CommandExecutor.resolveDefaultTimeout(override: 45, environment: [:]) == 45)
        #expect(CommandExecutor.resolveDefaultTimeout(override: nil, environment: [CommandExecutor.timeoutEnvironmentKey: "12.5"]) == 12.5)
        #expect(CommandExecutor.resolveDefaultTimeout(override: nil, environment: [CommandExecutor.timeoutEnvironmentKey: "0"]) == nil)
        #expect(CommandExecutor.resolveDefaultTimeout(override: nil, environment: [:]) == CommandExecutor.defaultTimeout)
    }
}

private final class ActivityCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

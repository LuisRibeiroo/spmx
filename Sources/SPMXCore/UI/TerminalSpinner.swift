import Darwin
import Foundation

/// Animated terminal progress indicator for background or long-running CLI tasks.
///
/// When ANSI/TTY styling is enabled, redraws a single status line (`\r\u{1B}[2K`) with an
/// animated Braille spinner and elapsed duration counter so active work never appears frozen.
/// Automatically truncates long paths to fit the terminal width and pauses cleanly around permanent
/// log output.
public final class TerminalSpinner: @unchecked Sendable {
    public static let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    private let style: TerminalStyle
    private let interval: TimeInterval
    private let maxColumnsProvider: @Sendable () -> Int
    private let writer: @Sendable (String) -> Void
    private let queue = DispatchQueue(label: "spmx.terminal.spinner")
    private let lock = NSLock()

    private var timer: DispatchSourceTimer?
    private var isRunning = false
    private var isSuspended = false
    private var hasDrawnLiveLine = false
    private var frameIndex = 0
    private var message = ""
    private var detail: String?
    private var stepStartedAt = Date()

    public init(
        style: TerminalStyle = .stdout,
        interval: TimeInterval = 0.09,
        maxColumnsProvider: @escaping @Sendable () -> Int = { TerminalSpinner.terminalColumns() },
        writer: (@Sendable (String) -> Void)? = nil
    ) {
        self.style = style
        self.interval = max(0.03, interval)
        self.maxColumnsProvider = maxColumnsProvider
        self.writer = writer ?? { chunk in
            fputs(chunk, Darwin.stdout)
            fflush(Darwin.stdout)
        }
    }

    public func start(message: String, detail: String? = nil) {
        lock.lock()
        self.message = message
        self.detail = detail
        self.stepStartedAt = Date()
        self.frameIndex = 0
        let shouldAnimate = style.isEnabled
        if shouldAnimate && !isRunning {
            isRunning = true
            isSuspended = false
            startTimerLocked()
        } else {
            isRunning = true
            isSuspended = false
        }
        let plainLine: String? = shouldAnimate ? nil : "  \(style.runningIcon) \(message)"
        lock.unlock()

        if shouldAnimate {
            renderNow()
        } else if let plainLine {
            writer("\(plainLine)\n")
        }
    }

    public func update(message: String? = nil, detail: String? = nil) {
        lock.lock()
        if let message, message != self.message {
            self.message = message
            self.stepStartedAt = Date()
        }
        self.detail = detail
        self.isSuspended = false
        let shouldAnimate = style.isEnabled
        let shouldStart = !isRunning
        if shouldStart {
            isRunning = true
            self.stepStartedAt = Date()
            if shouldAnimate {
                startTimerLocked()
            }
        }
        let currentMsg = self.message
        lock.unlock()

        if shouldAnimate {
            renderNow()
        } else if shouldStart {
            writer("  \(style.runningIcon) \(currentMsg)\n")
        }
    }

    public func suspendForOutput(_ block: () -> Void) {
        clearLiveLineIfNeeded(suspend: true)
        block()
        resumeAfterOutput()
    }

    /// Clears the active live spinner line, executes `block`, and keeps the spinner paused
    /// until the next ``update(message:detail:)`` or ``start(message:detail:)`` call.
    public func finishItem(_ block: () -> Void) {
        clearLiveLineIfNeeded(suspend: true)
        block()
    }

    public func stop(clearLine: Bool = true) {
        lock.lock()
        let source = timer
        timer = nil
        isRunning = false
        isSuspended = false
        let needsClear = clearLine && style.isEnabled && hasDrawnLiveLine
        hasDrawnLiveLine = false
        lock.unlock()

        source?.cancel()
        if needsClear {
            writer("\r\u{1B}[2K")
        }
    }

    deinit {
        stop(clearLine: false)
    }

    // MARK: - Terminal Sizing & Formatting Helpers

    public static func terminalColumns(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Int {
        var ws = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0 {
            return Int(ws.ws_col)
        }
        if let envCols = environment["COLUMNS"],
           let parsed = Int(envCols),
           parsed > 0 {
            return parsed
        }
        return 80
    }

    public static func middleTruncate(_ value: String, maxLength: Int) -> String {
        guard value.count > maxLength, maxLength > 5 else {
            return value
        }
        let keep = maxLength - 3
        let headCount = keep / 2
        let tailCount = keep - headCount
        return "\(value.prefix(headCount))...\(value.suffix(tailCount))"
    }

    // MARK: - Internal Rendering

    private func startTimerLocked() {
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(15)
        )
        source.setEventHandler { [weak self] in
            self?.tick()
        }
        timer = source
        source.resume()
    }

    private func tick() {
        lock.lock()
        guard isRunning, !isSuspended, style.isEnabled else {
            lock.unlock()
            return
        }
        frameIndex = (frameIndex + 1) % Self.frames.count
        lock.unlock()
        renderNow()
    }

    private func renderNow() {
        lock.lock()
        guard isRunning, !isSuspended, style.isEnabled else {
            lock.unlock()
            return
        }
        let frame = Self.frames[frameIndex]
        let msg = message
        let det = detail
        let elapsedSeconds = Int(Date().timeIntervalSince(stepStartedAt))
        hasDrawnLiveLine = true
        lock.unlock()

        let columns = max(24, maxColumnsProvider())
        let elapsedSuffix = elapsedSeconds >= 1 ? " · \(elapsedSeconds)s" : ""
        let stepBody = (det?.isEmpty == false) ? det! : msg
        let hasSeparateTarget = (det?.isEmpty == false) && !msg.isEmpty

        // Reserve space for "  ⠋ " (4 chars) plus a 2-char right-edge margin to prevent deferred wrap.
        let availableTotal = max(18, columns - 6)
        let separator = " · "
        let renderedContent: String

        if !hasSeparateTarget {
            let maxStep = max(8, availableTotal - elapsedSuffix.count)
            let truncatedStep = Self.middleTruncate(stepBody, maxLength: maxStep)
            let visibleStep = truncatedStep
            let visibleElapsed = elapsedSuffix
            renderedContent = visibleStep + (visibleElapsed.isEmpty ? "" : style.gray(visibleElapsed))
        } else {
            let fullStepWithElapsed = stepBody + elapsedSuffix
            let fullLength = msg.count + separator.count + fullStepWithElapsed.count

            if fullLength <= availableTotal {
                renderedContent = "\(msg)\(style.gray("\(separator)\(fullStepWithElapsed)"))"
            } else {
                // Prioritize keeping the step/message fully visible; shrink the target prefix first.
                let minTargetBudget = min(msg.count, max(10, availableTotal / 4))
                if minTargetBudget + separator.count + fullStepWithElapsed.count <= availableTotal {
                    let targetBudget = availableTotal - separator.count - fullStepWithElapsed.count
                    let truncatedTarget = Self.middleTruncate(msg, maxLength: targetBudget)
                    renderedContent = "\(truncatedTarget)\(style.gray("\(separator)\(fullStepWithElapsed)"))"
                } else {
                    // Extremely narrow terminal: keep elapsed visible and devote ~75% of remaining space to step.
                    let contentWithoutElapsed = max(12, availableTotal - elapsedSuffix.count)
                    let targetBudget = min(msg.count, max(6, contentWithoutElapsed / 4))
                    let stepBudget = max(8, contentWithoutElapsed - targetBudget - separator.count)
                    let truncatedTarget = Self.middleTruncate(msg, maxLength: targetBudget)
                    let truncatedStep = Self.middleTruncate(stepBody, maxLength: stepBudget)
                    renderedContent = "\(truncatedTarget)\(style.gray("\(separator)\(truncatedStep)\(elapsedSuffix)"))"
                }
            }
        }

        let icon = style.primaryBold(frame)
        // Disable auto-wrap (DECAWM) for the single status row so resizing panes never stack wrapped frames.
        writer("\r\u{1B}[2K\u{1B}[?7l  \(icon) \(renderedContent)\u{1B}[?7h")
    }

    private func clearLiveLineIfNeeded(suspend: Bool) {
        lock.lock()
        if suspend {
            isSuspended = true
        }
        let needsClear = style.isEnabled && hasDrawnLiveLine
        hasDrawnLiveLine = false
        lock.unlock()

        if needsClear {
            writer("\r\u{1B}[2K")
        }
    }

    private func resumeAfterOutput() {
        lock.lock()
        let active = isRunning
        isSuspended = false
        lock.unlock()

        if active && style.isEnabled {
            renderNow()
        }
    }
}

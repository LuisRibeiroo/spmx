import Foundation
import Testing
@testable import SPMXCore

@Suite("TerminalStyle")
struct TerminalStyleTests {
    @Test("environment overrides and TTY detection")
    func colorDetection() {
        #expect(TerminalStyle.shouldEnableColor(isTTY: true, environment: [:]) == true)
        #expect(TerminalStyle.shouldEnableColor(isTTY: false, environment: [:]) == false)

        // NO_COLOR disables even on TTY or FORCE_COLOR
        #expect(TerminalStyle.shouldEnableColor(isTTY: true, environment: ["NO_COLOR": "1"]) == false)
        #expect(TerminalStyle.shouldEnableColor(isTTY: true, environment: ["NO_COLOR": "1", "FORCE_COLOR": "1"]) == false)

        // CLICOLOR=0 and TERM=dumb disable colors
        #expect(TerminalStyle.shouldEnableColor(isTTY: true, environment: ["CLICOLOR": "0"]) == false)
        #expect(TerminalStyle.shouldEnableColor(isTTY: true, environment: ["TERM": "dumb"]) == false)

        // FORCE_COLOR / CLICOLOR_FORCE enable on non-TTY
        #expect(TerminalStyle.shouldEnableColor(isTTY: false, environment: ["FORCE_COLOR": "1"]) == true)
        #expect(TerminalStyle.shouldEnableColor(isTTY: false, environment: ["FORCE_COLOR": "0"]) == false)
        #expect(TerminalStyle.shouldEnableColor(isTTY: false, environment: ["CLICOLOR_FORCE": "1"]) == true)
    }

    @Test("plain style strips all ANSI sequences")
    func plainStyle() {
        let style = TerminalStyle.plain
        #expect(style.bold("hello") == "hello")
        #expect(style.italic("world") == "world")
        #expect(style.tip("note") == "note")
        #expect(style.tipItalic("hint") == "hint")
        #expect(style.stepRunning("Running...") == "  ▸ Running...")
        #expect(style.stepSuccess("Done", detail: "ok") == "  ✓ Done ok")
        #expect(style.stepSkipped("Skipped", detail: "reason") == "  • Skipped reason")
        #expect(style.stepWarning("Warn", detail: "check") == "  ! Warn check")
        #expect(style.stepError("Err", detail: "failed") == "  ✗ Err failed")
    }

    @Test("ansi style emits bold, italic, color, and gray tip codes")
    func ansiStyle() {
        let style = TerminalStyle.ansi
        #expect(style.bold("title") == "\u{1B}[1mtitle\u{1B}[0m")
        #expect(style.italic("sub") == "\u{1B}[3msub\u{1B}[0m")
        #expect(style.dim("muted") == "\u{1B}[2mmuted\u{1B}[0m")
        #expect(style.green("ok") == "\u{1B}[32mok\u{1B}[0m")
        #expect(style.cyan("path") == "\u{1B}[36mpath\u{1B}[0m")

        // Tips use gray tones (90)
        #expect(style.tip("hint") == "\u{1B}[90mhint\u{1B}[0m")
        #expect(style.tipItalic("detail") == "\u{1B}[90;3mdetail\u{1B}[0m")
        #expect(style.tipCommand("spmx status") == "\u{1B}[90;1mspmx status\u{1B}[0m")

        // Step lines contain status icons and SGR escapes
        let running = style.stepRunning("Creating shims...")
        #expect(running.contains("▸"))
        #expect(running.contains("\u{1B}[38;2;234;106;56m"))

        // Primary brand orange (#EA6A38) in TrueColor and 256-color fallback
        #expect(style.primary("spmx") == "\u{1B}[38;2;234;106;56mspmx\u{1B}[0m")
        #expect(style.heading("spmx migrate") == "\u{1B}[1;38;2;234;106;56mspmx migrate\u{1B}[0m")
        let style256 = TerminalStyle(enabled: true, supportsTrueColor: false)
        #expect(style256.primary("spmx") == "\u{1B}[38;5;209mspmx\u{1B}[0m")
        #expect(TerminalStyle.shouldUseTrueColor(environment: ["COLORTERM": "truecolor"]) == true)
        #expect(TerminalStyle.shouldUseTrueColor(environment: ["TERM_PROGRAM": "ghostty"]) == true)
        #expect(TerminalStyle.shouldUseTrueColor(environment: ["TERM_PROGRAM": "Apple_Terminal"]) == false)

        let success = style.stepSuccess("Shims", detail: "swift, xcodebuild")
        #expect(success.contains("✓"))
        #expect(success.contains("\u{1B}[1;32m"))

        let added = style.stepAdded("firebase-ios-sdk", detail: "12.19.3")
        #expect(added.contains("+"))
        #expect(added.contains("\u{1B}[1;32m"))
        #expect(added.contains("\u{1B}[90m12.19.3\u{1B}[0m"))
        #expect(style.doneIn(seconds: 1.4).contains("Done"))
        #expect(style.doneIn(seconds: 1.4).contains("in 1.4s"))

        let inlineTip = style.formatInlineCode("Run `spmx setup` or `spmx hydrate`.", baseCodes: ["90"], codeCodes: ["90", "1"])
        #expect(inlineTip == "\u{1B}[90mRun \u{1B}[0m\u{1B}[90;1m`spmx setup`\u{1B}[0m\u{1B}[90m or \u{1B}[0m\u{1B}[90;1m`spmx hydrate`\u{1B}[0m\u{1B}[90m.\u{1B}[0m")
        #expect(TerminalStyle.plain.formatInlineCode("Run `spmx setup`.") == "Run `spmx setup`.")
    }

    @Test("spinner animates background frames in ANSI mode and stays clean in plain mode")
    func terminalSpinnerBehavior() {
        let buffer = LockedStrings()
        let ansiSpinner = TerminalSpinner(
            style: .ansi,
            interval: 0.03,
            maxColumnsProvider: { 80 },
            writer: { chunk in buffer.append(chunk) }
        )

        ansiSpinner.start(message: "Scanning workspace", detail: "step 1")
        Thread.sleep(forTimeInterval: 0.12)
        ansiSpinner.update(detail: "harvesting 1/5")
        ansiSpinner.suspendForOutput {
            buffer.append("PERMANENT_LINE\n")
        }
        ansiSpinner.stop()

        let ansiOutput = buffer.joined()
        #expect(ansiOutput.contains("\r\u{1B}[2K"))
        #expect(ansiOutput.contains("⠋"))
        #expect(ansiOutput.contains("harvesting 1/5"))
        #expect(ansiOutput.contains("PERMANENT_LINE\n"))
        #expect(ansiOutput.hasSuffix("\r\u{1B}[2K"))

        let plainBuffer = LockedStrings()
        let plainSpinner = TerminalSpinner(
            style: .plain,
            interval: 0.03,
            maxColumnsProvider: { 80 },
            writer: { chunk in plainBuffer.append(chunk) }
        )
        plainSpinner.start(message: "Scanning workspace")
        plainSpinner.update(detail: "harvesting 1/5")
        plainSpinner.stop()

        let plainOutput = plainBuffer.joined()
        #expect(!plainOutput.contains("\u{1B}["))
        #expect(plainOutput.contains("Scanning workspace"))

        let truncated = TerminalSpinner.middleTruncate("/Users/example/very/long/path/to/SourcePackages", maxLength: 20)
        #expect(truncated.count == 20)
        #expect(truncated.contains("..."))

        // Narrow terminal keeps the step message intact while shrinking target prefix and disables auto-wrap
        let narrowBuffer = LockedStrings()
        let narrowSpinner = TerminalSpinner(
            style: .ansi,
            interval: 0.5,
            maxColumnsProvider: { 52 },
            writer: { chunk in narrowBuffer.append(chunk) }
        )
        narrowSpinner.start(
            message: "very/long/subproject/path/vr7x/slide [flutter]",
            detail: "calculating reclaimed space"
        )
        narrowSpinner.stop()
        let narrowOutput = narrowBuffer.joined()
        #expect(narrowOutput.contains("\u{1B}[?7l"))
        #expect(narrowOutput.contains("\u{1B}[?7h"))
        #expect(narrowOutput.contains("calculating reclaimed space"))
    }
}

private final class LockedStrings: @unchecked Sendable {
    private let lock = NSLock()
    private var chunks: [String] = []

    func append(_ value: String) {
        lock.lock()
        chunks.append(value)
        lock.unlock()
    }

    func joined() -> String {
        lock.lock()
        defer { lock.unlock() }
        return chunks.joined()
    }
}

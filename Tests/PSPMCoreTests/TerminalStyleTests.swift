import Foundation
import Testing
@testable import PSPMCore

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
        #expect(style.tipCommand("pspm status") == "\u{1B}[90;1mpspm status\u{1B}[0m")

        // Step lines contain status icons and SGR escapes
        let running = style.stepRunning("Creating shims...")
        #expect(running.contains("▸"))
        #expect(running.contains("\u{1B}["))

        let success = style.stepSuccess("Shims", detail: "swift, xcodebuild")
        #expect(success.contains("✓"))
        #expect(success.contains("\u{1B}[1;32m"))

        let inlineTip = style.formatInlineCode("Run `pspm setup` or `pspm hydrate`.", baseCodes: ["90"], codeCodes: ["90", "1"])
        #expect(inlineTip == "\u{1B}[90mRun \u{1B}[0m\u{1B}[90;1m`pspm setup`\u{1B}[0m\u{1B}[90m or \u{1B}[0m\u{1B}[90;1m`pspm hydrate`\u{1B}[0m\u{1B}[90m.\u{1B}[0m")
        #expect(TerminalStyle.plain.formatInlineCode("Run `pspm setup`.") == "Run `pspm setup`.")
    }
}

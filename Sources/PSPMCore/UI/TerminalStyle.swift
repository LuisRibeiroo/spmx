import Darwin
import Foundation

/// ANSI terminal styling helper that respects TTY detection and `NO_COLOR` / `FORCE_COLOR` conventions.
public struct TerminalStyle: Sendable, Equatable {
    public let isEnabled: Bool

    public init(enabled: Bool) {
        self.isEnabled = enabled
    }

    /// Standard output style based on `STDOUT_FILENO` TTY state and process environment.
    public static var stdout: TerminalStyle {
        let isTTY = isatty(STDOUT_FILENO) != 0
        return TerminalStyle(enabled: shouldEnableColor(isTTY: isTTY, environment: ProcessInfo.processInfo.environment))
    }

    /// Standard error style based on `STDERR_FILENO` TTY state and process environment.
    public static var stderr: TerminalStyle {
        let isTTY = isatty(STDERR_FILENO) != 0
        return TerminalStyle(enabled: shouldEnableColor(isTTY: isTTY, environment: ProcessInfo.processInfo.environment))
    }

    /// Always disables ANSI escape sequences.
    public static let plain = TerminalStyle(enabled: false)

    /// Always emits ANSI escape sequences.
    public static let ansi = TerminalStyle(enabled: true)

    /// Resolves whether ANSI color/formatting should be emitted.
    public static func shouldEnableColor(
        isTTY: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if let noColor = environment["NO_COLOR"], !noColor.isEmpty {
            return false
        }
        if environment["CLICOLOR"] == "0" {
            return false
        }
        if let term = environment["TERM"]?.lowercased(), term == "dumb" {
            return false
        }
        if let forceColor = environment["FORCE_COLOR"], !forceColor.isEmpty, forceColor != "0" {
            return true
        }
        if let cliColorForce = environment["CLICOLOR_FORCE"], !cliColorForce.isEmpty, cliColorForce != "0" {
            return true
        }
        return isTTY
    }

    // MARK: - Low-level SGR Primitives

    public func wrap(_ text: String, codes: [String]) -> String {
        guard isEnabled, !text.isEmpty, !codes.isEmpty else {
            return text
        }
        return "\u{1B}[\(codes.joined(separator: ";"))m\(text)\u{1B}[0m"
    }

    public func bold(_ text: String) -> String { wrap(text, codes: ["1"]) }
    public func dim(_ text: String) -> String { wrap(text, codes: ["2"]) }
    public func italic(_ text: String) -> String { wrap(text, codes: ["3"]) }
    public func underline(_ text: String) -> String { wrap(text, codes: ["4"]) }

    public func red(_ text: String) -> String { wrap(text, codes: ["31"]) }
    public func green(_ text: String) -> String { wrap(text, codes: ["32"]) }
    public func yellow(_ text: String) -> String { wrap(text, codes: ["33"]) }
    public func blue(_ text: String) -> String { wrap(text, codes: ["34"]) }
    public func magenta(_ text: String) -> String { wrap(text, codes: ["35"]) }
    public func cyan(_ text: String) -> String { wrap(text, codes: ["36"]) }
    public func gray(_ text: String) -> String { wrap(text, codes: ["90"]) }
    public func brightGreen(_ text: String) -> String { wrap(text, codes: ["92"]) }
    public func brightCyan(_ text: String) -> String { wrap(text, codes: ["96"]) }

    // MARK: - Semantic Helpers

    public func heading(_ text: String) -> String { wrap(text, codes: ["1", "36"]) }
    public func section(_ text: String) -> String { wrap(text, codes: ["1"]) }
    public func path(_ text: String) -> String { wrap(text, codes: ["36"]) }
    public func command(_ text: String) -> String { wrap(text, codes: ["1", "36"]) }
    public func emphasis(_ text: String) -> String { wrap(text, codes: ["1", "3"]) }

    public func successText(_ text: String) -> String { wrap(text, codes: ["1", "32"]) }
    public func runningText(_ text: String) -> String { wrap(text, codes: ["1", "36"]) }
    public func warningText(_ text: String) -> String { wrap(text, codes: ["1", "33"]) }
    public func errorText(_ text: String) -> String { wrap(text, codes: ["1", "31"]) }

    /// Muted gray tones for tips and secondary guidance so they remain low-focus.
    public func tip(_ text: String) -> String { wrap(text, codes: ["90"]) }
    public func tipItalic(_ text: String) -> String { wrap(text, codes: ["90", "3"]) }
    public func tipCommand(_ text: String) -> String { wrap(text, codes: ["90", "1"]) }

    /// Styles backtick-delimited inline code segments (e.g., `` `pspm setup` ``) while preserving the backticks.
    public func formatInlineCode(
        _ text: String,
        baseCodes: [String] = [],
        codeCodes: [String] = ["36"]
    ) -> String {
        guard isEnabled, text.contains("`") else {
            return wrap(text, codes: baseCodes)
        }

        var output = ""
        var index = text.startIndex
        while index < text.endIndex {
            if let openTick = text[index...].firstIndex(of: "`") {
                let afterOpen = text.index(after: openTick)
                if afterOpen < text.endIndex, let closeTick = text[afterOpen...].firstIndex(of: "`") {
                    let prefix = String(text[index..<openTick])
                    if !prefix.isEmpty {
                        output += wrap(prefix, codes: baseCodes)
                    }
                    let codeEnd = text.index(after: closeTick)
                    let codeToken = String(text[openTick..<codeEnd])
                    output += wrap(codeToken, codes: codeCodes)
                    index = codeEnd
                    continue
                }
            }
            let remainder = String(text[index..<text.endIndex])
            output += wrap(remainder, codes: baseCodes)
            break
        }
        return output
    }

    // MARK: - Status Icons & Step Lines

    public var runningIcon: String { wrap("▸", codes: ["1", "36"]) }
    public var successIcon: String { wrap("✓", codes: ["1", "32"]) }
    public var warningIcon: String { wrap("!", codes: ["1", "33"]) }
    public var errorIcon: String { wrap("✗", codes: ["1", "31"]) }
    public var skippedIcon: String { wrap("•", codes: ["90"]) }
    public var infoIcon: String { wrap("›", codes: ["36"]) }

    public func stepRunning(_ label: String) -> String {
        "  \(runningIcon) \(cyan(label))"
    }

    public func stepSuccess(_ title: String, detail: String? = nil) -> String {
        if let detail, !detail.isEmpty {
            return "  \(successIcon) \(bold(title)) \(detail)"
        }
        return "  \(successIcon) \(bold(title))"
    }

    public func stepSkipped(_ title: String, detail: String? = nil) -> String {
        if let detail, !detail.isEmpty {
            return "  \(skippedIcon) \(yellow(title)) \(tip(detail))"
        }
        return "  \(skippedIcon) \(yellow(title))"
    }

    public func stepWarning(_ title: String, detail: String? = nil) -> String {
        if let detail, !detail.isEmpty {
            return "  \(warningIcon) \(warningText(title)) \(detail)"
        }
        return "  \(warningIcon) \(warningText(title))"
    }

    public func stepError(_ title: String, detail: String? = nil) -> String {
        if let detail, !detail.isEmpty {
            return "  \(errorIcon) \(errorText(title)) \(detail)"
        }
        return "  \(errorIcon) \(errorText(title))"
    }
}

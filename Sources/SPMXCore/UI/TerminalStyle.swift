import Darwin
import Foundation

/// ANSI terminal styling helper inspired by pnpm's clean block layout, using spmx's icon orange (`#EA6A38`)
/// as the primary brand color, while respecting TTY detection and `NO_COLOR` / `FORCE_COLOR` conventions.
public struct TerminalStyle: Sendable, Equatable {
    /// Brand primary orange extracted from `assets/icon.svg` (`#EA6A38` / `rgb(234, 106, 56)`).
    public static let iconOrangeRGB = (r: 234, g: 106, b: 56)

    public let isEnabled: Bool
    public let supportsTrueColor: Bool

    public init(enabled: Bool, supportsTrueColor: Bool = true) {
        self.isEnabled = enabled
        self.supportsTrueColor = supportsTrueColor
    }

    /// Standard output style based on `STDOUT_FILENO` TTY state and process environment.
    public static var stdout: TerminalStyle {
        let env = ProcessInfo.processInfo.environment
        let isTTY = isatty(STDOUT_FILENO) != 0
        return TerminalStyle(
            enabled: shouldEnableColor(isTTY: isTTY, environment: env),
            supportsTrueColor: shouldUseTrueColor(environment: env)
        )
    }

    /// Standard error style based on `STDERR_FILENO` TTY state and process environment.
    public static var stderr: TerminalStyle {
        let env = ProcessInfo.processInfo.environment
        let isTTY = isatty(STDERR_FILENO) != 0
        return TerminalStyle(
            enabled: shouldEnableColor(isTTY: isTTY, environment: env),
            supportsTrueColor: shouldUseTrueColor(environment: env)
        )
    }

    /// Always disables ANSI escape sequences.
    public static let plain = TerminalStyle(enabled: false, supportsTrueColor: false)

    /// Always emits ANSI escape sequences (with TrueColor orange `#EA6A38`).
    public static let ansi = TerminalStyle(enabled: true, supportsTrueColor: true)

    /// Resolves whether the active terminal supports 24-bit TrueColor escape sequences.
    public static func shouldUseTrueColor(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if let colorTerm = environment["COLORTERM"]?.lowercased(),
           colorTerm.contains("truecolor") || colorTerm.contains("24bit") {
            return true
        }
        if let termProgram = environment["TERM_PROGRAM"] {
            let trueColorPrograms: Set<String> = [
                "iTerm.app", "vscode", "WarpTerminal", "ghostty", "WezTerm", "Alacritty"
            ]
            if trueColorPrograms.contains(termProgram) {
                return true
            }
        }
        return false
    }

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

    /// SGR foreground codes for the spmx icon orange (`#EA6A38`), falling back to 256-color `209`.
    public var primaryColorCodes: [String] {
        supportsTrueColor
            ? ["38", "2", "\(Self.iconOrangeRGB.r)", "\(Self.iconOrangeRGB.g)", "\(Self.iconOrangeRGB.b)"]
            : ["38", "5", "209"]
    }

    public func primary(_ text: String) -> String { wrap(text, codes: primaryColorCodes) }
    public func primaryBold(_ text: String) -> String { wrap(text, codes: ["1"] + primaryColorCodes) }
    public func orange(_ text: String) -> String { primary(text) }

    // MARK: - Semantic Helpers

    public func heading(_ text: String) -> String { primaryBold(text) }
    public func section(_ text: String) -> String { primaryBold(text) }
    public func path(_ text: String) -> String { text }
    public func mutedPath(_ text: String) -> String { gray(text) }
    public func command(_ text: String) -> String { primaryBold(text) }
    public func emphasis(_ text: String) -> String { wrap(text, codes: ["1", "3"]) }
    public func scopeLine(_ scope: String) -> String { "\(gray("Scope:")) \(scope)" }

    public func dryRunBadge(_ text: String = "[dry-run]") -> String {
        primaryBold(text)
    }

    public func doneIn(seconds: TimeInterval) -> String {
        let formatted = seconds < 10
            ? String(format: "%.1fs", max(0, seconds))
            : String(format: "%.0fs", max(0, seconds))
        return "\(green("Done")) \(gray("in \(formatted)"))"
    }

    public func successText(_ text: String) -> String { wrap(text, codes: ["1", "32"]) }
    public func runningText(_ text: String) -> String { primaryBold(text) }
    public func warningText(_ text: String) -> String { wrap(text, codes: ["1", "33"]) }
    public func errorText(_ text: String) -> String { wrap(text, codes: ["1", "31"]) }

    /// Muted gray tones for tips and secondary guidance so they remain low-focus.
    public func tip(_ text: String) -> String { wrap(text, codes: ["90"]) }
    public func tipItalic(_ text: String) -> String { wrap(text, codes: ["90", "3"]) }
    public func tipCommand(_ text: String) -> String { wrap(text, codes: ["90", "1"]) }

    /// Styles backtick-delimited inline code segments (e.g., `` `spmx setup` ``) while preserving the backticks.
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

    public var runningIcon: String { primaryBold("▸") }
    public var successIcon: String { wrap("✓", codes: ["1", "32"]) }
    public var addIcon: String { wrap("+", codes: ["1", "32"]) }
    public var removeIcon: String { wrap("-", codes: ["1", "31"]) }
    public var warningIcon: String { wrap("!", codes: ["1", "33"]) }
    public var errorIcon: String { wrap("✗", codes: ["1", "31"]) }
    public var skippedIcon: String { wrap("•", codes: ["90"]) }
    public var infoIcon: String { primary("›") }

    public func stepRunning(_ label: String) -> String {
        "  \(runningIcon) \(primary(label))"
    }

    public func stepAdded(_ title: String, detail: String? = nil) -> String {
        if let detail, !detail.isEmpty {
            return "  \(addIcon) \(title) \(gray(detail))"
        }
        return "  \(addIcon) \(title)"
    }

    public func stepSuccess(_ title: String, detail: String? = nil) -> String {
        if let detail, !detail.isEmpty {
            return "  \(successIcon) \(bold(title)) \(detail)"
        }
        return "  \(successIcon) \(bold(title))"
    }

    public func stepSkipped(_ title: String, detail: String? = nil) -> String {
        if let detail, !detail.isEmpty {
            return "  \(skippedIcon) \(gray(title)) \(tip(detail))"
        }
        return "  \(skippedIcon) \(gray(title))"
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

import ArgumentParser
import Foundation
import PSPMCore

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Diagnose APFS support, Xcode/Swift toolchain, PATH shims, store integrity, and Git hooks."
    )

    func run() throws {
        let style = TerminalStyle.stdout
        let report = DoctorDiagnostics().run()

        print(style.heading("pspm doctor"))
        for check in report.checks {
            let badge: String
            let nameText: String
            switch check.severity {
            case .pass:
                badge = style.bold(style.green("\(style.successIcon) PASS"))
                nameText = style.bold(check.name)
            case .warn:
                badge = style.bold(style.yellow("\(style.warningIcon) WARN"))
                nameText = style.yellow(style.bold(check.name))
            case .fail:
                badge = style.bold(style.red("\(style.errorIcon) FAIL"))
                nameText = style.red(style.bold(check.name))
            }
            print("  \(badge) \(nameText): \(check.summary)")
            if let remediation = check.remediation {
                print("         \(style.tip("\(style.infoIcon) \(remediation)"))")
            }
        }

        print("")
        let passText = style.green("\(report.passCount) passed")
        let warnText = report.warnCount > 0 ? style.yellow("\(report.warnCount) warning(s)") : style.dim("\(report.warnCount) warning(s)")
        let failText = report.failCount > 0 ? style.red(style.bold("\(report.failCount) failure(s)")) : style.dim("\(report.failCount) failure(s)")
        print("\(style.bold("Summary:")) \(passText), \(warnText), \(failText).")

        if report.hasFailures {
            throw ExitCode(1)
        }
    }
}

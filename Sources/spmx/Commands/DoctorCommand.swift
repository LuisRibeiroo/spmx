import ArgumentParser
import Foundation
import SPMXCore

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Diagnose APFS support, Xcode/Swift toolchain, PATH shims, store integrity, and Git hooks."
    )

    func run() throws {
        let style = TerminalStyle.stdout
        let report = DoctorDiagnostics().run()

        print(style.heading("spmx doctor"))
        print("")
        for check in report.checks {
            let badge: String
            let nameText: String
            switch check.severity {
            case .pass:
                badge = style.successText("[✓ PASS]")
                nameText = style.bold(check.name)
            case .warn:
                badge = style.warningText("[! WARN]")
                nameText = style.yellow(style.bold(check.name))
            case .fail:
                badge = style.errorText("[✗ FAIL]")
                nameText = style.red(style.bold(check.name))
            }
            let summaryText = style.formatInlineCode(check.summary, baseCodes: [], codeCodes: style.primaryColorCodes)
            print("  \(badge) \(nameText): \(summaryText)")
            if let remediation = check.remediation {
                let tipBody = style.formatInlineCode(remediation, baseCodes: ["90"], codeCodes: ["90", "1"])
                print("           \(style.tip("›")) \(tipBody)")
            }
        }

        print("")
        let passText = style.green("\(report.passCount) passed")
        let warnText = report.warnCount > 0 ? style.yellow("\(report.warnCount) warning(s)") : style.dim("\(report.warnCount) warning(s)")
        let failText = report.failCount > 0 ? style.red(style.bold("\(report.failCount) failure(s)")) : style.dim("\(report.failCount) failure(s)")
        print("\(style.section("Summary:")) \(passText), \(warnText), \(failText).")

        if report.hasFailures {
            throw ExitCode(1)
        }
    }
}

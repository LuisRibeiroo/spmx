import ArgumentParser
import Foundation
import PSPMCore

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Diagnose APFS support, Xcode/Swift toolchain, PATH shims, store integrity, and Git hooks."
    )

    func run() throws {
        let report = DoctorDiagnostics().run()

        print("pspm doctor")
        for check in report.checks {
            let badge: String
            switch check.severity {
            case .pass:
                badge = "[PASS]"
            case .warn:
                badge = "[WARN]"
            case .fail:
                badge = "[FAIL]"
            }
            print("  \(badge) \(check.name): \(check.summary)")
            if let remediation = check.remediation {
                print("         -> \(remediation)")
            }
        }

        print("")
        print("Summary: \(report.passCount) passed, \(report.warnCount) warning(s), \(report.failCount) failure(s).")

        if report.hasFailures {
            throw ExitCode(1)
        }
    }
}

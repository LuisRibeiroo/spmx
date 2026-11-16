import ArgumentParser
import Foundation
import SPMXCore

struct HooksCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hooks",
        abstract: "Manage opt-in Git post-checkout hooks for automatic worktree hydration.",
        subcommands: [
            Enable.self,
            Disable.self,
            Status.self
        ],
        defaultSubcommand: Status.self
    )

    struct Enable: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "enable",
            abstract: "Install the opt-in spmx post-checkout hook for the current repository or globally."
        )

        @Flag(name: .long, help: "Configure the Git post-checkout hook globally.")
        var global = false

        @Flag(name: .long, help: "Configure the Git post-checkout hook for the current repository.")
        var repo = false

        @Flag(
            name: .customLong("async"),
            help: "Run spmx hydrate asynchronously in the background during checkout."
        )
        var runAsync = false

        func validate() throws {
            if global && repo {
                throw ValidationError("Cannot specify both --global and --repo.")
            }
        }

        func run() throws {
            let style = TerminalStyle.stdout
            let scope: HookScope? = global ? .global : (repo ? .repo : nil)
            let manager = GitHooksManager()
            let result = try manager.enable(
                scope: scope,
                options: HookEnableOptions(async: runAsync)
            )

            if let notice = result.notice {
                print(style.stepWarning("Notice", detail: notice))
            }

            let modeLabel = result.async ? "async" : "sync"
            let actionLabel = result.alreadyInstalled ? "Updated" : "Enabled"
            print(style.stepSuccess("\(actionLabel) spmx post-checkout hook (\(result.scope.rawValue), \(modeLabel))", detail: style.path(result.hookFilePath)))

            if result.configuredGlobalHooksPath {
                print(style.stepSuccess("Configured git config --global core.hooksPath", detail: style.path(result.hooksDirectoryPath)))
            }
        }
    }

    struct Disable: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "disable",
            abstract: "Remove the spmx post-checkout hook block while preserving any other hooks."
        )

        @Flag(name: .long, help: "Remove the spmx hook from the global Git hooks configuration.")
        var global = false

        @Flag(name: .long, help: "Remove the spmx hook from the current repository.")
        var repo = false

        func validate() throws {
            if global && repo {
                throw ValidationError("Cannot specify both --global and --repo.")
            }
        }

        func run() throws {
            let scope: HookScope? = global ? .global : (repo ? .repo : nil)
            let manager = GitHooksManager()
            let result = try manager.disable(scope: scope)

            let style = TerminalStyle.stdout
            if let notice = result.notice {
                print(style.stepWarning("Notice", detail: notice))
            }

            if result.removed {
                if let hookPath = result.hookFilePath {
                    if result.preservedOtherContent {
                        print(style.stepSuccess("Removed spmx block from \(style.path(hookPath))", detail: "existing hooks preserved"))
                    } else {
                        print(style.stepSuccess("Disabled spmx post-checkout hook (\(result.scope.rawValue))", detail: style.path(hookPath)))
                    }
                }
                if result.unsetGlobalHooksPath {
                    print(style.stepSuccess("Unset git config --global core.hooksPath"))
                }
            } else {
                print(style.stepSkipped("No spmx post-checkout hook active", detail: "\(result.scope.rawValue) scope"))
            }
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show whether repository and global spmx post-checkout hooks are active."
        )

        @Flag(name: .long, help: "Show only global hook status.")
        var global = false

        @Flag(name: .long, help: "Show only repository hook status.")
        var repo = false

        func validate() throws {
            if global && repo {
                throw ValidationError("Cannot specify both --global and --repo.")
            }
        }

        func run() throws {
            let manager = GitHooksManager()
            let report = try manager.status()

            if !global {
                printScopedStatus(report.repo, title: "Repository hook")
            }
            if !repo {
                printScopedStatus(report.global, title: "Global hook")
            }
        }

        private func printScopedStatus(_ status: ScopedHookStatus, title: String) {
            let style = TerminalStyle.stdout
            guard status.isAvailable else {
                print("\(style.bold(title)): \(style.gray("\(style.skippedIcon) unavailable (not inside a Git repository)"))")
                return
            }

            if status.isActive {
                var details: [String] = [status.isAsync ? "async" : "sync"]
                if status.isChainedWithExistingHooks {
                    details.append("chained")
                }
                if !status.isExecutable {
                    details.append("not executable")
                }
                let stateText = style.green("\(style.successIcon) active")
                print("\(style.bold(title)): \(stateText) \(style.dim("(\(details.joined(separator: ", ")))"))")
            } else {
                print("\(style.bold(title)): \(style.gray("\(style.skippedIcon) inactive"))")
            }

            if let configured = status.configuredHooksPath {
                print("  \(style.dim("core.hooksPath:")) \(style.path(configured))")
            }
            if let commonDir = status.gitCommonDirPath {
                print("  \(style.dim("git common dir:")) \(style.path(commonDir))")
            }
            if let hookPath = status.hookFilePath {
                print("  \(style.dim("hook file:")) \(style.path(hookPath))")
            }
            if status.chainsExistingGlobalHooksPath {
                print("  \(style.tip("\(style.infoIcon) chaining: using existing global core.hooksPath"))")
            }
        }
    }
}

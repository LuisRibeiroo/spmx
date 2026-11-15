import ArgumentParser
import Foundation
import PSPMCore

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
            abstract: "Install the opt-in pspm post-checkout hook for the current repository or globally."
        )

        @Flag(name: .long, help: "Configure the Git post-checkout hook globally.")
        var global = false

        @Flag(name: .long, help: "Configure the Git post-checkout hook for the current repository.")
        var repo = false

        @Flag(
            name: .customLong("async"),
            help: "Run pspm hydrate asynchronously in the background during checkout."
        )
        var runAsync = false

        func validate() throws {
            if global && repo {
                throw ValidationError("Cannot specify both --global and --repo.")
            }
        }

        func run() throws {
            let scope: HookScope? = global ? .global : (repo ? .repo : nil)
            let manager = GitHooksManager()
            let result = try manager.enable(
                scope: scope,
                options: HookEnableOptions(async: runAsync)
            )

            if let notice = result.notice {
                print("Notice: \(notice)")
            }

            let modeLabel = result.async ? "async" : "sync"
            let actionLabel = result.alreadyInstalled ? "Updated" : "Enabled"
            print("\(actionLabel) pspm post-checkout hook (\(result.scope.rawValue), \(modeLabel)) at \(result.hookFilePath)")

            if result.configuredGlobalHooksPath {
                print("Configured git config --global core.hooksPath = \(result.hooksDirectoryPath)")
            }
        }
    }

    struct Disable: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "disable",
            abstract: "Remove the pspm post-checkout hook block while preserving any other hooks."
        )

        @Flag(name: .long, help: "Remove the pspm hook from the global Git hooks configuration.")
        var global = false

        @Flag(name: .long, help: "Remove the pspm hook from the current repository.")
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

            if let notice = result.notice {
                print("Notice: \(notice)")
            }

            if result.removed {
                if let hookPath = result.hookFilePath {
                    if result.preservedOtherContent {
                        print("Removed pspm block from \(hookPath) (existing hooks preserved).")
                    } else {
                        print("Disabled pspm post-checkout hook (\(result.scope.rawValue)) at \(hookPath).")
                    }
                }
                if result.unsetGlobalHooksPath {
                    print("Unset git config --global core.hooksPath.")
                }
            } else {
                print("No pspm post-checkout hook active for \(result.scope.rawValue) scope.")
            }
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show whether repository and global pspm post-checkout hooks are active."
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
            guard status.isAvailable else {
                print("\(title): unavailable (not inside a Git repository)")
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
                print("\(title): active (\(details.joined(separator: ", ")))")
            } else {
                print("\(title): inactive")
            }

            if let configured = status.configuredHooksPath {
                print("  core.hooksPath: \(configured)")
            }
            if let commonDir = status.gitCommonDirPath {
                print("  git common dir: \(commonDir)")
            }
            if let hookPath = status.hookFilePath {
                print("  hook file: \(hookPath)")
            }
            if status.chainsExistingGlobalHooksPath {
                print("  chaining: using existing global core.hooksPath")
            }
        }
    }
}

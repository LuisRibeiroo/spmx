import Foundation
import os
import Testing
@testable import SPMXCore

@Suite("GitHooksManager")
struct GitHooksManagerTests {
    @Test("Inserts delimited post-checkout hook into new repo hook with 0755 permissions")
    func insertsIntoNewRepoHook() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let commonDir = tmp.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: commonDir, withIntermediateDirectories: true)

        let runner = MockGitRunner(commonDirOutput: ".git")
        let manager = GitHooksManager(
            gitRunner: runner,
            defaultGlobalHooksDirectory: tmp.appendingPathComponent("spmx-hooks"),
            homeDirectory: tmp
        )

        let result = try manager.enable(workingDirectory: tmp.path)
        #expect(result.scope == .repo)
        #expect(result.alreadyInstalled == false)
        #expect(result.async == false)
        #expect(result.notice == nil)

        let expectedHookPath = commonDir.appendingPathComponent("hooks/post-checkout").path
        #expect(result.hookFilePath == expectedHookPath)
        #expect(FileManager.default.fileExists(atPath: expectedHookPath))

        let attributes = try FileManager.default.attributesOfItem(atPath: expectedHookPath)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        #expect(permissions == 0o755)

        let content = try String(contentsOfFile: expectedHookPath, encoding: .utf8)
        #expect(content.hasPrefix("#!/bin/sh\n"))
        #expect(content.contains(GitHooksManager.blockStartMarker))
        #expect(content.contains(GitHooksManager.blockEndMarker))
        #expect(content.contains(#"if [ "$3" = "1" ]; then"#))
        #expect(content.contains("pubspec.yaml"))
        #expect(content.contains("Package.swift"))
        #expect(content.contains("*.xcworkspace"))
        #expect(content.contains("*.xcodeproj"))
        #expect(content.contains("spmx hydrate --quiet"))
    }

    @Test("Chains with pre-existing hook preserving shebang and commands, and removes cleanly")
    func chainsAndCleanlyRemovesWithExistingHook() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let hooksDir = tmp.appendingPathComponent(".git/hooks")
        try FileManager.default.createDirectory(at: hooksDir, withIntermediateDirectories: true)
        let hookURL = hooksDir.appendingPathComponent("post-checkout")

        let existingHook = """
        #!/usr/bin/env sh
        # Lefthook / Husky existing hook
        . "$(dirname -- "$0")/_/husky.sh"
        echo "existing-hook-ran"
        """
        try existingHook.write(to: hookURL, atomically: true, encoding: .utf8)

        let runner = MockGitRunner(commonDirOutput: ".git")
        let manager = GitHooksManager(
            gitRunner: runner,
            defaultGlobalHooksDirectory: tmp.appendingPathComponent("spmx-hooks"),
            homeDirectory: tmp
        )

        let enableResult = try manager.enable(scope: .repo, workingDirectory: tmp.path)
        #expect(enableResult.alreadyInstalled == false)
        #expect(enableResult.notice != nil)

        let enabledContent = try String(contentsOf: hookURL, encoding: .utf8)
        #expect(enabledContent.hasPrefix("#!/usr/bin/env sh\n"))
        #expect(enabledContent.contains(#". "$(dirname -- "$0")/_/husky.sh""#))
        #expect(enabledContent.contains(#"echo "existing-hook-ran""#))
        #expect(enabledContent.contains(GitHooksManager.blockStartMarker))
        #expect(enabledContent.contains(GitHooksManager.blockEndMarker))

        // Re-enabling with --async updates the block in place without duplicating it.
        let updateResult = try manager.enable(
            scope: .repo,
            workingDirectory: tmp.path,
            options: HookEnableOptions(async: true)
        )
        #expect(updateResult.alreadyInstalled == true)
        #expect(updateResult.async == true)

        let updatedContent = try String(contentsOf: hookURL, encoding: .utf8)
        let startOccurrences = updatedContent.components(separatedBy: GitHooksManager.blockStartMarker).count - 1
        #expect(startOccurrences == 1)
        #expect(updatedContent.contains("spmx hydrate --quiet >/dev/null 2>&1 &"))

        // Disabling removes only the delimited spmx block and leaves existing hook intact.
        let disableResult = try manager.disable(scope: .repo, workingDirectory: tmp.path)
        #expect(disableResult.removed == true)
        #expect(disableResult.preservedOtherContent == true)
        #expect(FileManager.default.fileExists(atPath: hookURL.path))

        let disabledContent = try String(contentsOf: hookURL, encoding: .utf8)
        #expect(!disabledContent.contains(GitHooksManager.blockStartMarker))
        #expect(!disabledContent.contains(GitHooksManager.blockEndMarker))
        #expect(disabledContent == existingHook + "\n")
    }

    @Test("Removes empty post-checkout hook file on disable when no other commands remain")
    func removesHookFileWhenOnlySPMXBlockWasPresent() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try FileManager.default.createDirectory(at: tmp.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let runner = MockGitRunner(commonDirOutput: ".git")
        let manager = GitHooksManager(
            gitRunner: runner,
            defaultGlobalHooksDirectory: tmp.appendingPathComponent("spmx-hooks"),
            homeDirectory: tmp
        )

        let enableResult = try manager.enable(scope: .repo, workingDirectory: tmp.path)
        #expect(FileManager.default.fileExists(atPath: enableResult.hookFilePath))

        let disableResult = try manager.disable(scope: .repo, workingDirectory: tmp.path)
        #expect(disableResult.removed == true)
        #expect(disableResult.preservedOtherContent == false)
        #expect(!FileManager.default.fileExists(atPath: enableResult.hookFilePath))

        let secondDisable = try manager.disable(scope: .repo, workingDirectory: tmp.path)
        #expect(secondDisable.removed == false)
    }

    @Test("Resolves shared hooks directory across git worktrees via --git-common-dir")
    func resolvesSharedHooksInRealGitWorktree() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let mainRepo = tmp.appendingPathComponent("main-repo")
        let worktree = tmp.appendingPathComponent("feature-worktree")
        try FileManager.default.createDirectory(at: mainRepo, withIntermediateDirectories: true)

        let systemGit = SystemGitRunner()
        try runGitOrThrow(systemGit, args: ["init"], cwd: mainRepo.path)
        try runGitOrThrow(systemGit, args: ["config", "user.email", "test@example.com"], cwd: mainRepo.path)
        try runGitOrThrow(systemGit, args: ["config", "user.name", "Test User"], cwd: mainRepo.path)
        try "hello\n".write(to: mainRepo.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try runGitOrThrow(systemGit, args: ["add", "Package.swift"], cwd: mainRepo.path)
        try runGitOrThrow(systemGit, args: ["commit", "-m", "initial"], cwd: mainRepo.path)
        try runGitOrThrow(systemGit, args: ["worktree", "add", "-b", "feature/wt", worktree.path], cwd: mainRepo.path)

        let manager = GitHooksManager(
            gitRunner: systemGit,
            defaultGlobalHooksDirectory: tmp.appendingPathComponent("spmx-hooks"),
            homeDirectory: tmp
        )

        // Enable from inside the linked worktree; default scope should be .repo and resolve mainRepo/.git/hooks.
        let result = try manager.enable(workingDirectory: worktree.path)
        let expectedCommonHooks = mainRepo.appendingPathComponent(".git/hooks/post-checkout").standardized.path
        let resolvedResultPath = URL(fileURLWithPath: result.hookFilePath).resolvingSymlinksInPath().path
        let resolvedExpectedPath = URL(fileURLWithPath: expectedCommonHooks).resolvingSymlinksInPath().path

        #expect(result.scope == .repo)
        #expect(resolvedResultPath == resolvedExpectedPath)

        let statusReport = try manager.status(workingDirectory: worktree.path)
        #expect(statusReport.repo.isAvailable == true)
        #expect(statusReport.repo.isActive == true)
        #expect(statusReport.repo.isExecutable == true)
        #expect(statusReport.repo.gitCommonDirPath != nil)
    }

    @Test("Global mode configures core.hooksPath when unset and unsets cleanly on disable")
    func globalModeConfiguresAndUnsetsWhenUnset() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let defaultGlobalHooks = tmp.appendingPathComponent(".spmx/git-hooks")
        let runner = MockGitRunner(commonDirOutput: nil, globalHooksPath: nil)
        let manager = GitHooksManager(
            gitRunner: runner,
            defaultGlobalHooksDirectory: defaultGlobalHooks,
            homeDirectory: tmp
        )

        let enableResult = try manager.enable(scope: .global, workingDirectory: tmp.path)
        #expect(enableResult.scope == .global)
        #expect(enableResult.configuredGlobalHooksPath == true)
        #expect(enableResult.chainedExistingHooksPath == nil)
        #expect(enableResult.hooksDirectoryPath == defaultGlobalHooks.standardized.path)
        #expect(runner.currentGlobalHooksPath == defaultGlobalHooks.standardized.path)
        #expect(FileManager.default.fileExists(atPath: enableResult.hookFilePath))

        let statusActive = try manager.status(workingDirectory: tmp.path)
        #expect(statusActive.repo.isAvailable == false)
        #expect(statusActive.global.isAvailable == true)
        #expect(statusActive.global.isActive == true)
        #expect(statusActive.global.chainsExistingGlobalHooksPath == false)

        let disableResult = try manager.disable(scope: .global, workingDirectory: tmp.path)
        #expect(disableResult.removed == true)
        #expect(disableResult.unsetGlobalHooksPath == true)
        #expect(runner.currentGlobalHooksPath == nil)

        let statusInactive = try manager.status(workingDirectory: tmp.path)
        #expect(statusInactive.global.isActive == false)
    }

    @Test("Global mode chains into pre-existing core.hooksPath without clobbering it")
    func globalModeChainsExistingCoreHooksPath() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let userHooksDir = tmp.appendingPathComponent("custom-global-hooks")
        try FileManager.default.createDirectory(at: userHooksDir, withIntermediateDirectories: true)
        let userPostCheckout = userHooksDir.appendingPathComponent("post-checkout")
        let existingGlobalHook = "#!/bin/sh\necho \"user global hook\"\n"
        try existingGlobalHook.write(to: userPostCheckout, atomically: true, encoding: .utf8)

        let runner = MockGitRunner(commonDirOutput: nil, globalHooksPath: "~/custom-global-hooks")
        let manager = GitHooksManager(
            gitRunner: runner,
            defaultGlobalHooksDirectory: tmp.appendingPathComponent(".spmx/git-hooks"),
            homeDirectory: tmp
        )

        let enableResult = try manager.enable(
            scope: .global,
            workingDirectory: tmp.path,
            options: HookEnableOptions(async: true)
        )
        #expect(enableResult.configuredGlobalHooksPath == false)
        #expect(enableResult.chainedExistingHooksPath == userHooksDir.standardized.path)
        #expect(enableResult.hookFilePath == userPostCheckout.standardized.path)
        #expect(enableResult.notice != nil)
        #expect(runner.currentGlobalHooksPath == "~/custom-global-hooks")

        let content = try String(contentsOf: userPostCheckout, encoding: .utf8)
        #expect(content.contains(#"echo "user global hook""#))
        #expect(content.contains(GitHooksManager.blockStartMarker))
        #expect(content.contains("spmx hydrate --quiet >/dev/null 2>&1 &"))

        let status = try manager.status(workingDirectory: tmp.path)
        #expect(status.global.isActive == true)
        #expect(status.global.isAsync == true)
        #expect(status.global.isChainedWithExistingHooks == true)
        #expect(status.global.chainsExistingGlobalHooksPath == true)
        #expect(status.global.configuredHooksPath == "~/custom-global-hooks")

        let disableResult = try manager.disable(scope: .global, workingDirectory: tmp.path)
        #expect(disableResult.removed == true)
        #expect(disableResult.preservedOtherContent == true)
        #expect(disableResult.unsetGlobalHooksPath == false)
        #expect(runner.currentGlobalHooksPath == "~/custom-global-hooks")

        let afterDisable = try String(contentsOf: userPostCheckout, encoding: .utf8)
        #expect(afterDisable == existingGlobalHook)
    }

    @Test("Throws when default scope is requested outside a Git repository")
    func throwsOutsideGitRepoWithoutGlobalFlag() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let runner = MockGitRunner(commonDirOutput: nil, globalHooksPath: nil)
        let manager = GitHooksManager(
            gitRunner: runner,
            defaultGlobalHooksDirectory: tmp.appendingPathComponent(".spmx/git-hooks"),
            homeDirectory: tmp
        )

        #expect(throws: GitHooksError.notInGitRepository(tmp.path)) {
            try manager.enable(workingDirectory: tmp.path)
        }
    }

    @Test("Throws malformedHookBlock when start marker lacks end marker")
    func throwsOnMalformedHookBlock() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let hooksDir = tmp.appendingPathComponent(".git/hooks")
        try FileManager.default.createDirectory(at: hooksDir, withIntermediateDirectories: true)
        let hookURL = hooksDir.appendingPathComponent("post-checkout")
        try "#!/bin/sh\n\(GitHooksManager.blockStartMarker)\necho broken\n"
            .write(to: hookURL, atomically: true, encoding: .utf8)

        let runner = MockGitRunner(commonDirOutput: ".git")
        let manager = GitHooksManager(
            gitRunner: runner,
            defaultGlobalHooksDirectory: tmp.appendingPathComponent(".spmx/git-hooks"),
            homeDirectory: tmp
        )

        #expect(throws: GitHooksError.malformedHookBlock(hookURL.path)) {
            try manager.disable(scope: .repo, workingDirectory: tmp.path)
        }
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spmx-hook-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func runGitOrThrow(_ runner: SystemGitRunner, args: [String], cwd: String) throws {
        let result = try runner.runGit(arguments: args, workingDirectory: cwd)
        #expect(result.exitCode == 0, "git \(args.joined(separator: " ")) failed: \(result.stderr)")
    }
}

private final class MockGitRunner: GitCommandRunning {
    struct State: Sendable {
        var commonDirOutput: String?
        var globalHooksPath: String?
        var recordedCommands: [[String]] = []
    }

    private let state: OSAllocatedUnfairLock<State>

    init(commonDirOutput: String?, globalHooksPath: String? = nil) {
        self.state = OSAllocatedUnfairLock(
            initialState: State(
                commonDirOutput: commonDirOutput,
                globalHooksPath: globalHooksPath
            )
        )
    }

    var currentGlobalHooksPath: String? {
        state.withLock { $0.globalHooksPath }
    }

    func runGit(arguments: [String], workingDirectory: String?) throws -> GitCommandResult {
        let args = arguments
        return state.withLock { s in
            s.recordedCommands.append(args)

            if args == ["rev-parse", "--git-common-dir"] {
                if let commonDir = s.commonDirOutput {
                    return GitCommandResult(exitCode: 0, stdout: "\(commonDir)\n")
                }
                return GitCommandResult(exitCode: 128, stdout: "", stderr: "fatal: not a git repository")
            }

            if args == ["config", "--global", "--get", "core.hooksPath"] {
                if let path = s.globalHooksPath {
                    return GitCommandResult(exitCode: 0, stdout: "\(path)\n")
                }
                return GitCommandResult(exitCode: 1, stdout: "")
            }

            if args.count == 4 && args[0] == "config" && args[1] == "--global" && args[2] == "core.hooksPath" {
                s.globalHooksPath = args[3]
                return GitCommandResult(exitCode: 0, stdout: "")
            }

            if args == ["config", "--global", "--unset", "core.hooksPath"] {
                if s.globalHooksPath == nil {
                    return GitCommandResult(exitCode: 5, stdout: "")
                }
                s.globalHooksPath = nil
                return GitCommandResult(exitCode: 0, stdout: "")
            }

            return GitCommandResult(exitCode: 1, stdout: "", stderr: "unexpected mock git command: \(args)")
        }
    }
}

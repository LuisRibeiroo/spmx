import Foundation
import Testing
@testable import SPMXCore

@Suite("SetupManager")
struct SetupManagerTests {
    @Test("Creates directories and shim symlinks pointing to binaryPath, updating existing symlinks")
    func createsDirectoriesAndShims() throws {
        let home = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }

        let oldBinary = home.appendingPathComponent("old/spmx")
        let newBinary = home.appendingPathComponent(".spmx/bin/spmx")

        // First setup pointing to oldBinary (even if target doesn't exist yet -> dangling symlink)
        let first = try SetupManager.setup(
            noModifyPath: true,
            binaryPath: oldBinary,
            homeDirectory: home,
            shell: "/bin/zsh"
        )

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: first.binDirectory.path))
        #expect(fm.fileExists(atPath: first.shimsDirectory.path))
        #expect(fm.fileExists(atPath: first.storeDirectory.path))
        #expect(fm.fileExists(atPath: first.compilationCacheDirectory.path))
        #expect(first.shimPaths.count == 3)

        for name in ["flutter", "xcodebuild", "swift"] {
            let shimURL = first.shimsDirectory.appendingPathComponent(name)
            let dest = try fm.destinationOfSymbolicLink(atPath: shimURL.path)
            #expect(dest == oldBinary.path)
        }

        // Second setup pointing to newBinary should replace existing/dangling symlinks cleanly
        let second = try SetupManager.setup(
            noModifyPath: true,
            binaryPath: newBinary,
            homeDirectory: home,
            shell: "/bin/zsh"
        )

        for name in ["flutter", "xcodebuild", "swift"] {
            let shimURL = second.shimsDirectory.appendingPathComponent(name)
            let dest = try fm.destinationOfSymbolicLink(atPath: shimURL.path)
            #expect(dest == newBinary.path)
        }
    }

    @Test("Idempotently injects and removes PATH block across zsh, bash, and fish")
    func idempotentRCInjectionAndRemoval() throws {
        let cases: [(shell: String, relPath: String, expectedExport: String)] = [
            (
                "/bin/zsh",
                ".zshrc",
                #"export PATH="$HOME/.spmx/shims:$HOME/.spmx/bin:$PATH""#
            ),
            (
                "/bin/bash",
                ".bashrc",
                #"export PATH="$HOME/.spmx/shims:$HOME/.spmx/bin:$PATH""#
            ),
            (
                "/opt/homebrew/bin/fish",
                ".config/fish/config.fish",
                #"set -gx PATH "$HOME/.spmx/shims" "$HOME/.spmx/bin" $PATH"#
            )
        ]

        for testCase in cases {
            let home = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: home) }

            let rcURL = home.appendingPathComponent(testCase.relPath)
            try FileManager.default.createDirectory(
                at: rcURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let initialContent = "# existing config\nexport EDITOR=vim\n"
            try initialContent.write(to: rcURL, atomically: true, encoding: .utf8)

            let binary = home.appendingPathComponent(".spmx/bin/spmx")

            let result1 = try SetupManager.setup(
                noModifyPath: false,
                binaryPath: binary,
                homeDirectory: home,
                shell: testCase.shell
            )
            #expect(result1.modifiedShellRC == rcURL)

            let afterFirst = try String(contentsOf: rcURL, encoding: .utf8)
            #expect(afterFirst.contains("# existing config"))
            #expect(afterFirst.contains("export EDITOR=vim"))
            #expect(afterFirst.contains(SetupManager.blockStartMarker))
            #expect(afterFirst.contains(testCase.expectedExport))
            #expect(afterFirst.contains(SetupManager.blockEndMarker))

            // Running setup a second time must be byte-for-byte idempotent
            _ = try SetupManager.setup(
                noModifyPath: false,
                binaryPath: binary,
                homeDirectory: home,
                shell: testCase.shell
            )
            let afterSecond = try String(contentsOf: rcURL, encoding: .utf8)
            #expect(afterSecond == afterFirst)
            #expect(afterSecond.components(separatedBy: SetupManager.blockStartMarker).count == 2)

            // Uninstalling removes only the spmx block while preserving existing config
            let uninstallResult = try SetupManager.uninstall(
                purge: false,
                homeDirectory: home
            )
            #expect(uninstallResult.cleanedShellRCs.contains(rcURL))

            let afterUninstall = try String(contentsOf: rcURL, encoding: .utf8)
            #expect(!afterUninstall.contains(SetupManager.blockStartMarker))
            #expect(!afterUninstall.contains(SetupManager.blockEndMarker))
            #expect(!afterUninstall.contains(testCase.expectedExport))
            #expect(afterUninstall == initialContent)
        }
    }

    @Test("Preserves content before and after managed block on removal")
    func preservesSurroundingContentOnRemoval() {
        let original = """
        # before
        export FOO=1

        # >>> spmx >>>
        export PATH="$HOME/.spmx/shims:$HOME/.spmx/bin:$PATH"
        # <<< spmx <<<

        # after
        export BAR=2

        """

        let (stripped, didModify) = SetupManager.stripManagedBlock(from: original)
        #expect(didModify)
        #expect(stripped == """
        # before
        export FOO=1

        # after
        export BAR=2

        """)
    }

    @Test("noModifyPath skips modifying shell RC files and provides manual activation instructions")
    func noModifyPathSkipsRC() throws {
        let home = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }

        let zshrc = home.appendingPathComponent(".zshrc")
        let binary = home.appendingPathComponent(".spmx/bin/spmx")

        let result = try SetupManager.setup(
            noModifyPath: true,
            binaryPath: binary,
            homeDirectory: home,
            shell: "/bin/zsh"
        )

        #expect(result.modifiedShellRC == nil)
        #expect(!FileManager.default.fileExists(atPath: zshrc.path))
        #expect(result.activationCommand.contains(".spmx/shims"))

        let banner = result.summaryBanner()
        #expect(banner.contains("active by default"))
        #expect(banner.contains("disabled by default"))
        #expect(banner.contains("spmx hooks enable --global"))
        #expect(banner.contains("git worktree add"))
        #expect(banner.contains(result.activationCommand))

        let ansiBanner = result.summaryBanner(style: .ansi)
        #expect(ansiBanner.contains("✓"))
        #expect(ansiBanner.contains("\u{1B}[1;32m"))
        #expect(ansiBanner.contains("\u{1B}[90;3mTips:\u{1B}[0m"))
        #expect(ansiBanner.contains("\u{1B}[90;1m`spmx hooks enable --global`\u{1B}[0m"))
    }

    @Test("setup emits running, completed, and skipped step events")
    func setupStepObserverEvents() throws {
        let home = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }

        let binary = home.appendingPathComponent(".spmx/bin/spmx")
        try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("binary".utf8).write(to: binary)

        final class EventBox: @unchecked Sendable {
            private let lock = NSLock()
            private var storage: [SetupStepEvent] = []
            func append(_ event: SetupStepEvent) {
                lock.lock()
                storage.append(event)
                lock.unlock()
            }
            var items: [SetupStepEvent] {
                lock.lock()
                defer { lock.unlock() }
                return storage
            }
        }

        let box = EventBox()
        _ = try SetupManager.setup(
            noModifyPath: true,
            binaryPath: binary,
            homeDirectory: home,
            shell: "/bin/zsh",
            stepObserver: { box.append($0) }
        )

        let events = box.items
        #expect(events.contains { if case .running = $0 { return true }; return false })
        #expect(events.contains { if case .completed = $0 { return true }; return false })
        #expect(events.contains { if case .skipped = $0 { return true }; return false })
    }

    @Test("setup copies external executable into ~/.spmx/bin/spmx, links ~/.local/bin when on PATH, and uninstall cleans only managed links")
    func copiesBinaryAndLinksLocalBin() throws {
        let home = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }

        let fm = FileManager.default
        let externalBinary = home.appendingPathComponent("build/spmx")
        try fm.createDirectory(at: externalBinary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\necho spmx\n".utf8).write(to: externalBinary)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: externalBinary.path)

        let localBinDir = home.appendingPathComponent(".local/bin")
        let envWithLocalBin = ["PATH": "\(localBinDir.path):/usr/bin:/bin"]

        let result = try SetupManager.setup(
            noModifyPath: true,
            binaryPath: externalBinary,
            homeDirectory: home,
            shell: "/bin/zsh",
            environment: envWithLocalBin
        )

        let installedBinary = home.appendingPathComponent(".spmx/bin/spmx")
        #expect(result.binaryPath.standardizedFileURL.path == installedBinary.standardizedFileURL.path)
        #expect(fm.isExecutableFile(atPath: installedBinary.path))

        let shimDest = try fm.destinationOfSymbolicLink(atPath: home.appendingPathComponent(".spmx/shims/swift").path)
        #expect(shimDest == installedBinary.path)

        let localBinLink = localBinDir.appendingPathComponent("spmx")
        #expect(result.localBinSymlink?.path == localBinLink.path)
        let localDest = try fm.destinationOfSymbolicLink(atPath: localBinLink.path)
        #expect(localDest == installedBinary.path)

        _ = try SetupManager.uninstall(purge: true, homeDirectory: home)
        #expect((try? fm.attributesOfItem(atPath: localBinLink.path)) == nil)
    }

    @Test("uninstall without purge preserves store and compilation-cache; with purge removes them")
    func uninstallWithAndWithoutPurge() throws {
        let home = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }

        let fm = FileManager.default
        let binary = home.appendingPathComponent(".spmx/bin/spmx")
        try fm.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("binary".utf8).write(to: binary)

        _ = try SetupManager.setup(
            noModifyPath: false,
            binaryPath: binary,
            homeDirectory: home,
            shell: "/bin/zsh"
        )

        let storeMarker = home.appendingPathComponent(".spmx/store/index.json")
        let cacheMarker = home.appendingPathComponent(".spmx/compilation-cache/cas.db")
        try Data("{}".utf8).write(to: storeMarker)
        try Data("cas".utf8).write(to: cacheMarker)

        // Uninstall without purge
        let nonPurge = try SetupManager.uninstall(purge: false, homeDirectory: home)
        #expect(nonPurge.removedShimsDirectory)
        #expect(nonPurge.removedBinary)
        #expect(!nonPurge.purgedStore)
        #expect(!nonPurge.purgedCompilationCache)
        #expect(!fm.fileExists(atPath: home.appendingPathComponent(".spmx/shims").path))
        #expect(!fm.fileExists(atPath: binary.path))
        #expect(fm.fileExists(atPath: storeMarker.path))
        #expect(fm.fileExists(atPath: cacheMarker.path))

        // Re-setup and uninstall with purge
        try Data("binary".utf8).write(to: binary)
        _ = try SetupManager.setup(
            noModifyPath: false,
            binaryPath: binary,
            homeDirectory: home,
            shell: "/bin/zsh"
        )

        let purged = try SetupManager.uninstall(purge: true, homeDirectory: home)
        #expect(purged.removedShimsDirectory)
        #expect(purged.removedBinary)
        #expect(purged.purgedStore)
        #expect(purged.purgedCompilationCache)
        #expect(!fm.fileExists(atPath: home.appendingPathComponent(".spmx/store").path))
        #expect(!fm.fileExists(atPath: home.appendingPathComponent(".spmx/compilation-cache").path))
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spmx-setup-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

import Foundation
import Testing
@testable import PSPMCore

@Suite("MigrationManager")
struct MigrationManagerTests {
    private static let fixedToolchain = ToolchainFingerprint(
        swiftVersion: "Apple Swift version 6.4.2",
        xcodeVersion: "Xcode 27.2",
        hash: "migration_test_toolchain"
    )

    @Test("discovers Flutter, Xcode, and SwiftPM projects while honoring excludes, maxDepth, and symlink safety")
    func discoveryAndFiltering() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let fm = FileManager.default
        let workspace = root.appendingPathComponent("work")
        try fm.createDirectory(at: workspace, withIntermediateDirectories: true)

        // 1. SwiftPM project at depth 1
        let swiftPkg = workspace.appendingPathComponent("swift-lib")
        try createSwiftPMProject(at: swiftPkg, identity: "dep-a", revision: "rev111", cleanCheckout: true)

        // 2. Flutter project (should NOT double-detect ios/Runner.xcodeproj inside it)
        let flutterApp = workspace.appendingPathComponent("flutter-app")
        try fm.createDirectory(at: flutterApp.appendingPathComponent("ios/Runner.xcodeproj"), withIntermediateDirectories: true)
        try Data("name: sample_app\n".utf8).write(to: flutterApp.appendingPathComponent("pubspec.yaml"))

        // 3. Excluded directory
        let vendorPkg = workspace.appendingPathComponent("vendor-skip/nested-lib")
        try createSwiftPMProject(at: vendorPkg, identity: "dep-v", revision: "rev222", cleanCheckout: true)

        // 4. Too deep project beyond maxDepth=2
        let deepPkg = workspace.appendingPathComponent("a/b/c/deep-lib")
        try createSwiftPMProject(at: deepPkg, identity: "dep-d", revision: "rev333", cleanCheckout: true)

        // 5. Symlink loop inside workspace
        try? fm.createSymbolicLink(atPath: workspace.appendingPathComponent("loop-link").path, withDestinationPath: workspace.path)

        let store = GlobalStore(rootURL: root.appendingPathComponent("store"))
        let manager = MigrationManager(
            store: store,
            toolchainProvider: { Self.fixedToolchain },
            homeDirectory: root
        )

        let report = try manager.migrate(options: MigrationOptions(
            searchRoots: [workspace.path],
            dryRun: true,
            deduplicate: true,
            maxDepth: 2,
            excludePatterns: ["vendor-skip"]
        ))

        let foundRoots = Set(report.outcomes.map { URL(fileURLWithPath: $0.project.rootPath).lastPathComponent })
        #expect(foundRoots.contains("swift-lib"))
        #expect(foundRoots.contains("flutter-app"))
        #expect(!foundRoots.contains("ios"))
        #expect(!foundRoots.contains("nested-lib"))
        #expect(!foundRoots.contains("deep-lib"))
        #expect(report.dryRun)
        #expect(report.projectsWithExistingCacheCount == 1)
        #expect(report.totalExistingCacheBytes > 0)
        #expect(report.totalEstimatedReclaimedBytes == report.totalExistingCacheBytes)
        #expect(!fm.fileExists(atPath: store.indexURL.path))
    }

    @Test("discovers linked Git worktrees even outside scanned subdirectory")
    func discoversLinkedGitWorktrees() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let mainRepo = root.appendingPathComponent("main-repo")
        let linkedWorktree = root.appendingPathComponent("linked-wt")
        try createSwiftPMProject(at: mainRepo, identity: "dep-wt", revision: "revwt1", cleanCheckout: true)

        try runGit(["init"], in: mainRepo)
        try runGit(["config", "user.email", "test@example.com"], in: mainRepo)
        try runGit(["config", "user.name", "Tester"], in: mainRepo)
        try runGit(["add", "Package.swift", "Package.resolved"], in: mainRepo)
        try runGit(["commit", "-m", "init"], in: mainRepo)
        try runGit(["worktree", "add", linkedWorktree.path, "-b", "feature/wt"], in: mainRepo)

        let store = GlobalStore(rootURL: root.appendingPathComponent("store"))
        let manager = MigrationManager(
            store: store,
            toolchainProvider: { Self.fixedToolchain },
            homeDirectory: root
        )

        let projects = manager.discoverProjects(in: [mainRepo.path], maxDepth: 2)
        let names = Set(projects.map { URL(fileURLWithPath: $0.rootPath).lastPathComponent })
        #expect(names == ["main-repo", "linked-wt"])
    }

    @Test("migrates and deduplicates clean checkouts while preserving dirty local checkouts")
    func migrateAndDeduplicatePreservesDirtyCheckout() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let projectA = root.appendingPathComponent("proj-a")
        let projectB = root.appendingPathComponent("proj-b")
        try createSwiftPMProject(at: projectA, identity: "clean-pkg", revision: "rev-clean", cleanCheckout: true)
        try createSwiftPMProject(at: projectB, identity: "dirty-pkg", revision: "rev-dirty", cleanCheckout: false)

        // Also seed clean-pkg in projectB so both store harvest and CoW deduplication trigger cleanly.
        let combinedDir = root.appendingPathComponent("proj-b/.build/checkouts/clean-pkg")
        try FileManager.default.createDirectory(at: combinedDir, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 4096).write(to: combinedDir.appendingPathComponent("Lib.swift"))

        let store = GlobalStore(rootURL: root.appendingPathComponent("store"))
        let manager = MigrationManager(
            store: store,
            toolchainProvider: { Self.fixedToolchain },
            homeDirectory: root
        )

        let report = try manager.migrate(options: MigrationOptions(
            searchRoots: [root.path],
            dryRun: false,
            deduplicate: true,
            maxDepth: 3
        ))

        #expect(report.discoveredCount == 2)
        #expect(report.totalHarvestedItemsCount >= 2)
        #expect(report.totalDeduplicatedItemsCount >= 1)
        #expect(report.totalEstimatedReclaimedBytes > 0)
        #expect(store.hasCheckout(identity: "clean-pkg", revision: "rev-clean"))

        // Dirty checkout inside proj-b must preserve its local modification
        let outcomeB = try #require(report.outcomes.first { URL(fileURLWithPath: $0.project.rootPath).lastPathComponent == "proj-b" })
        #expect(outcomeB.skippedLocallyModifiedCount == 1)
        let dirtyFile = projectB.appendingPathComponent(".build/checkouts/dirty-pkg/LocalEdit.txt")
        #expect(FileManager.default.fileExists(atPath: dirtyFile.path))
    }

    @Test("skips project when active build command matches its root path")
    func skipsActiveBuild() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = root.appendingPathComponent("busy-pkg")
        try createSwiftPMProject(at: project, identity: "busy-dep", revision: "rev-busy", cleanCheckout: true)

        let store = GlobalStore(rootURL: root.appendingPathComponent("store"))
        let manager = MigrationManager(
            store: store,
            toolchainProvider: { Self.fixedToolchain },
            homeDirectory: root,
            activeCommandsProvider: {
                ["/usr/bin/swift-build --package-path \(project.path)"]
            }
        )

        let report = try manager.migrate(options: MigrationOptions(
            searchRoots: [root.path],
            dryRun: false,
            deduplicate: true
        ))

        let outcome = try #require(report.outcomes.first)
        #expect(outcome.skippedReason == "active build detected")
        #expect(outcome.totalHarvestedItemsCount == 0)
        #expect(!store.hasCheckout(identity: "busy-dep", revision: "rev-busy"))
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pspm-migrate-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func createSwiftPMProject(
        at root: URL,
        identity: String,
        revision: String,
        cleanCheckout: Bool
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: \"Sample\")\n".utf8)
            .write(to: root.appendingPathComponent("Package.swift"))

        let resolvedJSON = """
        {
          "pins" : [
            {
              "identity" : "\(identity)",
              "kind" : "remoteSourceControl",
              "location" : "https://example.com/\(identity).git",
              "state" : {
                "revision" : "\(revision)",
                "version" : "1.0.0"
              }
            }
          ],
          "version" : 2
        }
        """
        try Data(resolvedJSON.utf8).write(to: root.appendingPathComponent("Package.resolved"))

        let buildDir = root.appendingPathComponent(".build")
        let checkoutDir = buildDir.appendingPathComponent("checkouts/\(identity)")
        try fm.createDirectory(at: checkoutDir, withIntermediateDirectories: true)
        try Data(repeating: 0x5A, count: 4096).write(to: checkoutDir.appendingPathComponent("Source.swift"))

        if !cleanCheckout {
            // Initialize a git repo with an untracked/dirty file so isGitWorkingTreeDirty detects it
            try runGit(["init"], in: checkoutDir)
            try Data("dirty change\n".utf8).write(to: checkoutDir.appendingPathComponent("LocalEdit.txt"))
        }

        let workspaceStateJSON = """
        {
          "object" : {
            "artifacts" : [],
            "dependencies" : [
              {
                "basedOn" : null,
                "packageRef" : {
                  "identity" : "\(identity)",
                  "kind" : "remoteSourceControl",
                  "location" : "https://example.com/\(identity).git",
                  "name" : "\(identity)"
                },
                "state" : {
                  "checkoutState" : {
                    "revision" : "\(revision)",
                    "version" : "1.0.0"
                  },
                  "name" : "sourceControlCheckout"
                },
                "subpath" : "\(identity)"
              }
            ],
            "prebuilts" : []
          },
          "version" : 7
        }
        """
        try Data(workspaceStateJSON.utf8).write(to: buildDir.appendingPathComponent("workspace-state.json"))
    }

    private func runGit(_ args: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}

import Foundation
import Testing
@testable import PSPMCore

@Suite("ProjectDetector")
struct ProjectDetectorTests {
    @Test("Detects Flutter iOS and macOS SPM project with .flutter-plugins-dependencies and ephemeral package")
    func detectsFlutterMultiplatformProject() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try "name: my_flutter_app\n".write(
            to: tmp.appendingPathComponent("pubspec.yaml"),
            atomically: true,
            encoding: .utf8
        )

        let pluginDeps = """
        {
          "info": "Generated",
          "plugins": {
            "ios": [
              { "name": "firebase_core", "path": "/tmp/.pub-cache/firebase_core" },
              { "name": "shared_preferences_foundation", "path": "/tmp/.pub-cache/shared_preferences" }
            ],
            "macos": [
              { "name": "shared_preferences_foundation", "path": "/tmp/.pub-cache/shared_preferences" }
            ]
          }
        }
        """
        try pluginDeps.write(
            to: tmp.appendingPathComponent(".flutter-plugins-dependencies"),
            atomically: true,
            encoding: .utf8
        )

        // iOS workspace + generated SPM package + Package.resolved
        let iosWorkspace = tmp.appendingPathComponent("ios/Runner.xcworkspace")
        let iosSwiftPM = iosWorkspace.appendingPathComponent("xcshareddata/swiftpm")
        try FileManager.default.createDirectory(at: iosSwiftPM, withIntermediateDirectories: true)
        let iosResolved = iosSwiftPM.appendingPathComponent("Package.resolved")
        try "{}".write(to: iosResolved, atomically: true, encoding: .utf8)

        let iosGeneratedPkg = tmp.appendingPathComponent("ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage")
        try FileManager.default.createDirectory(at: iosGeneratedPkg, withIntermediateDirectories: true)
        let iosGeneratedManifest = iosGeneratedPkg.appendingPathComponent("Package.swift")
        try "// swift-tools-version: 5.9\n".write(to: iosGeneratedManifest, atomically: true, encoding: .utf8)

        // macOS workspace + Package.resolved
        let macosWorkspace = tmp.appendingPathComponent("macos/Runner.xcworkspace")
        let macosSwiftPM = macosWorkspace.appendingPathComponent("xcshareddata/swiftpm")
        try FileManager.default.createDirectory(at: macosSwiftPM, withIntermediateDirectories: true)
        let macosResolved = macosSwiftPM.appendingPathComponent("Package.resolved")
        try "{}".write(to: macosResolved, atomically: true, encoding: .utf8)

        let detected = try ProjectDetector.detect(in: tmp.path)

        #expect(detected.type == .flutter)
        #expect(detected.rootPath == tmp.path)
        #expect(detected.containerPath == iosWorkspace.path)
        #expect(detected.packageManifestPath == iosGeneratedManifest.path)
        #expect(detected.packageResolvedPath == iosResolved.path)
        #expect(detected.allPackageResolvedPaths == [iosResolved.path, macosResolved.path])

        let flutter = try #require(detected.flutterInfo)
        #expect(flutter.pubspecPath == tmp.appendingPathComponent("pubspec.yaml").path)
        #expect(flutter.pluginDependenciesPath == tmp.appendingPathComponent(".flutter-plugins-dependencies").path)
        #expect(flutter.pluginNamesByPlatform[.ios] == ["firebase_core", "shared_preferences_foundation"])
        #expect(flutter.pluginNamesByPlatform[.macos] == ["shared_preferences_foundation"])
        #expect(flutter.hasGeneratedSwiftPackage == true)
        #expect(flutter.targets.count == 2)
        #expect(flutter.targets[0].platform == .ios)
        #expect(flutter.targets[0].generatedPackageManifestExists == true)
        #expect(flutter.targets[1].platform == .macos)
        #expect(flutter.targets[1].generatedPackageManifestExists == false)
    }

    @Test("Detects clean Flutter worktree without ephemeral directory")
    func detectsFlutterWithoutEphemeral() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try "name: clean_worktree\n".write(
            to: tmp.appendingPathComponent("pubspec.yaml"),
            atomically: true,
            encoding: .utf8
        )
        let iosWorkspace = tmp.appendingPathComponent("ios/Runner.xcworkspace")
        try FileManager.default.createDirectory(at: iosWorkspace, withIntermediateDirectories: true)

        let detected = try ProjectDetector.detect(in: tmp.path)
        #expect(detected.type == .flutter)
        #expect(detected.containerPath == iosWorkspace.path)
        #expect(detected.packageManifestPath == nil)
        #expect(detected.packageResolvedPath == nil)
        #expect(detected.flutterInfo?.hasGeneratedSwiftPackage == false)
    }

    @Test("Explicit --workspace selects macOS Runner.xcworkspace in Flutter project")
    func explicitWorkspaceInsideFlutter() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try "name: flutter_mac\n".write(
            to: tmp.appendingPathComponent("pubspec.yaml"),
            atomically: true,
            encoding: .utf8
        )
        let iosResolved = tmp.appendingPathComponent("ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        try FileManager.default.createDirectory(at: iosResolved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{}".write(to: iosResolved, atomically: true, encoding: .utf8)

        let macResolved = tmp.appendingPathComponent("macos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        try FileManager.default.createDirectory(at: macResolved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{}".write(to: macResolved, atomically: true, encoding: .utf8)

        let detected = try ProjectDetector.detect(
            workspacePath: "macos/Runner.xcworkspace",
            currentDirectory: tmp.path
        )

        #expect(detected.type == .flutter)
        #expect(detected.rootPath == tmp.path)
        #expect(detected.containerPath == tmp.appendingPathComponent("macos/Runner.xcworkspace").path)
        #expect(detected.packageResolvedPath == macResolved.path)
    }

    @Test("Prioritizes .xcworkspace over .xcodeproj and ignores inner project.xcworkspace")
    func prioritizesWorkspaceOverXcodeproj() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let proj = tmp.appendingPathComponent("SampleApp.xcodeproj")
        let innerWorkspace = proj.appendingPathComponent("project.xcworkspace/xcshareddata/swiftpm")
        try FileManager.default.createDirectory(at: innerWorkspace, withIntermediateDirectories: true)
        let innerResolved = innerWorkspace.appendingPathComponent("Package.resolved")
        try "{}".write(to: innerResolved, atomically: true, encoding: .utf8)

        let workspace = tmp.appendingPathComponent("SampleApp.xcworkspace")
        let wsSwiftPM = workspace.appendingPathComponent("xcshareddata/swiftpm")
        try FileManager.default.createDirectory(at: wsSwiftPM, withIntermediateDirectories: true)
        let wsResolved = wsSwiftPM.appendingPathComponent("Package.resolved")
        try "{}".write(to: wsResolved, atomically: true, encoding: .utf8)

        let detected = try ProjectDetector.detect(in: tmp.path)
        #expect(detected.type == .xcode)
        #expect(detected.containerPath == workspace.path)
        #expect(detected.packageResolvedPath == wsResolved.path)
        #expect(detected.allPackageResolvedPaths == [wsResolved.path, innerResolved.path])

        // Also ensure passing project.xcworkspace directly normalizes to the .xcodeproj
        let explicitInner = try ProjectDetector.detect(
            workspacePath: innerWorkspace.deletingLastPathComponent().deletingLastPathComponent().path
        )
        #expect(explicitInner.containerPath == proj.path)
        #expect(explicitInner.packageResolvedPath == innerResolved.path)
    }

    @Test("Detects .xcodeproj only and locates project.xcworkspace Package.resolved")
    func detectsXcodeprojOnly() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let proj = tmp.appendingPathComponent("SoloApp.xcodeproj")
        let resolved = proj.appendingPathComponent("project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        try FileManager.default.createDirectory(at: resolved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{}".write(to: resolved, atomically: true, encoding: .utf8)

        let detected = try ProjectDetector.detect(in: tmp.path)
        #expect(detected.type == .xcode)
        #expect(detected.rootPath == tmp.path)
        #expect(detected.containerPath == proj.path)
        #expect(detected.packageResolvedPath == resolved.path)
    }

    @Test("Detects pure SwiftPM package and root Package.resolved")
    func detectsPureSwiftPM() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let manifest = tmp.appendingPathComponent("Package.swift")
        let resolved = tmp.appendingPathComponent("Package.resolved")
        try "// swift-tools-version: 6.0\n".write(to: manifest, atomically: true, encoding: .utf8)
        try "{}".write(to: resolved, atomically: true, encoding: .utf8)

        let detected = try ProjectDetector.detect(in: tmp.path)
        #expect(detected.type == .swiftPackage)
        #expect(detected.rootPath == tmp.path)
        #expect(detected.containerPath == nil)
        #expect(detected.packageManifestPath == manifest.path)
        #expect(detected.packageResolvedPath == resolved.path)
        #expect(detected.flutterInfo == nil)

        // Explicit --project pointing to Package.swift
        let byManifest = try ProjectDetector.detect(projectPath: manifest.path)
        #expect(byManifest == detected)
    }

    @Test("Throws clear errors for missing or empty project directories")
    func throwsErrorsForInvalidDirectories() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        #expect(throws: ProjectDetectionError.projectNotFound(tmp.path)) {
            _ = try ProjectDetector.detect(in: tmp.path)
        }

        // pubspec.yaml without ios/ or macos/ containers should not falsely match Flutter
        try "name: pure_dart_cli\n".write(
            to: tmp.appendingPathComponent("pubspec.yaml"),
            atomically: true,
            encoding: .utf8
        )
        #expect(throws: ProjectDetectionError.projectNotFound(tmp.path)) {
            _ = try ProjectDetector.detect(in: tmp.path)
        }

        let missingPath = tmp.appendingPathComponent("DoesNotExist").path
        #expect(throws: ProjectDetectionError.directoryNotFound(missingPath)) {
            _ = try ProjectDetector.detect(in: missingPath)
        }

        #expect(throws: ProjectDetectionError.explicitPathNotFound(missingPath)) {
            _ = try ProjectDetector.detect(projectPath: missingPath)
        }
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pspm-detector-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

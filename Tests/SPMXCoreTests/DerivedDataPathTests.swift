import Foundation
import Testing
@testable import SPMXCore

@Suite("DerivedDataPathCalculator")
struct DerivedDataPathTests {
    @Test("Matches known Xcode MD5 + base-26 hash vector")
    func knownHashVector() {
        let path = "/var/folders/q5/30t4gyk51s78kzcd03yxwpfw0000gn/T/tmp.xTGKdfbLJy/SampleApp.xcodeproj"
        let hash = DerivedDataPathCalculator.hash(forCanonicalPath: path)
        #expect(hash == "cxlxsqxaanqbsseaqbsmgqxfzqqp")
        #expect(hash.count == 28)
        #expect(hash.allSatisfy { $0 >= "a" && $0 <= "z" })
    }

    @Test("Strips trailing slash and normalizes relative path")
    func canonicalizesPaths() {
        let withSlash = DerivedDataPathCalculator.canonicalizePath("/Users/dev/App/App.xcworkspace/")
        let withoutSlash = DerivedDataPathCalculator.canonicalizePath("/Users/dev/App/App.xcworkspace")
        #expect(withSlash == withoutSlash)
        #expect(DerivedDataPathCalculator.hash(forCanonicalPath: withSlash) == DerivedDataPathCalculator.hash(forCanonicalPath: withoutSlash))

        let relative = DerivedDataPathCalculator.canonicalizePath(
            "./ios/../ios/Runner.xcworkspace/",
            currentDirectory: "/Users/dev/flutter_app"
        )
        #expect(relative == "/Users/dev/flutter_app/ios/Runner.xcworkspace")
    }

    @Test("Honors custom IDECustomDerivedDataLocation")
    func honorsCustomXcodeDefaultLocation() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let project = tmp.appendingPathComponent("MyApp.xcodeproj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        let customBase = tmp.appendingPathComponent("CustomXcodeDD").path
        let result = DerivedDataPathCalculator.derivedDataURL(
            forContainerPath: project.path,
            customXcodeLocation: customBase
        )

        let expectedHash = DerivedDataPathCalculator.hash(forCanonicalPath: project.path)
        #expect(result.path == "\(customBase)/MyApp-\(expectedHash)")
    }

    @Test("Honors WorkspaceSettings.xcsettings DerivedDataLocation and CustomLocation")
    func honorsWorkspaceSettings() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let workspace = tmp.appendingPathComponent("App.xcworkspace")
        let sharedData = workspace.appendingPathComponent("xcshareddata")
        try FileManager.default.createDirectory(at: sharedData, withIntermediateDirectories: true)

        let settingsURL = sharedData.appendingPathComponent("WorkspaceSettings.xcsettings")
        let plist: [String: Any] = [
            "DerivedDataLocationStyle": "WorkspaceRelativePath",
            "DerivedDataCustomLocation": "LocalDerivedData"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: settingsURL)

        let resolved = DerivedDataPathCalculator.derivedDataURL(
            forContainerPath: workspace.path,
            customXcodeLocation: "/tmp/should-not-win"
        )
        let expectedHash = DerivedDataPathCalculator.hash(forCanonicalPath: workspace.path)
        #expect(resolved.path == tmp.appendingPathComponent("LocalDerivedData/App-\(expectedHash)").path)

        // Also test explicit `DerivedDataLocation` key
        let explicitPlist: [String: Any] = ["DerivedDataLocation": "/tmp/ExplicitDD"]
        let explicitData = try PropertyListSerialization.data(fromPropertyList: explicitPlist, format: .xml, options: 0)
        try explicitData.write(to: settingsURL)

        let resolvedExplicit = DerivedDataPathCalculator.derivedDataURL(forContainerPath: workspace.path)
        #expect(resolvedExplicit.path == "/tmp/ExplicitDD/App-\(expectedHash)")
    }

    @Test("Resolves workspace before xcodeproj and detects Flutter ios/macos containers")
    func resolvesContainersInDirectories() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let nativeDir = tmp.appendingPathComponent("native")
        try FileManager.default.createDirectory(at: nativeDir.appendingPathComponent("Foo.xcodeproj"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nativeDir.appendingPathComponent("Foo.xcworkspace"), withIntermediateDirectories: true)

        let resolvedNative = try DerivedDataPathCalculator.resolveContainerPath(from: nativeDir.path)
        #expect(resolvedNative == nativeDir.appendingPathComponent("Foo.xcworkspace").path)

        let flutterDir = tmp.appendingPathComponent("flutter_app")
        try FileManager.default.createDirectory(at: flutterDir.appendingPathComponent("ios/Runner.xcworkspace"), withIntermediateDirectories: true)
        let resolvedFlutter = try DerivedDataPathCalculator.resolveContainerPath(from: flutterDir.path)
        #expect(resolvedFlutter == flutterDir.appendingPathComponent("ios/Runner.xcworkspace").path)
    }

    @Test("Integration: matches real xcodebuild -showBuildSettings BUILD_DIR")
    func matchesRealXcodebuild() throws {
        let xcodebuildPath = "/usr/bin/xcodebuild"
        guard FileManager.default.isExecutableFile(atPath: xcodebuildPath) else {
            return
        }

        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let projectURL = tmp.appendingPathComponent("IntegrationApp.xcodeproj")
        let schemesDir = projectURL.appendingPathComponent("xcshareddata/xcschemes")
        try FileManager.default.createDirectory(at: schemesDir, withIntermediateDirectories: true)

        let pbxproj = """
        // !$*UTF8*$!
        {
            archiveVersion = 1; classes = {}; objectVersion = 56;
            objects = {
                111111111111111111111111 = { isa = PBXGroup; children = (); sourceTree = "<group>"; };
                222222222222222222222222 = { isa = XCBuildConfiguration; buildSettings = { PRODUCT_NAME = "$(TARGET_NAME)"; }; name = Debug; };
                333333333333333333333333 = { isa = XCConfigurationList; buildConfigurations = (222222222222222222222222); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };
                444444444444444444444444 = { isa = PBXNativeTarget; buildConfigurationList = 333333333333333333333333; buildPhases = (); buildRules = (); dependencies = (); name = IntegrationApp; productName = IntegrationApp; productType = "com.apple.product-type.application"; };
                555555555555555555555555 = { isa = PBXProject; attributes = { LastUpgradeCheck = 1500; }; buildConfigurationList = 333333333333333333333333; compatibilityVersion = "Xcode 14.0"; mainGroup = 111111111111111111111111; projectDirPath = ""; projectRoot = ""; targets = (444444444444444444444444); };
            };
            rootObject = 555555555555555555555555;
        }
        """
        try pbxproj.write(to: projectURL.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8)

        let scheme = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Scheme LastUpgradeVersion = "1500" version = "1.7">
           <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
              <BuildActionEntries>
                 <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
                    <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "444444444444444444444444" BuildableName = "IntegrationApp.app" BlueprintName = "IntegrationApp" ReferencedContainer = "container:IntegrationApp.xcodeproj"></BuildableReference>
                 </BuildActionEntry>
              </BuildActionEntries>
           </BuildAction>
        </Scheme>
        """
        try scheme.write(to: schemesDir.appendingPathComponent("IntegrationApp.xcscheme"), atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: xcodebuildPath)
        process.arguments = ["-project", projectURL.path, "-scheme", "IntegrationApp", "-showBuildSettings"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        let buildDirLine = output
            .split(separator: "\n")
            .first { $0.contains(" BUILD_DIR = ") }
        let rawBuildDir = try #require(buildDirLine?
            .split(separator: "=", maxSplits: 1)
            .last?
            .trimmingCharacters(in: .whitespaces))

        // BUILD_DIR is <DerivedData>/<Name>-<hash>/Build/Products
        let xcodeDerivedDataRoot = URL(fileURLWithPath: rawBuildDir)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path

        let calculated = DerivedDataPathCalculator.derivedDataURL(forContainerPath: projectURL.path).path
        #expect(calculated == xcodeDerivedDataRoot)
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spmx-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

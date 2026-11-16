import Foundation
import Testing
@testable import SPMXCore

@Suite("WorkspaceStateParser")
struct WorkspaceStateParserTests {
    private static let sampleWorkspaceStateJSON = """
    {
      "object" : {
        "artifacts" : [
          {
            "kind" : {
              "xcframework" : {

              }
            },
            "packageRef" : {
              "identity" : "firebase-ios-sdk",
              "kind" : "remoteSourceControl",
              "location" : "https://github.com/firebase/firebase-ios-sdk.git",
              "name" : "Firebase"
            },
            "path" : "/Users/dev/Library/Developer/Xcode/DerivedData/Runner-aaaaaaaaaaaaaaaaaaaaaaaaaaaa/SourcePackages/artifacts/firebase-ios-sdk/FirebaseAnalytics/FirebaseAnalytics.xcframework",
            "source" : {
              "checksum" : "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
              "type" : "remote",
              "url" : "https://dl.google.com/firebase/ios/swiftpm/11.4.0/FirebaseAnalytics.zip"
            },
            "targetName" : "FirebaseAnalytics",
            "unknownArtifactMetadata" : {
              "preserved" : true,
              "count" : 42
            }
          },
          {
            "kind" : "xcframework",
            "packageRef" : {
              "identity" : "local-sdk",
              "kind" : "localSourceControl",
              "location" : "/Users/dev/src/LocalSDK",
              "name" : "LocalSDK"
            },
            "path" : "/Users/dev/Library/Developer/Xcode/DerivedData/Runner-aaaaaaaaaaaaaaaaaaaaaaaaaaaa/SourcePackages/artifacts/local-sdk/LocalBinary/LocalBinary.xcframework",
            "source" : {
              "type" : "local"
            },
            "targetName" : "LocalBinary"
          }
        ],
        "dependencies" : [
          {
            "basedOn" : null,
            "packageRef" : {
              "identity" : "firebase-ios-sdk",
              "kind" : "remoteSourceControl",
              "location" : "https://github.com/firebase/firebase-ios-sdk.git",
              "name" : "Firebase"
            },
            "state" : {
              "checkoutState" : {
                "revision" : "f9b6f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0",
                "version" : "11.4.0"
              },
              "name" : "sourceControlCheckout"
            },
            "subpath" : "firebase-ios-sdk"
          },
          {
            "basedOn" : null,
            "packageRef" : {
              "identity" : "swift-syntax",
              "kind" : "remoteSourceControl",
              "location" : "https://github.com/swiftlang/swift-syntax.git",
              "name" : "swift-syntax"
            },
            "state" : {
              "checkoutState" : {
                "revision" : "0687bfdc7645e9f482b6f6fb45183578a5d8e5f1",
                "version" : "600.0.1"
              },
              "name" : "sourceControlCheckout"
            },
            "subpath" : "swift-syntax"
          }
        ],
        "prebuilts" : [
          {
            "cModules" : [
              "_SwiftSyntaxCShims"
            ],
            "checksum" : "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
            "checkoutState" : {
              "revision" : "0687bfdc7645e9f482b6f6fb45183578a5d8e5f1",
              "version" : "600.0.1"
            },
            "identity" : "swift-syntax",
            "includePath" : [
              "/Users/dev/Library/Developer/Xcode/DerivedData/Runner-aaaaaaaaaaaaaaaaaaaaaaaaaaaa/SourcePackages/checkouts/swift-syntax/Sources/_SwiftSyntaxCShims/include"
            ],
            "libraryName" : "libSwiftSyntaxPrebuilt.dylib",
            "path" : "/Users/dev/Library/Developer/Xcode/DerivedData/Runner-aaaaaaaaaaaaaaaaaaaaaaaaaaaa/SourcePackages/prebuilts/swift-syntax/600.0.1/swiftlang-600",
            "products" : [
              "SwiftSyntax",
              "SwiftSyntaxMacros"
            ],
            "unknownPrebuiltFlag" : "keep-me"
          }
        ],
        "unknownObjectKey" : "preserved-value"
      },
      "version" : 7
    }
    """

    @Test("Parses dependencies, artifacts, and prebuilts from workspace-state.json")
    func parsesWorkspaceState() throws {
        let data = Data(Self.sampleWorkspaceStateJSON.utf8)
        let state = try WorkspaceStateParser.parse(data: data)

        #expect(state.version == 7)
        #expect(state.dependencies.count == 2)
        #expect(state.dependencies[0].packageRef.identity == "firebase-ios-sdk")
        #expect(state.dependencies[0].state.name == "sourceControlCheckout")
        #expect(state.dependencies[0].state.checkoutState?.version == "11.4.0")
        #expect(state.dependencies[0].subpath == "firebase-ios-sdk")

        #expect(state.artifacts.count == 2)
        let firebaseArtifact = state.artifacts[0]
        #expect(firebaseArtifact.packageRef.identity == "firebase-ios-sdk")
        #expect(firebaseArtifact.targetName == "FirebaseAnalytics")
        #expect(firebaseArtifact.kind == "xcframework")
        #expect(firebaseArtifact.checksum == "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
        #expect(firebaseArtifact.source == .remote(
            url: "https://dl.google.com/firebase/ios/swiftpm/11.4.0/FirebaseAnalytics.zip",
            checksum: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
        ))
        #expect(firebaseArtifact.path.hasSuffix("/SourcePackages/artifacts/firebase-ios-sdk/FirebaseAnalytics/FirebaseAnalytics.xcframework"))

        let localArtifact = state.artifacts[1]
        #expect(localArtifact.source == .local(checksum: nil))
        #expect(localArtifact.checksum == nil)

        #expect(state.prebuilts.count == 1)
        let prebuilt = state.prebuilts[0]
        #expect(prebuilt.identity == "swift-syntax")
        #expect(prebuilt.version == "600.0.1")
        #expect(prebuilt.checksum == "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
        #expect(prebuilt.libraryName == "libSwiftSyntaxPrebuilt.dylib")
        #expect(prebuilt.products == ["SwiftSyntax", "SwiftSyntaxMacros"])
        #expect(prebuilt.cModules == ["_SwiftSyntaxCShims"])
        #expect(prebuilt.includePaths == [
            "/Users/dev/Library/Developer/Xcode/DerivedData/Runner-aaaaaaaaaaaaaaaaaaaaaaaaaaaa/SourcePackages/checkouts/swift-syntax/Sources/_SwiftSyntaxCShims/include"
        ])
        #expect(prebuilt.path == "/Users/dev/Library/Developer/Xcode/DerivedData/Runner-aaaaaaaaaaaaaaaaaaaaaaaaaaaa/SourcePackages/prebuilts/swift-syntax/600.0.1/swiftlang-600")
    }

    @Test("Rewrites artifact and prebuilt paths using explicit oldRoot while preserving unknown fields")
    func rewritesPathsWithExplicitOldRoot() throws {
        let oldRoot = "/Users/dev/Library/Developer/Xcode/DerivedData/Runner-aaaaaaaaaaaaaaaaaaaaaaaaaaaa/SourcePackages"
        let newRoot = "/Users/dev/Library/Developer/Xcode/DerivedData/Runner-bbbbbbbbbbbbbbbbbbbbbbbbbbbb/SourcePackages"

        let rewrittenData = try WorkspaceStateParser.rewritingPaths(
            in: Data(Self.sampleWorkspaceStateJSON.utf8),
            toNewSourcePackagesPath: newRoot,
            replacingOldSourcePackagesPath: oldRoot
        )

        let reparsed = try WorkspaceStateParser.parse(data: rewrittenData)
        #expect(reparsed.artifacts[0].path == "\(newRoot)/artifacts/firebase-ios-sdk/FirebaseAnalytics/FirebaseAnalytics.xcframework")
        #expect(reparsed.artifacts[1].path == "\(newRoot)/artifacts/local-sdk/LocalBinary/LocalBinary.xcframework")
        #expect(reparsed.prebuilts[0].path == "\(newRoot)/prebuilts/swift-syntax/600.0.1/swiftlang-600")
        #expect(reparsed.prebuilts[0].includePaths == [
            "\(newRoot)/checkouts/swift-syntax/Sources/_SwiftSyntaxCShims/include"
        ])

        // Verify remote URLs and local dependency location outside SourcePackages were untouched,
        // and unknown fields were losslessly preserved.
        #expect(reparsed.artifacts[0].source == .remote(
            url: "https://dl.google.com/firebase/ios/swiftpm/11.4.0/FirebaseAnalytics.zip",
            checksum: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
        ))
        #expect(reparsed.artifacts[1].packageRef.location == "/Users/dev/src/LocalSDK")

        let rawJSON = try #require(try JSONSerialization.jsonObject(with: rewrittenData) as? [String: Any])
        let object = try #require(rawJSON["object"] as? [String: Any])
        #expect(object["unknownObjectKey"] as? String == "preserved-value")

        let artifacts = try #require(object["artifacts"] as? [[String: Any]])
        let unknownMeta = try #require(artifacts[0]["unknownArtifactMetadata"] as? [String: Any])
        #expect(unknownMeta["preserved"] as? Bool == true)
        #expect(unknownMeta["count"] as? Int == 42)

        let prebuilts = try #require(object["prebuilts"] as? [[String: Any]])
        #expect(prebuilts[0]["unknownPrebuiltFlag"] as? String == "keep-me")
    }

    @Test("Automatically anchors and rewrites paths without oldRoot across SourcePackages and .build")
    func rewritesPathsWithInferredAnchor() throws {
        let targetBuildDir = "/Users/dev/worktree-b/.build"

        let rewrittenData = try WorkspaceStateParser.rewritingPaths(
            in: Data(Self.sampleWorkspaceStateJSON.utf8),
            toNewSourcePackagesPath: targetBuildDir
        )

        let reparsed = try WorkspaceStateParser.parse(data: rewrittenData)
        #expect(reparsed.artifacts[0].path == "\(targetBuildDir)/artifacts/firebase-ios-sdk/FirebaseAnalytics/FirebaseAnalytics.xcframework")
        #expect(reparsed.prebuilts[0].path == "\(targetBuildDir)/prebuilts/swift-syntax/600.0.1/swiftlang-600")
        #expect(reparsed.prebuilts[0].includePaths == [
            "\(targetBuildDir)/checkouts/swift-syntax/Sources/_SwiftSyntaxCShims/include"
        ])
    }

    @Test("Rewrites workspace-state.json file on disk")
    func rewritesFileOnDisk() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("spmx-ws-state-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sourceFile = tmp.appendingPathComponent("workspace-state.json")
        let destFile = tmp.appendingPathComponent("workspace-state-rewritten.json")
        try Self.sampleWorkspaceStateJSON.write(to: sourceFile, atomically: true, encoding: .utf8)

        let newRoot = tmp.appendingPathComponent("SourcePackages").path
        try WorkspaceStateParser.rewritePaths(
            inFileAt: sourceFile.path,
            writingTo: destFile.path,
            toNewSourcePackagesPath: newRoot
        )

        let reparsed = try WorkspaceStateParser.parse(fileAt: destFile.path)
        #expect(reparsed.artifacts[0].path == "\(newRoot)/artifacts/firebase-ios-sdk/FirebaseAnalytics/FirebaseAnalytics.xcframework")
        #expect(reparsed.prebuilts[0].path == "\(newRoot)/prebuilts/swift-syntax/600.0.1/swiftlang-600")
    }

    @Test("Throws clear errors for missing or malformed workspace-state.json")
    func throwsErrorsForInvalidInputs() {
        #expect(throws: WorkspaceStateError.fileNotFound("/nonexistent/workspace-state.json")) {
            _ = try WorkspaceStateParser.parse(fileAt: "/nonexistent/workspace-state.json")
        }

        let missingObject = #"{"version": 7}"#
        #expect(throws: WorkspaceStateError.invalidFormat("Missing 'object' dictionary.")) {
            _ = try WorkspaceStateParser.parse(data: Data(missingObject.utf8))
        }
    }
}

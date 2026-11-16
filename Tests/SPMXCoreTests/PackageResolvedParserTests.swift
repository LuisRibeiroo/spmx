import Foundation
import Testing
@testable import SPMXCore

@Suite("PackageResolvedParser")
struct PackageResolvedParserTests {
    @Test("Parses Package.resolved v1 and derives lowercase identities")
    func parsesV1Schema() throws {
        let json = """
        {
          "object": {
            "pins": [
              {
                "package": "Alamofire",
                "repositoryURL": "https://github.com/Alamofire/Alamofire.git",
                "state": {
                  "branch": null,
                  "revision": "f455c2975872ccd2d9c81594c658af65716e9b9a",
                  "version": "5.9.1"
                }
              },
              {
                "package": "SDWebImage",
                "repositoryURL": "git@github.com:SDWebImage/SDWebImage.git",
                "state": {
                  "branch": "master",
                  "revision": "0123456789abcdef0123456789abcdef01234567",
                  "version": null
                }
              },
              {
                "package": "LocalHelpers",
                "repositoryURL": "file:///Users/dev/Packages/LocalHelpers/",
                "state": {
                  "branch": "main",
                  "revision": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                  "version": null
                }
              },
              {
                "package": "FallbackPkg",
                "repositoryURL": "https://example.com",
                "state": {
                  "branch": null,
                  "revision": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                  "version": "1.0.0"
                }
              }
            ]
          },
          "version": 1
        }
        """

        let resolved = try PackageResolvedParser.parse(data: Data(json.utf8))
        #expect(resolved.version == 1)
        #expect(resolved.originHash == nil)
        #expect(resolved.pins.count == 4)

        #expect(resolved.pins[0] == PackagePin(
            identity: "alamofire",
            kind: .remoteSourceControl,
            location: "https://github.com/Alamofire/Alamofire.git",
            revision: "f455c2975872ccd2d9c81594c658af65716e9b9a",
            version: "5.9.1",
            branch: nil,
            packageName: "Alamofire"
        ))

        #expect(resolved.pins[1].identity == "sdwebimage")
        #expect(resolved.pins[1].kind == .remoteSourceControl)
        #expect(resolved.pins[1].branch == "master")
        #expect(resolved.pins[1].version == nil)

        #expect(resolved.pins[2].identity == "localhelpers")
        #expect(resolved.pins[2].kind == .localSourceControl)

        #expect(resolved.pins[3].identity == "fallbackpkg")
        #expect(resolved.pins[3].packageName == "FallbackPkg")
    }

    @Test("Parses Package.resolved v2 with remoteSourceControl, registry, and localSourceControl pins")
    func parsesV2Schema() throws {
        let json = """
        {
          "pins" : [
            {
              "identity" : "firebase-ios-sdk",
              "kind" : "remoteSourceControl",
              "location" : "https://github.com/firebase/firebase-ios-sdk.git",
              "state" : {
                "revision" : "f9b6f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0",
                "version" : "11.4.0"
              }
            },
            {
              "identity" : "apple.swift-log",
              "kind" : "registry",
              "location" : "",
              "state" : {
                "version" : "1.6.1"
              }
            },
            {
              "identity" : "shared-kit",
              "kind" : "localSourceControl",
              "location" : "/Users/dev/src/SharedKit",
              "state" : {
                "branch" : "develop",
                "revision" : "1111222233334444555566667777888899990000"
              }
            }
          ],
          "version" : 2
        }
        """

        let resolved = try PackageResolvedParser.parse(data: Data(json.utf8))
        #expect(resolved.version == 2)
        #expect(resolved.originHash == nil)
        #expect(resolved.pins.count == 3)

        #expect(resolved.pins[0].identity == "firebase-ios-sdk")
        #expect(resolved.pins[0].kind == .remoteSourceControl)
        #expect(resolved.pins[0].version == "11.4.0")
        #expect(resolved.pins[0].revision == "f9b6f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0")

        #expect(resolved.pins[1].identity == "apple.swift-log")
        #expect(resolved.pins[1].kind == .registry)
        #expect(resolved.pins[1].location == "")
        #expect(resolved.pins[1].revision == nil)
        #expect(resolved.pins[1].version == "1.6.1")

        #expect(resolved.pins[2].identity == "shared-kit")
        #expect(resolved.pins[2].kind == .localSourceControl)
        #expect(resolved.pins[2].location == "/Users/dev/src/SharedKit")
        #expect(resolved.pins[2].branch == "develop")
    }

    @Test("Parses Package.resolved v3 with originHash from disk")
    func parsesV3SchemaFromDisk() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("spmx-resolved-v3-\(UUID().uuidString).resolved")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let json = """
        {
          "originHash" : "e18414a7417dde61b0695bdd63b9530ba98d6101eb19644c1fc97beed51205cb",
          "pins" : [
            {
              "identity" : "swift-argument-parser",
              "kind" : "remoteSourceControl",
              "location" : "https://github.com/apple/swift-argument-parser.git",
              "state" : {
                "revision" : "6a52f3251125d74daf04fcbd5e6f08a75d074382",
                "version" : "1.8.2"
              }
            },
            {
              "identity" : "swift-syntax",
              "kind" : "remoteSourceControl",
              "location" : "https://github.com/swiftlang/swift-syntax.git",
              "state" : {
                "revision" : "0687bfdc7645e9f482b6f6fb45183578a5d8e5f1",
                "version" : "600.0.1"
              }
            }
          ],
          "version" : 3
        }
        """
        try json.write(to: tmp, atomically: true, encoding: .utf8)

        let resolved = try PackageResolvedParser.parse(fileAt: tmp.path)
        #expect(resolved.version == 3)
        #expect(resolved.originHash == "e18414a7417dde61b0695bdd63b9530ba98d6101eb19644c1fc97beed51205cb")
        #expect(resolved.pins.count == 2)
        #expect(resolved.pins[0].identity == "swift-argument-parser")
        #expect(resolved.pins[1].identity == "swift-syntax")
        #expect(resolved.pins[1].version == "600.0.1")
    }

    @Test("Derives identities cleanly across URL variants")
    func derivesIdentitiesAcrossURLFormats() {
        #expect(
            PackageResolvedParser.deriveIdentity(fromLocation: "https://github.com/apple/swift-nio.git")
                == "swift-nio"
        )
        #expect(
            PackageResolvedParser.deriveIdentity(fromLocation: "https://github.com/Alamofire/Alamofire/")
                == "alamofire"
        )
        #expect(
            PackageResolvedParser.deriveIdentity(fromLocation: "git@github.com:MyOrg/MySDK.git")
                == "mysdk"
        )
        #expect(
            PackageResolvedParser.deriveIdentity(fromLocation: "git@internal.host:SoloRepo.git")
                == "solorepo"
        )
        #expect(
            PackageResolvedParser.deriveIdentity(fromLocation: "", fallbackPackageName: "CustomPkg")
                == "custompkg"
        )
    }

    @Test("Rejects unsupported versions, malformed JSON, and missing files")
    func rejectsInvalidInputs() {
        let unsupported = #"{"version": 99, "pins": []}"#
        #expect(throws: PackageResolvedError.unsupportedVersion(99)) {
            _ = try PackageResolvedParser.parse(data: Data(unsupported.utf8))
        }

        let malformed = "{ not json"
        #expect(throws: PackageResolvedError.self) {
            _ = try PackageResolvedParser.parse(data: Data(malformed.utf8))
        }

        #expect(throws: PackageResolvedError.fileNotFound("/nonexistent/Package.resolved")) {
            _ = try PackageResolvedParser.parse(fileAt: "/nonexistent/Package.resolved")
        }
    }
}

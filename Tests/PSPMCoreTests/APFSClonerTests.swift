import Darwin
import Foundation
import Testing
@testable import PSPMCore

private final class LockedArray<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Element] = []

    func append(_ element: Element) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(element)
    }

    var values: [Element] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@Suite("APFSCloner")
struct APFSClonerTests {
    @Test("Clones directory tree via clonefile with Copy-on-Write isolation")
    func clonesDirectoryTreeWithCopyOnWriteIndependence() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let source = tmp.appendingPathComponent("source-pkg")
        let nestedDir = source.appendingPathComponent("Sources/MyLib")
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)

        let sourceFile = nestedDir.appendingPathComponent("MyLib.swift")
        let readmeFile = source.appendingPathComponent("README.md")
        try "public let version = 1\n".write(to: sourceFile, atomically: true, encoding: .utf8)
        try "# MyLib\n".write(to: readmeFile, atomically: true, encoding: .utf8)

        let destination = tmp.appendingPathComponent("worktree/SourcePackages/checkouts/source-pkg")
        let cloner = APFSCloner()
        let outcome = try cloner.clone(from: source, to: destination)

        if APFSCloner.isAPFS(at: tmp) {
            #expect(outcome.method == .apfsClone)
        }
        #expect(outcome.destinationURL.path == destination.standardizedFileURL.path)

        let clonedFile = destination.appendingPathComponent("Sources/MyLib/MyLib.swift")
        let clonedReadme = destination.appendingPathComponent("README.md")
        #expect(try String(contentsOf: clonedFile, encoding: .utf8) == "public let version = 1\n")
        #expect(try String(contentsOf: clonedReadme, encoding: .utf8) == "# MyLib\n")

        // Mutating the cloned file must not affect the source file in the store.
        try "public let version = 2\n".write(to: clonedFile, atomically: true, encoding: .utf8)
        #expect(try String(contentsOf: sourceFile, encoding: .utf8) == "public let version = 1\n")
        #expect(try String(contentsOf: clonedFile, encoding: .utf8) == "public let version = 2\n")
    }

    @Test("Detects APFS filesystem via statfs including non-existent child paths")
    func detectsAPFSOnTempDirectory() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let fsName = APFSCloner.fileSystemTypeName(at: tmp)
        #expect(fsName != nil)

        let nonExistentChild = tmp.appendingPathComponent("does/not/exist/yet")
        #expect(APFSCloner.fileSystemTypeName(at: nonExistentChild) == fsName)
        #expect(APFSCloner.isAPFS(at: nonExistentChild) == (fsName?.lowercased() == "apfs"))
    }

    @Test("Falls back to FileManager.copyItem on ENOTSUP and logs verbose warning")
    func fallsBackOnENOTSUP() throws {
        try assertFallback(simulatedErrno: ENOTSUP)
    }

    @Test("Falls back to FileManager.copyItem on EXDEV and logs verbose warning")
    func fallsBackOnEXDEV() throws {
        try assertFallback(simulatedErrno: EXDEV)
    }

    @Test("Throws cloneFailed without falling back on non-recoverable errno")
    func throwsOnNonFallbackErrno() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let source = tmp.appendingPathComponent("src.txt")
        try "hello".write(to: source, atomically: true, encoding: .utf8)

        let destParent = tmp.appendingPathComponent("out")
        let destination = destParent.appendingPathComponent("dst.txt")

        let logs = LockedArray<String>()
        let cloner = APFSCloner(
            cloneSyscall: { _, _, _ in
                Darwin.errno = EACCES
                return -1
            },
            verboseLogger: { logs.append($0) }
        )

        #expect(throws: APFSClonerError.self) {
            try cloner.clone(from: source, to: destination)
        }
        #expect(logs.values.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: destination.path))

        let entries = (try? FileManager.default.contentsOfDirectory(atPath: destParent.path)) ?? []
        #expect(entries.isEmpty)
    }

    @Test("Atomic staging prevents partial destinations and respects overwrite flag")
    func atomicStagingAndOverwriteBehavior() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sourceV1 = tmp.appendingPathComponent("pkg-v1")
        let sourceV2 = tmp.appendingPathComponent("pkg-v2")
        try FileManager.default.createDirectory(at: sourceV1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceV2, withIntermediateDirectories: true)
        try "v1".write(to: sourceV1.appendingPathComponent("VERSION"), atomically: true, encoding: .utf8)
        try "v2".write(to: sourceV2.appendingPathComponent("VERSION"), atomically: true, encoding: .utf8)

        let destParent = tmp.appendingPathComponent("dest")
        let destination = destParent.appendingPathComponent("pkg")

        let cloner = APFSCloner()
        _ = try cloner.clone(from: sourceV1, to: destination, overwrite: false)
        #expect(try String(contentsOf: destination.appendingPathComponent("VERSION"), encoding: .utf8) == "v1")

        // Without overwrite, destinationAlreadyExists is thrown and existing contents stay intact.
        #expect(throws: APFSClonerError.destinationAlreadyExists(destination.standardizedFileURL.path)) {
            try cloner.clone(from: sourceV2, to: destination, overwrite: false)
        }
        #expect(try String(contentsOf: destination.appendingPathComponent("VERSION"), encoding: .utf8) == "v1")

        // With overwrite: true, destination is atomically replaced.
        _ = try cloner.clone(from: sourceV2, to: destination, overwrite: true)
        #expect(try String(contentsOf: destination.appendingPathComponent("VERSION"), encoding: .utf8) == "v2")

        // If staging fails during overwrite, the existing destination remains intact and no temp files remain.
        let failingCloner = APFSCloner(cloneSyscall: { _, _, _ in
            Darwin.errno = EIO
            return -1
        })
        #expect(throws: APFSClonerError.self) {
            try failingCloner.clone(from: sourceV1, to: destination, overwrite: true)
        }
        #expect(try String(contentsOf: destination.appendingPathComponent("VERSION"), encoding: .utf8) == "v2")

        let parentEntries = try FileManager.default.contentsOfDirectory(atPath: destParent.path)
        #expect(parentEntries == ["pkg"])
    }

    // MARK: - Helpers

    private func assertFallback(simulatedErrno: Int32) throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let source = tmp.appendingPathComponent("artifact.xcframework")
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("ios-arm64"),
            withIntermediateDirectories: true
        )
        try "binary-plist".write(
            to: source.appendingPathComponent("Info.plist"),
            atomically: true,
            encoding: .utf8
        )

        let destination = tmp.appendingPathComponent("dest/artifact.xcframework")
        let logs = LockedArray<String>()
        let cloner = APFSCloner(
            cloneSyscall: { _, _, _ in
                Darwin.errno = simulatedErrno
                return -1
            },
            verboseLogger: { logs.append($0) }
        )

        let outcome = try cloner.clone(from: source, to: destination)
        #expect(outcome.method == .fallbackCopy)
        #expect(try String(contentsOf: destination.appendingPathComponent("Info.plist"), encoding: .utf8) == "binary-plist")
        #expect(logs.values.count == 1)
        #expect(logs.values[0].contains("FileManager.copyItem"))
        #expect(logs.values[0].contains("errno \(simulatedErrno)"))

        let parentEntries = try FileManager.default.contentsOfDirectory(
            atPath: destination.deletingLastPathComponent().path
        )
        #expect(parentEntries == ["artifact.xcframework"])
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pspm-cloner-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

import Darwin
import Foundation

@_silgen_name("statfs")
private func posixStatfs(_ path: UnsafePointer<CChar>, _ buf: UnsafeMutablePointer<statfs>) -> Int32

/// Errors thrown by ``APFSCloner`` during APFS cloning or fallback copying.
public enum APFSClonerError: Error, LocalizedError, Equatable, Sendable {
    case sourceNotFound(String)
    case destinationAlreadyExists(String)
    case cloneFailed(source: String, destination: String, errno: Int32, message: String)
    case stagingFailed(source: String, destination: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .sourceNotFound(let path):
            return "Source path does not exist: '\(path)'."
        case .destinationAlreadyExists(let path):
            return "Destination path already exists: '\(path)'."
        case .cloneFailed(let source, let destination, let code, let message):
            return "Failed to clone '\(source)' to '\(destination)' (errno \(code): \(message))."
        case .stagingFailed(let source, let destination, let message):
            return "Failed to atomically stage '\(source)' to '\(destination)': \(message)."
        }
    }
}

/// Describes how an item was materialized at its destination.
public enum CloneMethod: String, Equatable, Sendable {
    case apfsClone
    case fallbackCopy
}

/// Result returned by ``APFSCloner/clone(from:to:overwrite:)``.
public struct CloneOutcome: Equatable, Sendable {
    public let destinationURL: URL
    public let method: CloneMethod

    public init(destinationURL: URL, method: CloneMethod) {
        self.destinationURL = destinationURL
        self.method = method
    }
}

/// Safe Swift wrapper around Darwin's `clonefile(2)` with atomic staging and automatic
/// fallback to `FileManager.copyItem` on `ENOTSUP` or `EXDEV`.
public struct APFSCloner: Sendable {
    /// Signature matching Darwin's `clonefile(const char *, const char *, uint32_t)`.
    /// Implementations should return `0` on success, or `-1` with `errno` set (or a positive errno value) on failure.
    public typealias CloneSyscall = @Sendable (_ sourcePath: String, _ destinationPath: String, _ flags: UInt32) -> Int32

    /// Callback invoked with diagnostic messages when falling back from `clonefile` to `copyItem`.
    public typealias VerboseLogger = @Sendable (String) -> Void

    private let cloneSyscall: CloneSyscall
    private let verboseLogger: VerboseLogger?

    public init(
        cloneSyscall: @escaping CloneSyscall = APFSCloner.defaultCloneSyscall,
        verboseLogger: VerboseLogger? = nil
    ) {
        self.cloneSyscall = cloneSyscall
        self.verboseLogger = verboseLogger
    }

    /// Default syscall implementation calling `<sys/clonefile.h>` `clonefile(src, dst, flags)`.
    public static let defaultCloneSyscall: CloneSyscall = { sourcePath, destinationPath, flags in
        Darwin.clonefile(sourcePath, destinationPath, flags)
    }

    /// Clones a file or directory tree from `sourceURL` to `destinationURL`.
    ///
    /// Materializes into a hidden temporary path inside `destinationURL`'s parent directory,
    /// then atomically moves or replaces the destination so partial clones are never exposed.
    /// Falls back to `FileManager.copyItem` when `clonefile` fails with `ENOTSUP` or `EXDEV`.
    @discardableResult
    public func clone(
        from sourceURL: URL,
        to destinationURL: URL,
        overwrite: Bool = false
    ) throws -> CloneOutcome {
        let fileManager = FileManager.default
        let source = sourceURL.standardizedFileURL
        let destination = destinationURL.standardizedFileURL

        guard Self.itemExists(at: source) else {
            throw APFSClonerError.sourceNotFound(source.path)
        }

        if Self.itemExists(at: destination) && !overwrite {
            throw APFSClonerError.destinationAlreadyExists(destination.path)
        }

        let parentDirectory = destination.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        } catch {
            throw APFSClonerError.stagingFailed(
                source: source.path,
                destination: destination.path,
                message: error.localizedDescription
            )
        }

        let stagingURL = parentDirectory.appendingPathComponent(
            ".\(destination.lastPathComponent).pspm-tmp-\(UUID().uuidString)"
        )
        defer {
            if Self.itemExists(at: stagingURL) {
                try? fileManager.removeItem(at: stagingURL)
            }
        }

        let method = try materializeToStaging(source: source, staging: stagingURL, destination: destination)
        try commitStaging(staging: stagingURL, to: destination, overwrite: overwrite, source: source)

        return CloneOutcome(destinationURL: destination, method: method)
    }

    /// Returns the filesystem type name (e.g. `"apfs"`, `"hfs"`) for the volume containing `url`.
    public static func fileSystemTypeName(at url: URL) -> String? {
        var candidatePath = url.standardizedFileURL.path
        let fileManager = FileManager.default

        while !fileManager.fileExists(atPath: candidatePath) {
            let parent = (candidatePath as NSString).deletingLastPathComponent
            if parent.isEmpty || parent == candidatePath {
                break
            }
            candidatePath = parent
        }

        var stats = statfs()
        guard posixStatfs(candidatePath, &stats) == 0 else {
            return nil
        }

        return withUnsafePointer(to: &stats.f_fstypename) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { cString in
                String(cString: cString)
            }
        }
    }

    /// Checks via `statfs(2)` whether `url` (or its nearest existing ancestor) resides on APFS.
    public static func isAPFS(at url: URL) -> Bool {
        fileSystemTypeName(at: url)?.lowercased() == "apfs"
    }

    // MARK: - Private Helpers

    private func materializeToStaging(
        source: URL,
        staging: URL,
        destination: URL
    ) throws -> CloneMethod {
        let rc = cloneSyscall(source.path, staging.path, 0)
        if rc == 0 {
            return .apfsClone
        }

        let errorCode: Int32 = rc == -1 ? Darwin.errno : rc
        if errorCode == ENOTSUP || errorCode == EXDEV {
            let reason = String(cString: Darwin.strerror(errorCode))
            verboseLogger?(
                "APFS clonefile unavailable (errno \(errorCode): \(reason)); falling back to FileManager.copyItem for '\(source.path)' -> '\(destination.path)'."
            )

            // Ensure staging path is clean before fallback copy.
            if Self.itemExists(at: staging) {
                try? FileManager.default.removeItem(at: staging)
            }

            do {
                try FileManager.default.copyItem(at: source, to: staging)
            } catch {
                throw APFSClonerError.stagingFailed(
                    source: source.path,
                    destination: destination.path,
                    message: error.localizedDescription
                )
            }
            return .fallbackCopy
        }

        throw APFSClonerError.cloneFailed(
            source: source.path,
            destination: destination.path,
            errno: errorCode,
            message: String(cString: Darwin.strerror(errorCode))
        )
    }

    private func commitStaging(
        staging: URL,
        to destination: URL,
        overwrite: Bool,
        source: URL
    ) throws {
        let fileManager = FileManager.default

        if !Self.itemExists(at: destination) {
            do {
                try fileManager.moveItem(at: staging, to: destination)
                return
            } catch {
                if !overwrite {
                    throw APFSClonerError.stagingFailed(
                        source: source.path,
                        destination: destination.path,
                        message: error.localizedDescription
                    )
                }
                // Fall through to replacement if destination appeared concurrently and overwrite is true.
            }
        }

        guard overwrite else {
            throw APFSClonerError.destinationAlreadyExists(destination.path)
        }

        do {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
        } catch {
            // Fallback replacement when item types differ (e.g., symlink vs directory).
            let backupURL = destination.deletingLastPathComponent().appendingPathComponent(
                ".\(destination.lastPathComponent).pspm-bak-\(UUID().uuidString)"
            )
            do {
                try fileManager.moveItem(at: destination, to: backupURL)
                do {
                    try fileManager.moveItem(at: staging, to: destination)
                    try? fileManager.removeItem(at: backupURL)
                } catch {
                    try? fileManager.moveItem(at: backupURL, to: destination)
                    throw error
                }
            } catch {
                throw APFSClonerError.stagingFailed(
                    source: source.path,
                    destination: destination.path,
                    message: error.localizedDescription
                )
            }
        }
    }

    private static func itemExists(at url: URL) -> Bool {
        var st = stat()
        return Darwin.lstat(url.path, &st) == 0
    }
}

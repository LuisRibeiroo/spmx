import CryptoKit
import Foundation

public enum DerivedDataError: Error, LocalizedError, Equatable {
    case containerNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .containerNotFound(let path):
            return "No .xcworkspace or .xcodeproj found at '\(path)'."
        }
    }
}

/// Computes deterministic Xcode DerivedData paths using Xcode's MD5 + base-26 algorithm.
public struct DerivedDataPathCalculator: Sendable {
    private static let base26Alphabet: [Character] = Array("abcdefghijklmnopqrstuvwxyz")
    private static let customXcodeKey = "IDECustomDerivedDataLocation"
    private static let xcodeDomain = "com.apple.dt.Xcode"

    public init() {}

    /// Canonicalizes a path to an absolute standardized form without trailing slashes
    /// and without resolving `/var` -> `/private/var`, matching `xcodebuild` hashing.
    public static func canonicalizePath(
        _ path: String,
        currentDirectory: String = FileManager.default.currentDirectoryPath
    ) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let url: URL
        if expanded.hasPrefix("/") {
            url = URL(fileURLWithPath: expanded)
        } else {
            url = URL(fileURLWithPath: currentDirectory).appendingPathComponent(expanded)
        }
        var standardized = url.standardized.path
        while standardized.count > 1 && standardized.hasSuffix("/") {
            standardized.removeLast()
        }
        return standardized
    }

    /// Computes Xcode's 28-character lowercase base-26 suffix from the MD5 digest
    /// of the UTF-8 bytes of the canonical `.xcworkspace`/`.xcodeproj` path.
    public static func hash(forCanonicalPath canonicalPath: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(canonicalPath.utf8))
        let bytes = Array(digest)
        let high = readUInt64BigEndian(bytes[0..<8])
        let low = readUInt64BigEndian(bytes[8..<16])
        return encodeBase26(high, length: 14) + encodeBase26(low, length: 14)
    }

    /// Computes Xcode's 28-character suffix for any path (canonicalizing it first).
    public static func hash(
        forPath path: String,
        currentDirectory: String = FileManager.default.currentDirectoryPath
    ) -> String {
        hash(forCanonicalPath: canonicalizePath(path, currentDirectory: currentDirectory))
    }

    /// Extracts the sanitized DerivedData folder prefix for a `.xcworkspace` or `.xcodeproj`.
    public static func folderPrefix(forContainerPath containerPath: String) -> String {
        let name = URL(fileURLWithPath: containerPath).deletingPathExtension().lastPathComponent
        return name.replacingOccurrences(of: " ", with: "_")
    }

    /// Resolves the base DerivedData directory, honoring `WorkspaceSettings.xcsettings`,
    /// `IDECustomDerivedDataLocation` in `com.apple.dt.Xcode`, and falling back to
    /// `~/Library/Developer/Xcode/DerivedData`.
    public static func resolveBaseDerivedDataDirectory(
        forContainerPath containerPath: String,
        customXcodeLocation: String? = nil,
        fileManager: FileManager = .default,
        username: String = NSUserName()
    ) -> URL {
        let canonical = canonicalizePath(containerPath)
        let containerURL = URL(fileURLWithPath: canonical)
        let workspaceParent = containerURL.deletingLastPathComponent()

        if let workspaceCustom = readWorkspaceSettingsLocation(
            for: containerURL,
            workspaceParent: workspaceParent,
            username: username,
            fileManager: fileManager
        ) {
            return workspaceCustom
        }

        let resolvedCustomLocation = customXcodeLocation
            ?? UserDefaults(suiteName: xcodeDomain)?.string(forKey: customXcodeKey)
        if let resolvedCustomLocation,
           !resolvedCustomLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded = (resolvedCustomLocation as NSString).expandingTildeInPath
            if expanded.hasPrefix("/") {
                return URL(fileURLWithPath: expanded).standardized
            }
            return workspaceParent.appendingPathComponent(expanded).standardized
        }

        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Developer")
            .appendingPathComponent("Xcode")
            .appendingPathComponent("DerivedData")
    }

    /// Computes the full DerivedData directory URL (`<base>/<Name>-<28_chars>`) for a
    /// `.xcworkspace` or `.xcodeproj` path.
    public static func derivedDataURL(
        forContainerPath containerPath: String,
        currentDirectory: String = FileManager.default.currentDirectoryPath,
        customXcodeLocation: String? = nil,
        fileManager: FileManager = .default,
        username: String = NSUserName()
    ) -> URL {
        let canonical = canonicalizePath(containerPath, currentDirectory: currentDirectory)
        let base = resolveBaseDerivedDataDirectory(
            forContainerPath: canonical,
            customXcodeLocation: customXcodeLocation,
            fileManager: fileManager,
            username: username
        )
        let prefix = folderPrefix(forContainerPath: canonical)
        let suffix = hash(forCanonicalPath: canonical)
        return base.appendingPathComponent("\(prefix)-\(suffix)")
    }

    /// Resolves a user-supplied path (either a `.xcworkspace`/`.xcodeproj` or a directory
    /// containing one, including Flutter `ios/` or `macos/` roots) to the target container path.
    public static func resolveContainerPath(
        from inputPath: String,
        currentDirectory: String = FileManager.default.currentDirectoryPath,
        fileManager: FileManager = .default
    ) throws -> String {
        let canonical = canonicalizePath(inputPath, currentDirectory: currentDirectory)
        let url = URL(fileURLWithPath: canonical)

        if canonical.hasSuffix(".xcworkspace") || canonical.hasSuffix(".xcodeproj") {
            guard fileManager.fileExists(atPath: canonical) else {
                throw DerivedDataError.containerNotFound(canonical)
            }
            return canonical
        }

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: canonical, isDirectory: &isDir), isDir.boolValue else {
            throw DerivedDataError.containerNotFound(canonical)
        }

        if let found = findContainer(in: url, fileManager: fileManager) {
            return found
        }

        // Check Flutter standard subdirectories (`ios/Runner.xcworkspace`, `macos/Runner.xcworkspace`).
        let flutterCandidates = [
            url.appendingPathComponent("ios"),
            url.appendingPathComponent("macos")
        ]
        for dir in flutterCandidates {
            if let found = findContainer(in: dir, fileManager: fileManager) {
                return found
            }
        }

        throw DerivedDataError.containerNotFound(canonical)
    }

    // MARK: - Private Helpers

    private static func findContainer(in directory: URL, fileManager: FileManager) -> String? {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let sorted = entries.sorted { $0.lastPathComponent < $1.lastPathComponent }
        if let workspace = sorted.first(where: { $0.pathExtension == "xcworkspace" }) {
            return directory.appendingPathComponent(workspace.lastPathComponent).standardized.path
        }
        if let project = sorted.first(where: { $0.pathExtension == "xcodeproj" }) {
            return directory.appendingPathComponent(project.lastPathComponent).standardized.path
        }
        return nil
    }

    private static func readWorkspaceSettingsLocation(
        for containerURL: URL,
        workspaceParent: URL,
        username: String,
        fileManager: FileManager
    ) -> URL? {
        let candidateSettings: [URL]
        if containerURL.pathExtension == "xcodeproj" {
            let innerWorkspace = containerURL.appendingPathComponent("project.xcworkspace")
            candidateSettings = [
                innerWorkspace
                    .appendingPathComponent("xcuserdata")
                    .appendingPathComponent("\(username).xcuserdatad")
                    .appendingPathComponent("WorkspaceSettings.xcsettings"),
                innerWorkspace
                    .appendingPathComponent("xcshareddata")
                    .appendingPathComponent("WorkspaceSettings.xcsettings"),
                containerURL
                    .appendingPathComponent("xcuserdata")
                    .appendingPathComponent("\(username).xcuserdatad")
                    .appendingPathComponent("WorkspaceSettings.xcsettings"),
                containerURL
                    .appendingPathComponent("xcshareddata")
                    .appendingPathComponent("WorkspaceSettings.xcsettings")
            ]
        } else {
            candidateSettings = [
                containerURL
                    .appendingPathComponent("xcuserdata")
                    .appendingPathComponent("\(username).xcuserdatad")
                    .appendingPathComponent("WorkspaceSettings.xcsettings"),
                containerURL
                    .appendingPathComponent("xcshareddata")
                    .appendingPathComponent("WorkspaceSettings.xcsettings")
            ]
        }

        for settingsURL in candidateSettings {
            guard fileManager.fileExists(atPath: settingsURL.path),
                  let data = try? Data(contentsOf: settingsURL),
                  let plist = try? PropertyListSerialization.propertyList(
                      from: data,
                      options: [],
                      format: nil
                  ) as? [String: Any]
            else {
                continue
            }

            // Explicit `DerivedDataLocation` key when present.
            if let explicit = plist["DerivedDataLocation"] as? String,
               !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return resolveLocationString(explicit, relativeTo: workspaceParent)
            }

            // Standard Xcode keys: `DerivedDataLocationStyle` + `DerivedDataCustomLocation`.
            let style = plist["DerivedDataLocationStyle"] as? String ?? "Default"
            if style != "Default",
               let custom = plist["DerivedDataCustomLocation"] as? String,
               !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return resolveLocationString(custom, relativeTo: workspaceParent)
            }
        }

        return nil
    }

    private static func resolveLocationString(_ value: String, relativeTo base: URL) -> URL {
        let expanded = (value as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardized
        }
        return base.appendingPathComponent(expanded).standardized
    }

    private static func readUInt64BigEndian(_ slice: ArraySlice<UInt8>) -> UInt64 {
        var value: UInt64 = 0
        for byte in slice {
            value = (value << 8) | UInt64(byte)
        }
        return value
    }

    private static func encodeBase26(_ value: UInt64, length: Int) -> String {
        var remaining = value
        var chars = [Character](repeating: "a", count: length)
        for index in stride(from: length - 1, through: 0, by: -1) {
            chars[index] = base26Alphabet[Int(remaining % 26)]
            remaining /= 26
        }
        return String(chars)
    }
}

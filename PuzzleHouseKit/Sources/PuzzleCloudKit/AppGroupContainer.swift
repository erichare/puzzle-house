import Foundation

/// Resolves a writable directory shared by the main app, Share Extension, and
/// iMessage app. Production code passes the real App Group identifier; tests
/// pass a tmp directory.
public struct AppGroupContainer: Sendable {
    public let baseURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    /// Production initializer — looks up the App Group container by identifier.
    /// Returns `nil` if the entitlement isn't present (e.g. in test/CLI runs).
    public init?(appGroupIdentifier: String) {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else { return nil }
        self.init(baseURL: url)
    }

    public func subdirectory(_ path: String) -> URL {
        let url = baseURL.appendingPathComponent(path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

import Foundation
import CloudKit

/// Persists per-zone CKServerChangeTokens to disk so reopening the app doesn't
/// trigger a full zone refetch. One file per (user, zone) pair, keyed by zone
/// owner + zone name.
///
/// Tokens are opaque to us — we round-trip them via `NSKeyedArchiver` /
/// `NSKeyedUnarchiver`.
public final class ChangeTokenStore: @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()

    public init(container: AppGroupContainer) {
        self.directory = container.subdirectory("change-tokens")
    }

    public func token(for zoneID: CKRecordZone.ID) -> CKServerChangeToken? {
        lock.lock(); defer { lock.unlock() }
        let url = fileURL(for: zoneID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: CKServerChangeToken.self, from: data
        )
    }

    public func save(_ token: CKServerChangeToken, for zoneID: CKRecordZone.ID) throws {
        lock.lock(); defer { lock.unlock() }
        let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        try data.write(to: fileURL(for: zoneID), options: .atomic)
    }

    public func clear(_ zoneID: CKRecordZone.ID) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL(for: zoneID))
    }

    public func clearAll() {
        lock.lock(); defer { lock.unlock() }
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in contents { try? FileManager.default.removeItem(at: url) }
    }

    private func fileURL(for zoneID: CKRecordZone.ID) -> URL {
        let owner = zoneID.ownerName.replacingOccurrences(of: "/", with: "_")
        let name = zoneID.zoneName.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent("\(owner)__\(name).token")
    }
}

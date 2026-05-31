import Foundation
import PuzzleCore

/// Local, all-time cache of a household's `PuzzleResult`s, persisted as JSON in
/// the App Group container (one file per household). Seeded by a one-time
/// CloudKit backfill and kept current by folding in each load's recent window,
/// so charts, achievements, and member profiles can read full history without
/// re-fetching everything on every launch.
///
/// Mirrors `WidgetSnapshotStore`: an `@unchecked Sendable` class guarded by a
/// lock, encoding/decoding leniently so a schema addition never crashes a read.
public final class ResultArchiveStore: @unchecked Sendable {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()

    public init(container: AppGroupContainer) {
        self.directory = container.subdirectory("results-archive")
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    public func read(householdID: String) -> [PuzzleResult] {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL(householdID)) else { return [] }
        return (try? decoder.decode([PuzzleResult].self, from: data)) ?? []
    }

    public func write(_ results: [PuzzleResult], householdID: String) {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? encoder.encode(results) else { return }
        try? data.write(to: fileURL(householdID), options: .atomic)
    }

    public func clear(householdID: String) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL(householdID))
    }

    private func fileURL(_ householdID: String) -> URL {
        // Household IDs are CloudKit zone names ([A-Za-z0-9_.-]); sanitize
        // defensively so the value is always a safe single path component.
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-")
        let safe = String(householdID.unicodeScalars.map {
            allowed.contains($0) ? Character($0) : "_"
        })
        return directory.appendingPathComponent("\(safe).json")
    }
}

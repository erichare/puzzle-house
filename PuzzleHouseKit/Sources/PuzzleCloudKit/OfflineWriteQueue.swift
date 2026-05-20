import Foundation
import PuzzleCore

/// Append-only queue of `PuzzleResult`s waiting to sync to CloudKit. Used by
/// the Share Extension (which often runs without network) and by the main app
/// after intermittent failures. Each entry is one JSON file so writes are
/// crash-safe and entries can be processed independently.
public final class OfflineWriteQueue: @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(container: AppGroupContainer) {
        self.directory = container.subdirectory("pending-results")
        self.encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    @discardableResult
    public func enqueue(_ result: PuzzleResult) throws -> URL {
        lock.lock(); defer { lock.unlock() }
        let url = directory.appendingPathComponent("\(result.id).json")
        let data = try encoder.encode(result)
        try data.write(to: url, options: .atomic)
        return url
    }

    public func pending() throws -> [PuzzleResult] {
        lock.lock(); defer { lock.unlock() }
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        )
        var results: [(Date, PuzzleResult)] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let result = try? decoder.decode(PuzzleResult.self, from: data) else { continue }
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            results.append((modified, result))
        }
        return results.sorted { $0.0 < $1.0 }.map(\.1)
    }

    public func remove(_ id: PuzzleResult.ID) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(id).json"))
    }

    public func count() throws -> Int {
        lock.lock(); defer { lock.unlock() }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return files.filter { $0.pathExtension == "json" }.count
    }
}

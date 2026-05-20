import Foundation
import PuzzleCore

/// What the home-screen widget reads from the App Group container. Encoded
/// as JSON at `<appGroup>/widget-snapshot.json` whenever the main app
/// refreshes household data. Schema additions are append-only and decoded
/// leniently so an old widget binary doesn't crash on a new app build.
public struct WidgetSnapshot: Hashable, Sendable, Codable {
    public struct Entry: Hashable, Sendable, Codable {
        public let userID: String
        public let displayName: String
        public let avatarEmoji: String
        public let combinedScore: Double
        public let gamesPlayed: Int

        public init(
            userID: String,
            displayName: String,
            avatarEmoji: String,
            combinedScore: Double,
            gamesPlayed: Int
        ) {
            self.userID = userID
            self.displayName = displayName
            self.avatarEmoji = avatarEmoji
            self.combinedScore = combinedScore
            self.gamesPlayed = gamesPlayed
        }
    }

    public let updatedAt: Date
    public let householdName: String
    public let householdIcon: String
    public let dayISO: String
    public let houseStreak: Int
    public let entries: [Entry]

    public init(
        updatedAt: Date,
        householdName: String,
        householdIcon: String,
        dayISO: String,
        houseStreak: Int,
        entries: [Entry]
    ) {
        self.updatedAt = updatedAt
        self.householdName = householdName
        self.householdIcon = householdIcon
        self.dayISO = dayISO
        self.houseStreak = houseStreak
        self.entries = entries
    }
}

public final class WidgetSnapshotStore: @unchecked Sendable {
    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()

    public init(container: AppGroupContainer) {
        self.url = container.baseURL.appendingPathComponent("widget-snapshot.json")
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    public func read() -> WidgetSnapshot? {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    public func write(_ snapshot: WidgetSnapshot) {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: url)
    }
}

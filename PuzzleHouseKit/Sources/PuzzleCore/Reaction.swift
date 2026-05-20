import Foundation

public struct Reaction: Hashable, Sendable, Codable, Identifiable {
    public typealias ID = String

    public let id: ID
    public let targetResultID: PuzzleResult.ID
    public let authorUserID: String
    public let emoji: String
    public let createdAt: Date

    public init(
        id: ID = UUID().uuidString,
        targetResultID: PuzzleResult.ID,
        authorUserID: String,
        emoji: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.targetResultID = targetResultID
        self.authorUserID = authorUserID
        self.emoji = emoji
        self.createdAt = createdAt
    }
}

public extension Reaction {
    /// Deterministic record ID: one reaction per (target, author).
    /// Different emojis from the same author collapse onto the same record,
    /// so re-reacting replaces the prior choice.
    static func deterministicID(targetResultID: PuzzleResult.ID, authorUserID: String) -> ID {
        let userToken = String(authorUserID.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" })
            .prefix(40)
        return "rx-\(targetResultID)-\(userToken)"
    }
}

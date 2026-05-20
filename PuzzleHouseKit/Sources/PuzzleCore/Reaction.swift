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

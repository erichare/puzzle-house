import Foundation

/// Transient output of a parser. Becomes a `PuzzleResult` once associated with
/// a household and an author.
public struct ParsedResult: Hashable, Sendable, Codable {
    public let gameID: String
    public let puzzleNumber: Int
    public let puzzleDate: Date?
    public let rawScore: RawScore
    public let gridData: String?
    public let metadata: [String: String]

    public init(
        gameID: String,
        puzzleNumber: Int,
        puzzleDate: Date? = nil,
        rawScore: RawScore,
        gridData: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.gameID = gameID
        self.puzzleNumber = puzzleNumber
        self.puzzleDate = puzzleDate
        self.rawScore = rawScore
        self.gridData = gridData
        self.metadata = metadata
    }
}

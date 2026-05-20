import Foundation

public struct PuzzleResult: Hashable, Sendable, Codable, Identifiable {
    public typealias ID = String

    public let id: ID
    public let householdID: Household.ID
    public let authorUserID: String
    public let gameID: String
    public let puzzleNumber: Int
    public let puzzleDay: PuzzleDay
    public let rawScore: RawScore
    public let rawPayload: String
    public let gridData: String?
    public let submittedAt: Date

    public init(
        id: ID = UUID().uuidString,
        householdID: Household.ID,
        authorUserID: String,
        gameID: String,
        puzzleNumber: Int,
        puzzleDay: PuzzleDay,
        rawScore: RawScore,
        rawPayload: String,
        gridData: String? = nil,
        submittedAt: Date = Date()
    ) {
        self.id = id
        self.householdID = householdID
        self.authorUserID = authorUserID
        self.gameID = gameID
        self.puzzleNumber = puzzleNumber
        self.puzzleDay = puzzleDay
        self.rawScore = rawScore
        self.rawPayload = rawPayload
        self.gridData = gridData
        self.submittedAt = submittedAt
    }
}

public extension PuzzleResult {
    /// Deterministic record ID. Two submissions of the same puzzle by the
    /// same author collapse onto the same CloudKit record so they overwrite
    /// each other instead of accumulating duplicates.
    static func deterministicID(
        authorUserID: String,
        gameID: String,
        puzzleNumber: Int
    ) -> ID {
        // CloudKit record names must be <= 255 chars and use only
        // [A-Za-z0-9_.-]. Hash the user ID to stay short and safe.
        let userToken = String(authorUserID.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" })
            .prefix(40)
        let safeGame = gameID
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        return "r-\(userToken)-\(safeGame)-\(puzzleNumber)"
    }

    /// Build a PuzzleResult from a parser output plus the household/author context
    /// only known at submit time.
    init(
        parsed: ParsedResult,
        householdID: Household.ID,
        authorUserID: String,
        rawPayload: String,
        timeZone: TimeZone,
        submittedAt: Date = Date()
    ) {
        let day = parsed.puzzleDate.map { PuzzleDay(date: $0, timeZone: timeZone) }
            ?? PuzzleDay(date: submittedAt, timeZone: timeZone)
        self.init(
            id: PuzzleResult.deterministicID(
                authorUserID: authorUserID,
                gameID: parsed.gameID,
                puzzleNumber: parsed.puzzleNumber
            ),
            householdID: householdID,
            authorUserID: authorUserID,
            gameID: parsed.gameID,
            puzzleNumber: parsed.puzzleNumber,
            puzzleDay: day,
            rawScore: parsed.rawScore,
            rawPayload: rawPayload,
            gridData: parsed.gridData,
            submittedAt: submittedAt
        )
    }
}

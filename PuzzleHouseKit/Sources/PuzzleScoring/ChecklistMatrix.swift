import Foundation
import PuzzleCore

public enum CompletionState: Sendable, Equatable, Hashable {
    case solved
    case failed
    case notPlayed
}

public struct ChecklistRow: Sendable, Equatable, Hashable {
    public let gameID: String
    public let perMember: [(userID: String, state: CompletionState)]

    public init(gameID: String, perMember: [(userID: String, state: CompletionState)]) {
        self.gameID = gameID
        self.perMember = perMember
    }

    public static func == (lhs: ChecklistRow, rhs: ChecklistRow) -> Bool {
        lhs.gameID == rhs.gameID
            && lhs.perMember.elementsEqual(rhs.perMember) { $0.userID == $1.userID && $0.state == $1.state }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(gameID)
        for entry in perMember {
            hasher.combine(entry.userID)
            hasher.combine(entry.state)
        }
    }

    public var solvedCount: Int { perMember.filter { $0.state == .solved }.count }
    public var totalCount: Int { perMember.count }
}

public enum ChecklistMatrix {
    /// Builds a per-game checklist of who's done each game on a given day.
    /// Games that nobody played still appear if they're in `tracked` — that's
    /// the point, to see incompleteness.
    public static func build(
        results: [PuzzleResult],
        memberUserIDs: [String],
        tracked: [String],
        day: PuzzleDay
    ) -> [ChecklistRow] {
        let dayResults = results.filter { $0.puzzleDay == day }
        let allGames = Array(Set(tracked).union(dayResults.map(\.gameID)))
            .sorted { lhs, rhs in
                // Tracked order first, then alphabetical for the rest.
                switch (tracked.firstIndex(of: lhs), tracked.firstIndex(of: rhs)) {
                case (let l?, let r?): return l < r
                case (_?, nil):        return true
                case (nil, _?):        return false
                case (nil, nil):       return lhs < rhs
                }
            }

        return allGames.map { gameID in
            let entries: [(String, CompletionState)] = memberUserIDs.map { uid in
                let mine = dayResults.first(where: { $0.gameID == gameID && $0.authorUserID == uid })
                let state: CompletionState
                if let mine {
                    state = mine.rawScore.solved ? .solved : .failed
                } else {
                    state = .notPlayed
                }
                return (uid, state)
            }
            return ChecklistRow(gameID: gameID, perMember: entries)
        }
    }
}

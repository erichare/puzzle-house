import Foundation
import PuzzleCore

/// All-time personal records for one member.
public struct PersonalRecords: Sendable, Equatable {
    public let totalSolved: Int
    public let totalPlayed: Int
    public let bestWordleGuesses: Int?
    public let bestConnectionsMistakes: Int?
    public let activeDays: Int

    public var solveRate: Double { totalPlayed == 0 ? 0 : Double(totalSolved) / Double(totalPlayed) }

    public init(
        totalSolved: Int,
        totalPlayed: Int,
        bestWordleGuesses: Int?,
        bestConnectionsMistakes: Int?,
        activeDays: Int
    ) {
        self.totalSolved = totalSolved
        self.totalPlayed = totalPlayed
        self.bestWordleGuesses = bestWordleGuesses
        self.bestConnectionsMistakes = bestConnectionsMistakes
        self.activeDays = activeDays
    }
}

/// Head-to-head record between a viewer and an opponent, comparing the better
/// `goodness` on each puzzle both played.
public struct HeadToHead: Sendable, Equatable {
    public let opponentID: String
    public let wins: Int
    public let losses: Int
    public let ties: Int

    public var total: Int { wins + losses + ties }

    public init(opponentID: String, wins: Int, losses: Int, ties: Int) {
        self.opponentID = opponentID
        self.wins = wins
        self.losses = losses
        self.ties = ties
    }
}

/// One day of activity for the contribution-style streak timeline.
public struct ActivityDay: Sendable, Equatable, Identifiable {
    public let day: PuzzleDay
    public let gamesPlayed: Int

    public var id: Int64 { day.epoch }

    public init(day: PuzzleDay, gamesPlayed: Int) {
        self.day = day
        self.gamesPlayed = gamesPlayed
    }
}

/// Pure all-time profile derivations (records, head-to-head, activity timeline).
/// SwiftUI-free and testable, like the rest of `PuzzleScoring`.
public enum MemberProfileStats {

    public static func records(results: [PuzzleResult], userID: String) -> PersonalRecords {
        let mine = results.filter { $0.authorUserID == userID }
        let bestWordle = mine
            .filter { $0.gameID == "wordle" }
            .compactMap { r -> Int? in
                if case .guesses(let used, _, let solved) = r.rawScore, solved { return used }
                return nil
            }
            .min()
        let bestConnections = mine
            .filter { $0.gameID == "connections" }
            .compactMap { r -> Int? in
                if case .mistakes(let count, _, let solved) = r.rawScore, solved { return count }
                return nil
            }
            .min()
        return PersonalRecords(
            totalSolved: mine.filter { $0.rawScore.solved }.count,
            totalPlayed: mine.count,
            bestWordleGuesses: bestWordle,
            bestConnectionsMistakes: bestConnections,
            activeDays: Set(mine.map(\.puzzleDay)).count
        )
    }

    public static func headToHead(
        results: [PuzzleResult],
        viewer: String,
        opponent: String
    ) -> HeadToHead {
        func byPuzzle(_ uid: String) -> [String: Double] {
            var best: [String: Double] = [:]
            for r in results where r.authorUserID == uid {
                let key = "\(r.gameID)|\(r.puzzleNumber)"
                best[key] = max(best[key] ?? -.infinity, r.rawScore.goodness)
            }
            return best
        }
        let mine = byPuzzle(viewer)
        let theirs = byPuzzle(opponent)
        var wins = 0, losses = 0, ties = 0
        for (key, myScore) in mine {
            guard let theirScore = theirs[key] else { continue }
            if myScore > theirScore { wins += 1 }
            else if myScore < theirScore { losses += 1 }
            else { ties += 1 }
        }
        return HeadToHead(opponentID: opponent, wins: wins, losses: losses, ties: ties)
    }

    /// Per-day game counts for the last `days` days ending at `today`, including
    /// zero-activity days so the timeline has a continuous run of cells.
    public static func activityTimeline(
        results: [PuzzleResult],
        userID: String,
        today: PuzzleDay,
        days: Int = 28
    ) -> [ActivityDay] {
        let mine = results.filter { $0.authorUserID == userID }
        let countsByDay = Dictionary(grouping: mine, by: \.puzzleDay)
            .mapValues { Set($0.map(\.gameID)).count }
        return (0..<days).reversed().map { offset in
            let day = today.advanced(by: -offset)
            return ActivityDay(day: day, gamesPlayed: countsByDay[day] ?? 0)
        }
    }
}

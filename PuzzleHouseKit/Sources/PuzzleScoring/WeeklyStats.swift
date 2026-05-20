import Foundation
import PuzzleCore

public struct WeeklyStats: Sendable, Equatable {
    public struct PerMember: Sendable, Equatable {
        public let userID: String
        public let daysPlayed: Int
        public let championships: Int       // days they topped the combined score
        public let totalSolved: Int
        public let longestStreak: Int       // longest single-game streak in the window
    }

    public let windowDays: Int
    public let totalResults: Int
    public let totalDaysPlayed: Int         // how many days had any result
    public let perMember: [PerMember]
}

public enum WeeklyStatsCalculator {

    public static func compute(
        results: [PuzzleResult],
        memberUserIDs: [String],
        today: PuzzleDay,
        windowDays: Int = 7
    ) -> WeeklyStats {
        let earliest = today.advanced(by: -(windowDays - 1))
        let inWindow = results.filter { $0.puzzleDay >= earliest && $0.puzzleDay <= today }
        let daysSet = Set(inWindow.map(\.puzzleDay))

        // Build per-day leaderboards to count championships.
        var champs: [String: Int] = [:]
        for day in daysSet {
            let board = CombinedScore.leaderboard(inWindow, day: day)
            if let top = board.first {
                champs[top.userID, default: 0] += 1
            }
        }

        // Build per-member stats.
        let perMember: [WeeklyStats.PerMember] = memberUserIDs.map { uid in
            let mine = inWindow.filter { $0.authorUserID == uid }
            let daysPlayed = Set(mine.map(\.puzzleDay)).count
            let totalSolved = mine.filter { $0.rawScore.solved }.count
            let longest = longestStreakAcrossGames(
                results: inWindow, userID: uid, today: today
            )
            return WeeklyStats.PerMember(
                userID: uid,
                daysPlayed: daysPlayed,
                championships: champs[uid] ?? 0,
                totalSolved: totalSolved,
                longestStreak: longest
            )
        }
        .sorted { $0.championships > $1.championships }

        return WeeklyStats(
            windowDays: windowDays,
            totalResults: inWindow.count,
            totalDaysPlayed: daysSet.count,
            perMember: perMember
        )
    }

    /// Longest *any-game* streak this user achieved within the window — best
    /// across all games they played.
    private static func longestStreakAcrossGames(
        results: [PuzzleResult],
        userID: String,
        today: PuzzleDay
    ) -> Int {
        let games = Set(results.filter { $0.authorUserID == userID }.map(\.gameID))
        var best = 0
        for game in games {
            let s = StreakCalculator.gameStreak(
                results: results, gameID: game, userID: userID, today: today
            )
            best = max(best, s)
        }
        return best
    }
}

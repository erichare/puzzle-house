import Foundation
import PuzzleCore

public struct PlayerDailyScore: Hashable, Sendable, Codable {
    public let userID: String
    public let day: PuzzleDay
    public let perGame: [String: Double]   // gameID -> z-score
    public let breadthBonus: Double
    public let combined: Double

    public init(
        userID: String,
        day: PuzzleDay,
        perGame: [String: Double],
        breadthBonus: Double,
        combined: Double
    ) {
        self.userID = userID
        self.day = day
        self.perGame = perGame
        self.breadthBonus = breadthBonus
        self.combined = combined
    }
}

public enum CombinedScore {

    /// Bonus weight applied per game played for the breadth term.
    public static let breadthWeight: Double = 0.1

    /// Standard deviation floor so a tied household doesn't explode the z-score.
    public static let stdFloor: Double = 0.5

    /// Computes combined daily scores for one household-day's worth of results.
    /// Returns one entry per (userID, day) pair found in `results`.
    /// Tolerates duplicate (user, game, day) tuples — keeps the best goodness.
    public static func computeDay(
        _ results: [PuzzleResult],
        day: PuzzleDay
    ) -> [PlayerDailyScore] {
        let dayResults = results.filter { $0.puzzleDay == day }
        guard !dayResults.isEmpty else { return [] }

        let byGame = Dictionary(grouping: dayResults, by: \.gameID)
        var goodnessByPlayerGame: [String: [String: Double]] = [:]      // userID -> gameID -> goodness
        var stdByGame: [String: (mean: Double, std: Double)] = [:]

        for (gameID, gameResults) in byGame {
            // Defensive: if the same player has multiple results for this
            // game-day, keep the best score rather than crashing.
            var goodnessByPlayer: [String: Double] = [:]
            for r in gameResults {
                let g = r.rawScore.goodness
                goodnessByPlayer[r.authorUserID] = max(goodnessByPlayer[r.authorUserID] ?? -.infinity, g)
            }
            stdByGame[gameID] = meanAndStd(Array(goodnessByPlayer.values))
            for (uid, g) in goodnessByPlayer {
                goodnessByPlayerGame[uid, default: [:]][gameID] = g
            }
        }

        let players = Set(dayResults.map(\.authorUserID))
        return players.map { uid in
            let perGame = goodnessByPlayerGame[uid] ?? [:]
            var zScores: [String: Double] = [:]
            for (gameID, goodness) in perGame {
                let stats = stdByGame[gameID] ?? (mean: goodness, std: 0)
                let std = max(stats.std, stdFloor)
                zScores[gameID] = (goodness - stats.mean) / std
            }
            let mean = zScores.values.isEmpty ? 0 : zScores.values.reduce(0, +) / Double(zScores.count)
            let bonus = breadthWeight * Double(perGame.count)
            return PlayerDailyScore(
                userID: uid,
                day: day,
                perGame: zScores,
                breadthBonus: bonus,
                combined: mean + bonus
            )
        }
        .sorted { $0.combined > $1.combined }
    }

    /// Convenience: rank a household-day's scores. First element is the champion.
    public static func leaderboard(
        _ results: [PuzzleResult],
        day: PuzzleDay
    ) -> [PlayerDailyScore] {
        computeDay(results, day: day)
    }

    // MARK: - Math

    static func meanAndStd(_ values: [Double]) -> (mean: Double, std: Double) {
        guard !values.isEmpty else { return (0, 0) }
        let mean = values.reduce(0, +) / Double(values.count)
        guard values.count > 1 else { return (mean, 0) }
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return (mean, sqrt(variance))
    }
}

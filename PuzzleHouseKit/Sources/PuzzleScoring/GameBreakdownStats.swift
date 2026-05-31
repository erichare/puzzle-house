import Foundation
import PuzzleCore

/// One bar in a per-game guess/mistake distribution.
public struct DistributionBucket: Sendable, Equatable, Hashable, Identifiable {
    /// Axis label: "1"…"6" guesses, "0"…"4" mistakes/hints, "X" for a fail.
    public let label: String
    public let count: Int
    /// Sort key so charts render left→right; the fail bucket sorts last.
    public let order: Int

    public var id: String { label }

    public init(label: String, count: Int, order: Int) {
        self.label = label
        self.count = count
        self.order = order
    }
}

/// Distribution of how a game was solved, plus a fail ("X") bucket.
public struct GuessDistribution: Sendable, Equatable, Hashable, Identifiable {
    public let gameID: String
    public let buckets: [DistributionBucket]

    public var id: String { gameID }

    public init(gameID: String, buckets: [DistributionBucket]) {
        self.gameID = gameID
        self.buckets = buckets
    }
}

/// Solved-over-played rate for one game.
public struct WinRate: Sendable, Equatable, Hashable, Identifiable {
    public let gameID: String
    public let played: Int
    public let solved: Int

    public var id: String { gameID }
    public var rate: Double { played == 0 ? 0 : Double(solved) / Double(played) }

    public init(gameID: String, played: Int, solved: Int) {
        self.gameID = gameID
        self.played = played
        self.solved = solved
    }
}

/// Everything the per-game breakdown charts need for one game.
public struct GameBreakdown: Sendable, Equatable, Identifiable {
    public let gameID: String
    public let distribution: GuessDistribution
    public let winRate: WinRate

    public var id: String { gameID }

    public init(gameID: String, distribution: GuessDistribution, winRate: WinRate) {
        self.gameID = gameID
        self.distribution = distribution
        self.winRate = winRate
    }
}

/// Derives per-game guess distributions and win rates from results. Pure value
/// computation (like `WeeklyStats` / `StatsHighlights`) so the Stats charts
/// stay testable and SwiftUI-free. Reads all-time `allResults` in practice, but
/// works over any window. Optionally filtered to a single member so the same
/// function powers household-wide charts and per-member profile charts.
public enum GameBreakdownStats {

    public static func compute(
        results: [PuzzleResult],
        userID: String? = nil,
        games: [String] = Game.known.map(\.id)
    ) -> [GameBreakdown] {
        let scoped = userID.map { uid in results.filter { $0.authorUserID == uid } } ?? results
        var out: [GameBreakdown] = []
        for gameID in games {
            let forGame = scoped.filter { $0.gameID == gameID }
            guard !forGame.isEmpty else { continue }
            out.append(GameBreakdown(
                gameID: gameID,
                distribution: distribution(gameID: gameID, results: forGame),
                winRate: WinRate(
                    gameID: gameID,
                    played: forGame.count,
                    solved: forGame.filter { $0.rawScore.solved }.count
                )
            ))
        }
        return out
    }

    private static func distribution(gameID: String, results: [PuzzleResult]) -> GuessDistribution {
        var counts: [Int: Int] = [:]          // order → count (solved buckets)
        var labelByOrder: [Int: String] = [:]
        var fails = 0

        for r in results {
            switch r.rawScore {
            case .guesses(let used, _, let solved):
                if solved { bump(&counts, &labelByOrder, key: used, label: "\(used)") } else { fails += 1 }
            case .mistakes(let count, _, let solved):
                if solved { bump(&counts, &labelByOrder, key: count, label: "\(count)") } else { fails += 1 }
            case .hints(let count, let solved):
                if solved { bump(&counts, &labelByOrder, key: count, label: "\(count)") } else { fails += 1 }
            case .custom(_, let solved):
                if solved { bump(&counts, &labelByOrder, key: 0, label: "Solved") } else { fails += 1 }
            }
        }

        var buckets = counts.keys.sorted().map { key in
            DistributionBucket(label: labelByOrder[key] ?? "\(key)", count: counts[key] ?? 0, order: key)
        }
        if fails > 0 {
            buckets.append(DistributionBucket(label: "X", count: fails, order: .max))
        }
        return GuessDistribution(gameID: gameID, buckets: buckets)
    }

    private static func bump(
        _ counts: inout [Int: Int],
        _ labels: inout [Int: String],
        key: Int,
        label: String
    ) {
        counts[key, default: 0] += 1
        labels[key] = label
    }
}

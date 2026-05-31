import Foundation
import PuzzleCore

// MARK: - Public value types

public enum AchievementCategory: String, Sendable, Codable, CaseIterable {
    case streak, perfect, breadth, social, volume
}

/// An earned badge token. Stable string `id` (never a UUID) so it can act as a
/// de-dup key for celebrations across launches and devices.
public struct Achievement: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let tier: Tier

    public enum Tier: Int, Sendable, Codable, Comparable {
        case bronze, silver, gold
        public static func < (l: Tier, r: Tier) -> Bool { l.rawValue < r.rawValue }
    }

    public init(id: String, tier: Tier) {
        self.id = id
        self.tier = tier
    }
}

public struct AchievementProgress: Hashable, Sendable {
    public let current: Int
    public let target: Int

    public init(current: Int, target: Int) {
        self.current = current
        self.target = target
    }

    public var fraction: Double { target == 0 ? 0 : min(1, Double(current) / Double(target)) }
}

/// A badge definition: metadata plus a pure predicate over a precomputed
/// `AchievementContext`. Definitions live in `AchievementCatalog.all`.
public struct AchievementDefinition: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let blurb: String
    public let glyph: String          // SF Symbol name
    public let tier: Achievement.Tier
    public let category: AchievementCategory
    public let isEarned: @Sendable (AchievementContext) -> Bool
    public let progress: (@Sendable (AchievementContext) -> AchievementProgress?)?

    public init(
        id: String,
        title: String,
        blurb: String,
        glyph: String,
        tier: Achievement.Tier,
        category: AchievementCategory,
        isEarned: @escaping @Sendable (AchievementContext) -> Bool,
        progress: (@Sendable (AchievementContext) -> AchievementProgress?)? = nil
    ) {
        self.id = id
        self.title = title
        self.blurb = blurb
        self.glyph = glyph
        self.tier = tier
        self.category = category
        self.isEarned = isEarned
        self.progress = progress
    }
}

/// Everything a badge predicate needs, computed once per member from the
/// all-time result history so each predicate is a cheap field read rather than
/// a re-scan.
public struct AchievementContext: Sendable {
    public let userID: String
    public let today: PuzzleDay
    public let bestCurrentStreak: Int
    public let totalSolved: Int
    public let totalPlayed: Int
    public let perfectDays: Int
    public let distinctGames: Int
    public let trackedGames: Int
    public let maxGamesInADay: Int
    public let championDays: Int
    public let sweepDays: Int
    public let bestWordleGuesses: Int?
    public let cleanConnections: Bool
    public let earlyBird: Bool
    public let comeback: Bool
}

// MARK: - Engine

public enum AchievementEngine {

    /// Builds the per-member context from the household's all-time results.
    /// Reuses `StreakCalculator` and `CombinedScore.leaderboard` rather than
    /// reimplementing streak / champion logic.
    public static func context(
        results: [PuzzleResult],
        userID: String,
        today: PuzzleDay,
        trackedGames: [String] = Game.known.map(\.id)
    ) -> AchievementContext {
        let mine = results.filter { $0.authorUserID == userID }

        let bestCurrentStreak = Set(mine.map(\.gameID))
            .map { StreakCalculator.gameStreak(results: results, gameID: $0, userID: userID, today: today) }
            .max() ?? 0

        let totalSolved = mine.filter { $0.rawScore.solved }.count
        let distinctGames = Set(mine.map(\.gameID)).count
        let myByDay = Dictionary(grouping: mine, by: \.puzzleDay)
        let maxGamesInADay = myByDay.values.map { Set($0.map(\.gameID)).count }.max() ?? 0
        let perfectDays = myByDay.values.filter { day in
            !day.isEmpty && day.allSatisfy { $0.rawScore.solved }
        }.count

        // Champion + sweep need the full household on each day.
        let houseByDay = Dictionary(grouping: results, by: \.puzzleDay)
        var championDays = 0
        var sweepDays = 0
        for (day, dayResults) in houseByDay {
            if CombinedScore.leaderboard(dayResults, day: day).first?.userID == userID {
                championDays += 1
            }
            let gamesPlayed = Set(dayResults.map(\.gameID))
            guard gamesPlayed.count > 1 else { continue }
            let wonEvery = gamesPlayed.allSatisfy { game in
                dayResults.filter { $0.gameID == game }
                    .max { $0.rawScore.goodness < $1.rawScore.goodness }?
                    .authorUserID == userID
            }
            if wonEvery { sweepDays += 1 }
        }

        let bestWordleGuesses = mine
            .filter { $0.gameID == "wordle" }
            .compactMap { r -> Int? in
                if case .guesses(let used, _, let solved) = r.rawScore, solved { return used }
                return nil
            }
            .min()

        let cleanConnections = mine.contains { r in
            if case .mistakes(let count, _, let solved) = r.rawScore { return solved && count == 0 }
            return false
        }

        let calendar = Calendar(identifier: .gregorian)
        let earlyBird = mine.contains { calendar.component(.hour, from: $0.submittedAt) < 8 }

        var comeback = false
        for (_, rs) in Dictionary(grouping: mine, by: \.gameID) {
            let failedDays = Set(rs.filter { !$0.rawScore.solved }.map(\.puzzleDay))
            let solvedDays = Set(rs.filter { $0.rawScore.solved }.map(\.puzzleDay))
            if failedDays.contains(where: { solvedDays.contains($0.advanced(by: 1)) }) {
                comeback = true
                break
            }
        }

        return AchievementContext(
            userID: userID,
            today: today,
            bestCurrentStreak: bestCurrentStreak,
            totalSolved: totalSolved,
            totalPlayed: mine.count,
            perfectDays: perfectDays,
            distinctGames: distinctGames,
            trackedGames: trackedGames.count,
            maxGamesInADay: maxGamesInADay,
            championDays: championDays,
            sweepDays: sweepDays,
            bestWordleGuesses: bestWordleGuesses,
            cleanConnections: cleanConnections,
            earlyBird: earlyBird,
            comeback: comeback
        )
    }

    /// The full shelf for a context: every definition with its earned flag and
    /// optional progress (for "almost there" UI).
    public static func evaluate(
        _ context: AchievementContext
    ) -> [(definition: AchievementDefinition, earned: Bool, progress: AchievementProgress?)] {
        AchievementCatalog.all.map { ($0, $0.isEarned(context), $0.progress?(context)) }
    }

    /// Just the earned badge tokens (used for celebration de-duping).
    public static func earned(_ context: AchievementContext) -> [Achievement] {
        AchievementCatalog.all
            .filter { $0.isEarned(context) }
            .map { Achievement(id: $0.id, tier: $0.tier) }
    }
}

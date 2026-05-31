import Foundation

/// The curated set of ~17 badges. An immutable catalog (like `Game.known`),
/// grouped by category and tier. Every predicate reads a precomputed field on
/// `AchievementContext`, so the whole shelf evaluates in O(badges).
public enum AchievementCatalog {

    public static let all: [AchievementDefinition] = streaks + perfect + breadth + social + volume

    // MARK: Streaks

    private static let streaks: [AchievementDefinition] = [
        AchievementDefinition(
            id: "streak-3", title: "On a Roll", blurb: "3-day streak in a game",
            glyph: "flame", tier: .bronze, category: .streak,
            isEarned: { $0.bestCurrentStreak >= 3 },
            progress: { AchievementProgress(current: $0.bestCurrentStreak, target: 3) }
        ),
        AchievementDefinition(
            id: "streak-7", title: "Week Warrior", blurb: "7-day streak in a game",
            glyph: "flame.fill", tier: .silver, category: .streak,
            isEarned: { $0.bestCurrentStreak >= 7 },
            progress: { AchievementProgress(current: $0.bestCurrentStreak, target: 7) }
        ),
        AchievementDefinition(
            id: "streak-14", title: "Fortnight", blurb: "14-day streak in a game",
            glyph: "flame.fill", tier: .gold, category: .streak,
            isEarned: { $0.bestCurrentStreak >= 14 },
            progress: { AchievementProgress(current: $0.bestCurrentStreak, target: 14) }
        ),
        AchievementDefinition(
            id: "streak-30", title: "Unstoppable", blurb: "30-day streak in a game",
            glyph: "bolt.fill", tier: .gold, category: .streak,
            isEarned: { $0.bestCurrentStreak >= 30 },
            progress: { AchievementProgress(current: $0.bestCurrentStreak, target: 30) }
        ),
    ]

    // MARK: Perfect play

    private static let perfect: [AchievementDefinition] = [
        AchievementDefinition(
            id: "perfect-day", title: "Flawless", blurb: "Solved every game you played in a day",
            glyph: "checkmark.seal", tier: .bronze, category: .perfect,
            isEarned: { $0.perfectDays >= 1 },
            progress: { AchievementProgress(current: $0.perfectDays, target: 1) }
        ),
        AchievementDefinition(
            id: "perfect-10", title: "Picture of Consistency", blurb: "10 flawless days",
            glyph: "checkmark.seal.fill", tier: .silver, category: .perfect,
            isEarned: { $0.perfectDays >= 10 },
            progress: { AchievementProgress(current: $0.perfectDays, target: 10) }
        ),
        AchievementDefinition(
            id: "wordle-2", title: "Eagle Eye", blurb: "Solved Wordle in 2 guesses",
            glyph: "eye.fill", tier: .gold, category: .perfect,
            isEarned: { ($0.bestWordleGuesses ?? .max) <= 2 }
        ),
        AchievementDefinition(
            id: "connections-clean", title: "No Mistakes", blurb: "A clean Connections solve",
            glyph: "square.grid.2x2.fill", tier: .silver, category: .perfect,
            isEarned: { $0.cleanConnections }
        ),
        AchievementDefinition(
            id: "comeback", title: "Comeback Kid", blurb: "Failed a game, solved it the next day",
            glyph: "arrow.uturn.up", tier: .silver, category: .perfect,
            isEarned: { $0.comeback }
        ),
    ]

    // MARK: Breadth

    private static let breadth: [AchievementDefinition] = [
        AchievementDefinition(
            id: "breadth-day", title: "Quadruple", blurb: "Played every game in a single day",
            glyph: "square.stack.3d.up.fill", tier: .gold, category: .breadth,
            isEarned: { $0.maxGamesInADay >= $0.trackedGames && $0.trackedGames > 0 },
            progress: { AchievementProgress(current: $0.maxGamesInADay, target: $0.trackedGames) }
        ),
        AchievementDefinition(
            id: "breadth-all", title: "Renaissance", blurb: "Played every tracked game",
            glyph: "circle.grid.cross.fill", tier: .silver, category: .breadth,
            isEarned: { $0.distinctGames >= $0.trackedGames && $0.trackedGames > 0 },
            progress: { AchievementProgress(current: $0.distinctGames, target: $0.trackedGames) }
        ),
        AchievementDefinition(
            id: "sweep", title: "Clean Sweep", blurb: "Won every game played on a day",
            glyph: "rosette", tier: .gold, category: .breadth,
            isEarned: { $0.sweepDays >= 1 },
            progress: { AchievementProgress(current: $0.sweepDays, target: 1) }
        ),
    ]

    // MARK: Social

    private static let social: [AchievementDefinition] = [
        AchievementDefinition(
            id: "champ-1", title: "Top Dog", blurb: "Topped the house leaderboard",
            glyph: "trophy", tier: .bronze, category: .social,
            isEarned: { $0.championDays >= 1 },
            progress: { AchievementProgress(current: $0.championDays, target: 1) }
        ),
        AchievementDefinition(
            id: "champ-10", title: "Reigning", blurb: "Champion of the house 10 days",
            glyph: "trophy.fill", tier: .gold, category: .social,
            isEarned: { $0.championDays >= 10 },
            progress: { AchievementProgress(current: $0.championDays, target: 10) }
        ),
        AchievementDefinition(
            id: "early-bird", title: "Early Bird", blurb: "Played before 8am",
            glyph: "sunrise.fill", tier: .bronze, category: .social,
            isEarned: { $0.earlyBird }
        ),
    ]

    // MARK: Volume

    private static let volume: [AchievementDefinition] = [
        AchievementDefinition(
            id: "solved-25", title: "Quarter Century", blurb: "Solved 25 puzzles",
            glyph: "25.circle", tier: .bronze, category: .volume,
            isEarned: { $0.totalSolved >= 25 },
            progress: { AchievementProgress(current: $0.totalSolved, target: 25) }
        ),
        AchievementDefinition(
            id: "solved-100", title: "Centurion", blurb: "Solved 100 puzzles",
            glyph: "100.circle", tier: .silver, category: .volume,
            isEarned: { $0.totalSolved >= 100 },
            progress: { AchievementProgress(current: $0.totalSolved, target: 100) }
        ),
        AchievementDefinition(
            id: "solved-500", title: "Veteran", blurb: "Solved 500 puzzles",
            glyph: "star.circle.fill", tier: .gold, category: .volume,
            isEarned: { $0.totalSolved >= 500 },
            progress: { AchievementProgress(current: $0.totalSolved, target: 500) }
        ),
    ]
}

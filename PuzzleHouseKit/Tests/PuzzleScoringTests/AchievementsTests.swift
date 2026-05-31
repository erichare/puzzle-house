import Testing
import Foundation
import PuzzleCore
@testable import PuzzleScoring

@Suite struct AchievementsTests {
    private let today = PuzzleDay(year: 2026, month: 5, day: 31)

    private func result(
        _ uid: String,
        _ game: String,
        day: PuzzleDay,
        score: RawScore,
        submittedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> PuzzleResult {
        PuzzleResult(
            id: "\(uid)-\(game)-\(day.epoch)",
            householdID: "h",
            authorUserID: uid,
            gameID: game,
            puzzleNumber: Int(day.epoch),
            puzzleDay: day,
            rawScore: score,
            rawPayload: "",
            submittedAt: submittedAt
        )
    }

    @Test func streakBadgeEarnedAtThreshold() {
        let results = (0..<3).map {
            result("me", "wordle", day: today.advanced(by: -$0), score: .guesses(used: 3, outOf: 6, solved: true))
        }
        let ctx = AchievementEngine.context(results: results, userID: "me", today: today)
        #expect(ctx.bestCurrentStreak == 3)
        let earned = Set(AchievementEngine.earned(ctx).map(\.id))
        #expect(earned.contains("streak-3"))
        #expect(!earned.contains("streak-7"))
    }

    @Test func perfectDayCleanConnectionsWordleAndChampion() {
        let results = [
            result("me", "wordle", day: today, score: .guesses(used: 2, outOf: 6, solved: true)),
            result("me", "connections", day: today, score: .mistakes(count: 0, maxAllowed: 4, solved: true)),
        ]
        let ctx = AchievementEngine.context(results: results, userID: "me", today: today)
        #expect(ctx.perfectDays == 1)
        #expect(ctx.cleanConnections)
        #expect(ctx.championDays == 1)
        let earned = Set(AchievementEngine.earned(ctx).map(\.id))
        #expect(earned.contains("perfect-day"))
        #expect(earned.contains("connections-clean"))
        #expect(earned.contains("wordle-2"))
        #expect(earned.contains("champ-1"))
    }

    @Test func comebackBadge() {
        let results = [
            result("me", "wordle", day: today.advanced(by: -1), score: .guesses(used: 6, outOf: 6, solved: false)),
            result("me", "wordle", day: today, score: .guesses(used: 4, outOf: 6, solved: true)),
        ]
        let ctx = AchievementEngine.context(results: results, userID: "me", today: today)
        #expect(ctx.comeback)
        #expect(Set(AchievementEngine.earned(ctx).map(\.id)).contains("comeback"))
    }

    @Test func progressReportsTowardUnearned() {
        let results = (0..<2).map {
            result("me", "wordle", day: today.advanced(by: -$0), score: .guesses(used: 3, outOf: 6, solved: true))
        }
        let ctx = AchievementEngine.context(results: results, userID: "me", today: today)
        let streak7 = AchievementEngine.evaluate(ctx).first { $0.definition.id == "streak-7" }!
        #expect(!streak7.earned)
        #expect(streak7.progress?.current == 2)
        #expect(streak7.progress?.target == 7)
    }

    @Test func earlyBirdBadge() {
        let early = Calendar(identifier: .gregorian)
            .date(from: DateComponents(year: 2026, month: 5, day: 31, hour: 6))!
        let results = [result("me", "wordle", day: today, score: .guesses(used: 3, outOf: 6, solved: true), submittedAt: early)]
        let ctx = AchievementEngine.context(results: results, userID: "me", today: today)
        #expect(ctx.earlyBird)
        #expect(Set(AchievementEngine.earned(ctx).map(\.id)).contains("early-bird"))
    }
}

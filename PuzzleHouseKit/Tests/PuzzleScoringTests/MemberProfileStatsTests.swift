import Testing
import PuzzleCore
@testable import PuzzleScoring

@Suite struct MemberProfileStatsTests {
    private let today = PuzzleDay(year: 2026, month: 5, day: 31)

    private func result(_ uid: String, _ game: String, _ n: Int, _ score: RawScore, day: PuzzleDay? = nil) -> PuzzleResult {
        PuzzleResult(
            id: "\(uid)-\(game)-\(n)",
            householdID: "h",
            authorUserID: uid,
            gameID: game,
            puzzleNumber: n,
            puzzleDay: day ?? today,
            rawScore: score,
            rawPayload: ""
        )
    }

    @Test func recordsTracksBestsAndRate() {
        let results = [
            result("me", "wordle", 1, .guesses(used: 3, outOf: 6, solved: true)),
            result("me", "wordle", 2, .guesses(used: 2, outOf: 6, solved: true)),
            result("me", "wordle", 3, .guesses(used: 6, outOf: 6, solved: false)),
            result("me", "connections", 1, .mistakes(count: 1, maxAllowed: 4, solved: true)),
        ]
        let r = MemberProfileStats.records(results: results, userID: "me")
        #expect(r.totalPlayed == 4)
        #expect(r.totalSolved == 3)
        #expect(r.bestWordleGuesses == 2)
        #expect(r.bestConnectionsMistakes == 1)
        #expect(abs(r.solveRate - 0.75) < 0.0001)
    }

    @Test func headToHeadComparesSharedPuzzlesOnly() {
        let results = [
            result("me", "wordle", 1, .guesses(used: 2, outOf: 6, solved: true)),   // me better
            result("mom", "wordle", 1, .guesses(used: 4, outOf: 6, solved: true)),
            result("me", "wordle", 2, .guesses(used: 5, outOf: 6, solved: true)),   // mom better
            result("mom", "wordle", 2, .guesses(used: 3, outOf: 6, solved: true)),
            result("me", "connections", 1, .mistakes(count: 0, maxAllowed: 4, solved: true)),  // only me
        ]
        let h2h = MemberProfileStats.headToHead(results: results, viewer: "me", opponent: "mom")
        #expect(h2h.wins == 1)
        #expect(h2h.losses == 1)
        #expect(h2h.total == 2)
    }

    @Test func activityTimelineIsContinuous() {
        let results = [result("me", "wordle", 1, .guesses(used: 3, outOf: 6, solved: true), day: today)]
        let timeline = MemberProfileStats.activityTimeline(results: results, userID: "me", today: today, days: 7)
        #expect(timeline.count == 7)
        #expect(timeline.last?.day == today)
        #expect(timeline.last?.gamesPlayed == 1)
        #expect(timeline.first?.gamesPlayed == 0)
    }
}

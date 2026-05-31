import Testing
import PuzzleCore
@testable import PuzzleScoring

@Suite struct GameBreakdownStatsTests {

    private func result(_ uid: String, _ gameID: String, _ n: Int, _ score: RawScore) -> PuzzleResult {
        PuzzleResult(
            id: "\(uid)-\(gameID)-\(n)",
            householdID: "h",
            authorUserID: uid,
            gameID: gameID,
            puzzleNumber: n,
            puzzleDay: PuzzleDay(year: 2026, month: 5, day: 1),
            rawScore: score,
            rawPayload: ""
        )
    }

    @Test func bucketsGuessesAndPutsFailsLast() {
        let results = [
            result("me", "wordle", 1, .guesses(used: 3, outOf: 6, solved: true)),
            result("me", "wordle", 2, .guesses(used: 3, outOf: 6, solved: true)),
            result("me", "wordle", 3, .guesses(used: 4, outOf: 6, solved: true)),
            result("me", "wordle", 4, .guesses(used: 6, outOf: 6, solved: false)),
        ]
        let dist = GameBreakdownStats.compute(results: results, games: ["wordle"])[0].distribution
        #expect(dist.buckets.first(where: { $0.label == "3" })?.count == 2)
        #expect(dist.buckets.first(where: { $0.label == "4" })?.count == 1)
        #expect(dist.buckets.first(where: { $0.label == "X" })?.count == 1)
        #expect(dist.buckets.last?.label == "X")   // fails always sort to the end
    }

    @Test func winRateIsSolvedOverPlayed() {
        let results = [
            result("me", "wordle", 1, .guesses(used: 3, outOf: 6, solved: true)),
            result("me", "wordle", 2, .guesses(used: 6, outOf: 6, solved: false)),
        ]
        let wr = GameBreakdownStats.compute(results: results, games: ["wordle"])[0].winRate
        #expect(wr.played == 2)
        #expect(wr.solved == 1)
        #expect(abs(wr.rate - 0.5) < 0.0001)
    }

    @Test func filtersByUser() {
        let results = [
            result("me", "wordle", 1, .guesses(used: 3, outOf: 6, solved: true)),
            result("mom", "wordle", 1, .guesses(used: 4, outOf: 6, solved: true)),
        ]
        let mine = GameBreakdownStats.compute(results: results, userID: "me", games: ["wordle"])
        #expect(mine[0].winRate.played == 1)
    }

    @Test func skipsGamesWithNoResults() {
        let results = [result("me", "wordle", 1, .guesses(used: 3, outOf: 6, solved: true))]
        let breakdown = GameBreakdownStats.compute(results: results, games: ["wordle", "connections"])
        #expect(breakdown.count == 1)
        #expect(breakdown[0].gameID == "wordle")
    }

    @Test func bucketsConnectionsMistakes() {
        let results = [
            result("me", "connections", 1, .mistakes(count: 0, maxAllowed: 4, solved: true)),
            result("me", "connections", 2, .mistakes(count: 2, maxAllowed: 4, solved: true)),
            result("me", "connections", 3, .mistakes(count: 4, maxAllowed: 4, solved: false)),
        ]
        let dist = GameBreakdownStats.compute(results: results, games: ["connections"])[0].distribution
        #expect(dist.buckets.first(where: { $0.label == "0" })?.count == 1)
        #expect(dist.buckets.first(where: { $0.label == "2" })?.count == 1)
        #expect(dist.buckets.first(where: { $0.label == "X" })?.count == 1)
    }
}

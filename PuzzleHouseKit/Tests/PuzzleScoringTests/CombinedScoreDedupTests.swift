import XCTest
import PuzzleCore
@testable import PuzzleScoring

/// Regression: a household ending up with two `PuzzleResult`s for the same
/// (user, game, day) used to trap in `Dictionary(uniqueKeysWithValues:)`.
/// `computeDay` now keeps the best goodness per player.
final class CombinedScoreDedupTests: XCTestCase {

    private let today = PuzzleDay(year: 2026, month: 5, day: 19)

    private func wordle(_ uid: String, used: Int) -> PuzzleResult {
        PuzzleResult(
            householdID: "h1",
            authorUserID: uid,
            gameID: "wordle",
            puzzleNumber: 1247,
            puzzleDay: today,
            rawScore: .guesses(used: used, outOf: 6, solved: true),
            rawPayload: ""
        )
    }

    func testDuplicateUserGameDayDoesNotCrash() {
        let results = [wordle("me", used: 5), wordle("me", used: 3)]
        let scores = CombinedScore.computeDay(results, day: today)
        XCTAssertEqual(scores.count, 1)
        // 3/6 has goodness 4, which beats 2 from 5/6
        XCTAssertEqual(scores.first?.userID, "me")
    }

    func testBestScoreSurvivesWhenDuplicated() {
        // a has two results, b has one; a's best (used=2 → goodness 5) wins.
        let results = [
            wordle("a", used: 4),
            wordle("a", used: 2),
            wordle("b", used: 3),
        ]
        let scores = CombinedScore.leaderboard(results, day: today)
        XCTAssertEqual(scores.first?.userID, "a")
    }
}

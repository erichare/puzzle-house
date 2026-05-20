import XCTest
import PuzzleCore
@testable import PuzzleScoring

final class CombinedScoreTests: XCTestCase {

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

    private func connections(_ uid: String, mistakes: Int) -> PuzzleResult {
        PuzzleResult(
            householdID: "h1",
            authorUserID: uid,
            gameID: "connections",
            puzzleNumber: 234,
            puzzleDay: today,
            rawScore: .mistakes(count: mistakes, maxAllowed: 4, solved: mistakes < 4),
            rawPayload: ""
        )
    }

    func testSinglePlayerDayYieldsZeroZScores() {
        let results = [wordle("a", used: 4)]
        let scores = CombinedScore.computeDay(results, day: today)
        XCTAssertEqual(scores.count, 1)
        XCTAssertEqual(scores[0].perGame["wordle"], 0)
        // Only the breadth bonus survives.
        XCTAssertEqual(scores[0].combined, CombinedScore.breadthWeight, accuracy: 0.0001)
    }

    func testBetterScoreYieldsPositiveZ() {
        // a guessed in 3 (goodness 4), b in 5 (goodness 2)
        let results = [wordle("a", used: 3), wordle("b", used: 5)]
        let scores = CombinedScore.computeDay(results, day: today)
        let a = scores.first { $0.userID == "a" }!
        let b = scores.first { $0.userID == "b" }!
        XCTAssertGreaterThan(a.perGame["wordle"]!, 0)
        XCTAssertLessThan(b.perGame["wordle"]!, 0)
        XCTAssertGreaterThan(a.combined, b.combined)
    }

    func testLeaderboardSortsChampionFirst() {
        let results = [
            wordle("a", used: 5),
            wordle("b", used: 3),
            wordle("c", used: 4),
        ]
        let board = CombinedScore.leaderboard(results, day: today)
        XCTAssertEqual(board.first?.userID, "b")
        XCTAssertEqual(board.last?.userID, "a")
    }

    func testBreadthBonusFavorsMoreGames() {
        // a played both, b only played wordle. Same wordle score.
        let results = [
            wordle("a", used: 4),
            wordle("b", used: 4),
            connections("a", mistakes: 1),
        ]
        let scores = CombinedScore.computeDay(results, day: today)
        let a = scores.first { $0.userID == "a" }!
        let b = scores.first { $0.userID == "b" }!
        // a gets a breadth bonus of 0.2 (two games), b gets 0.1 (one).
        XCTAssertEqual(a.breadthBonus, 0.2, accuracy: 0.0001)
        XCTAssertEqual(b.breadthBonus, 0.1, accuracy: 0.0001)
        XCTAssertGreaterThan(a.combined, b.combined)
    }

    func testTiedHouseholdUsesStdFloor() {
        let results = [wordle("a", used: 4), wordle("b", used: 4)]
        let scores = CombinedScore.computeDay(results, day: today)
        for score in scores {
            XCTAssertEqual(score.perGame["wordle"] ?? .nan, 0, accuracy: 0.0001)
        }
    }

    func testIgnoresOtherDays() {
        let yesterday = today.advanced(by: -1)
        let results = [
            wordle("a", used: 4),
            PuzzleResult(
                householdID: "h1",
                authorUserID: "b",
                gameID: "wordle",
                puzzleNumber: 1246,
                puzzleDay: yesterday,
                rawScore: .guesses(used: 2, outOf: 6, solved: true),
                rawPayload: ""
            ),
        ]
        let scores = CombinedScore.computeDay(results, day: today)
        XCTAssertEqual(scores.count, 1)
        XCTAssertEqual(scores[0].userID, "a")
    }
}

import XCTest
import PuzzleCore
@testable import PuzzleScoring

final class StreakCalculatorTests: XCTestCase {

    private let today = PuzzleDay(year: 2026, month: 5, day: 19)

    private func result(uid: String, gameID: String, day: PuzzleDay) -> PuzzleResult {
        PuzzleResult(
            householdID: "h1",
            authorUserID: uid,
            gameID: gameID,
            puzzleNumber: day.year * 10000 + day.month * 100 + day.day,
            puzzleDay: day,
            rawScore: .guesses(used: 4, outOf: 6, solved: true),
            rawPayload: ""
        )
    }

    func testGameStreakConsecutiveDays() {
        let results = (0..<5).map { result(uid: "a", gameID: "wordle", day: today.advanced(by: -$0)) }
        let streak = StreakCalculator.gameStreak(
            results: results, gameID: "wordle", userID: "a", today: today
        )
        XCTAssertEqual(streak, 5)
    }

    func testGameStreakBrokenByGap() {
        let results = [
            result(uid: "a", gameID: "wordle", day: today),
            result(uid: "a", gameID: "wordle", day: today.advanced(by: -1)),
            // skipped today-2
            result(uid: "a", gameID: "wordle", day: today.advanced(by: -3)),
        ]
        let streak = StreakCalculator.gameStreak(
            results: results, gameID: "wordle", userID: "a", today: today
        )
        XCTAssertEqual(streak, 2)
    }

    func testGameStreakIgnoresOtherGames() {
        let results = [
            result(uid: "a", gameID: "wordle", day: today),
            result(uid: "a", gameID: "connections", day: today.advanced(by: -1)),
        ]
        let streak = StreakCalculator.gameStreak(
            results: results, gameID: "wordle", userID: "a", today: today
        )
        XCTAssertEqual(streak, 1)
    }

    func testHouseStreakRequiresEveryActiveMember() {
        let members = ["a", "b"]
        var results: [PuzzleResult] = []
        for offset in 0..<3 {
            results.append(result(uid: "a", gameID: "wordle", day: today.advanced(by: -offset)))
            results.append(result(uid: "b", gameID: "wordle", day: today.advanced(by: -offset)))
        }
        let streak = StreakCalculator.houseStreak(
            results: results, memberUserIDs: members, today: today
        )
        XCTAssertEqual(streak, 3)
    }

    func testHouseStreakBrokenWhenSomeoneMissesADay() {
        let members = ["a", "b"]
        let results = [
            result(uid: "a", gameID: "wordle", day: today),
            result(uid: "b", gameID: "wordle", day: today),
            result(uid: "a", gameID: "wordle", day: today.advanced(by: -1)),
            // b missed yesterday
            result(uid: "a", gameID: "wordle", day: today.advanced(by: -2)),
            result(uid: "b", gameID: "wordle", day: today.advanced(by: -2)),
        ]
        let streak = StreakCalculator.houseStreak(
            results: results, memberUserIDs: members, today: today
        )
        XCTAssertEqual(streak, 1)
    }

    func testInactiveMembersDoNotBlockHouseStreak() {
        // c hasn't played in 30 days — excluded as inactive.
        let members = ["a", "b", "c"]
        var results: [PuzzleResult] = []
        for offset in 0..<2 {
            results.append(result(uid: "a", gameID: "wordle", day: today.advanced(by: -offset)))
            results.append(result(uid: "b", gameID: "wordle", day: today.advanced(by: -offset)))
        }
        results.append(result(uid: "c", gameID: "wordle", day: today.advanced(by: -30)))
        let streak = StreakCalculator.houseStreak(
            results: results, memberUserIDs: members, today: today
        )
        XCTAssertEqual(streak, 2)
    }
}

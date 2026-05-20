import XCTest
import PuzzleCore
@testable import PuzzleScoring

final class ChecklistMatrixTests: XCTestCase {

    private let today = PuzzleDay(year: 2026, month: 5, day: 19)

    private func result(uid: String, gameID: String, solved: Bool) -> PuzzleResult {
        PuzzleResult(
            householdID: "h1",
            authorUserID: uid,
            gameID: gameID,
            puzzleNumber: 1,
            puzzleDay: today,
            rawScore: solved ? .guesses(used: 3, outOf: 6, solved: true)
                             : .guesses(used: 7, outOf: 6, solved: false),
            rawPayload: ""
        )
    }

    func testTrackedGamesAppearEvenWithNoPlay() {
        let rows = ChecklistMatrix.build(
            results: [],
            memberUserIDs: ["me", "mom"],
            tracked: ["wordle", "connections", "strands"],
            day: today
        )
        XCTAssertEqual(rows.map(\.gameID), ["wordle", "connections", "strands"])
        for row in rows {
            for entry in row.perMember {
                XCTAssertEqual(entry.state, .notPlayed)
            }
        }
    }

    func testSolvedAndFailedReflectedPerMember() {
        let results = [
            result(uid: "me", gameID: "wordle", solved: true),
            result(uid: "mom", gameID: "wordle", solved: false),
        ]
        let rows = ChecklistMatrix.build(
            results: results,
            memberUserIDs: ["me", "mom"],
            tracked: ["wordle"],
            day: today
        )
        let wordle = rows.first!
        let me = wordle.perMember.first { $0.userID == "me" }!
        let mom = wordle.perMember.first { $0.userID == "mom" }!
        XCTAssertEqual(me.state, .solved)
        XCTAssertEqual(mom.state, .failed)
        XCTAssertEqual(wordle.solvedCount, 1)
        XCTAssertEqual(wordle.totalCount, 2)
    }

    func testUntrackedGamePlayedTodayShowsUp() {
        let results = [result(uid: "me", gameID: "quordle", solved: true)]
        let rows = ChecklistMatrix.build(
            results: results,
            memberUserIDs: ["me"],
            tracked: ["wordle"],
            day: today
        )
        XCTAssertEqual(rows.map(\.gameID), ["wordle", "quordle"])
    }

    func testIgnoresOtherDays() {
        let results = [
            result(uid: "me", gameID: "wordle", solved: true).onDay(today.advanced(by: -1))
        ]
        let rows = ChecklistMatrix.build(
            results: results,
            memberUserIDs: ["me"],
            tracked: ["wordle"],
            day: today
        )
        XCTAssertEqual(rows.first?.perMember.first?.state, .notPlayed)
    }
}

private extension PuzzleResult {
    func onDay(_ d: PuzzleDay) -> PuzzleResult {
        PuzzleResult(
            id: id, householdID: householdID, authorUserID: authorUserID,
            gameID: gameID, puzzleNumber: puzzleNumber, puzzleDay: d,
            rawScore: rawScore, rawPayload: rawPayload,
            gridData: gridData, submittedAt: submittedAt
        )
    }
}

import XCTest
import PuzzleCore
@testable import PuzzleScoring

final class StatsHighlightsTests: XCTestCase {

    private let today = PuzzleDay(year: 2026, month: 5, day: 19)

    private func result(
        uid: String,
        gameID: String,
        solved: Bool = true,
        days offset: Int = 0
    ) -> PuzzleResult {
        PuzzleResult(
            householdID: "h1",
            authorUserID: uid,
            gameID: gameID,
            puzzleNumber: 1000 + offset,
            puzzleDay: today.advanced(by: -offset),
            rawScore: solved ? .guesses(used: 3, outOf: 6, solved: true)
                             : .guesses(used: 7, outOf: 6, solved: false),
            rawPayload: ""
        )
    }

    func testEmptyReturnsNothing() {
        let highlights = StatsHighlights.compute(
            results: [],
            memberDisplayName: { _ in "" },
            memberAvatar: { _ in "" },
            today: today
        )
        XCTAssertTrue(highlights.isEmpty)
    }

    func testMostPlayedSurfacesCorrectGame() {
        let results = [
            result(uid: "me", gameID: "wordle"),
            result(uid: "me", gameID: "wordle", days: 1),
            result(uid: "me", gameID: "wordle", days: 2),
            result(uid: "mom", gameID: "connections"),
        ]
        let highlights = StatsHighlights.compute(
            results: results,
            memberDisplayName: { $0 },
            memberAvatar: { _ in "🧩" },
            today: today
        )
        let mostPlayed = highlights.first { $0.id == "most-played" }
        XCTAssertNotNil(mostPlayed)
        XCTAssertTrue(mostPlayed!.detail.contains("Wordle"))
    }

    func testStreakHighlightAppearsWhenStreakLongerThanOne() {
        let results = (0..<4).map { result(uid: "me", gameID: "wordle", days: $0) }
        let highlights = StatsHighlights.compute(
            results: results,
            memberDisplayName: { _ in "Me" },
            memberAvatar: { _ in "🧑" },
            today: today
        )
        let streak = highlights.first { $0.id == "streak" }
        XCTAssertNotNil(streak)
        XCTAssertTrue(streak!.detail.contains("4"))
    }

    func testVolumeAlwaysAppearsWithAnyResult() {
        let results = [result(uid: "me", gameID: "wordle")]
        let highlights = StatsHighlights.compute(
            results: results,
            memberDisplayName: { _ in "Me" },
            memberAvatar: { _ in "🧑" },
            today: today
        )
        XCTAssertTrue(highlights.contains(where: { $0.id == "volume" }))
    }
}

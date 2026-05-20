import XCTest
import PuzzleCore
@testable import PuzzleScoring

final class SpoilerPolicyTests: XCTestCase {

    private let today = PuzzleDay(year: 2026, month: 5, day: 19)

    private func result(uid: String, gameID: String = "wordle", number: Int = 1247) -> PuzzleResult {
        PuzzleResult(
            householdID: "h1",
            authorUserID: uid,
            gameID: gameID,
            puzzleNumber: number,
            puzzleDay: today,
            rawScore: .guesses(used: 4, outOf: 6, solved: true),
            rawPayload: ""
        )
    }

    func testViewerSeesTheirOwnResultFully() {
        let r = result(uid: "me")
        let v = SpoilerPolicy.visibility(
            of: r,
            viewerUserID: "me",
            viewerResults: [r],
            viewerPreferences: .init(hideSpoilersUntilSolved: true)
        )
        XCTAssertEqual(v, .full)
    }

    func testOthersResultHiddenWhenViewerHasntPlayed() {
        let theirs = result(uid: "mom")
        let v = SpoilerPolicy.visibility(
            of: theirs,
            viewerUserID: "me",
            viewerResults: [],
            viewerPreferences: .init(hideSpoilersUntilSolved: true)
        )
        XCTAssertEqual(v, .hidden)
    }

    func testOthersResultRevealedAfterViewerSubmits() {
        let theirs = result(uid: "mom")
        let mine = result(uid: "me")
        let v = SpoilerPolicy.visibility(
            of: theirs,
            viewerUserID: "me",
            viewerResults: [mine],
            viewerPreferences: .init(hideSpoilersUntilSolved: true)
        )
        XCTAssertEqual(v, .full)
    }

    func testPreferenceTurnsSpoilersOff() {
        let theirs = result(uid: "mom")
        let v = SpoilerPolicy.visibility(
            of: theirs,
            viewerUserID: "me",
            viewerResults: [],
            viewerPreferences: .init(hideSpoilersUntilSolved: false)
        )
        XCTAssertEqual(v, .full)
    }

    func testSubmittingOneGameDoesNotRevealAnother() {
        let theirWordle = result(uid: "mom", gameID: "wordle", number: 1247)
        let myConnections = result(uid: "me", gameID: "connections", number: 234)
        let v = SpoilerPolicy.visibility(
            of: theirWordle,
            viewerUserID: "me",
            viewerResults: [myConnections],
            viewerPreferences: .init(hideSpoilersUntilSolved: true)
        )
        XCTAssertEqual(v, .hidden)
    }

    func testBulkVisibilitiesMatchIndividualResults() {
        let me = result(uid: "me")
        let mom = result(uid: "mom")
        let dad = result(uid: "dad")
        let results = [me, mom, dad]
        let map = SpoilerPolicy.visibilities(
            for: results,
            viewerUserID: "me",
            viewerPreferences: .init(hideSpoilersUntilSolved: true)
        )
        // I've played wordle 1247 so mom & dad reveal.
        XCTAssertEqual(map[me.id], .full)
        XCTAssertEqual(map[mom.id], .full)
        XCTAssertEqual(map[dad.id], .full)
    }
}

import XCTest
import PuzzleCore
@testable import PuzzleCloudKit

final class OfflineWriteQueueTests: XCTestCase {

    private var tmpDir: URL!
    private var queue: OfflineWriteQueue!

    override func setUpWithError() throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("queue-\(UUID().uuidString)")
        let container = AppGroupContainer(baseURL: tmpDir)
        queue = OfflineWriteQueue(container: container)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    private func sampleResult(id: String = UUID().uuidString) -> PuzzleResult {
        PuzzleResult(
            id: id,
            householdID: "h1",
            authorUserID: "u1",
            gameID: "wordle",
            puzzleNumber: 1247,
            puzzleDay: PuzzleDay(year: 2026, month: 5, day: 19),
            rawScore: .guesses(used: 4, outOf: 6, solved: true),
            rawPayload: "Wordle 1,247 4/6\n⬛⬛⬛⬛⬛"
        )
    }

    func testEmptyQueueHasNothing() throws {
        XCTAssertEqual(try queue.count(), 0)
        XCTAssertTrue(try queue.pending().isEmpty)
    }

    func testEnqueueRoundTripsCleanly() throws {
        let result = sampleResult()
        try queue.enqueue(result)
        let pending = try queue.pending()
        XCTAssertEqual(pending.count, 1)
        let round = pending.first!
        XCTAssertEqual(round.id, result.id)
        XCTAssertEqual(round.householdID, result.householdID)
        XCTAssertEqual(round.authorUserID, result.authorUserID)
        XCTAssertEqual(round.gameID, result.gameID)
        XCTAssertEqual(round.puzzleNumber, result.puzzleNumber)
        XCTAssertEqual(round.puzzleDay, result.puzzleDay)
        XCTAssertEqual(round.rawScore, result.rawScore)
        XCTAssertEqual(round.rawPayload, result.rawPayload)
        XCTAssertEqual(round.gridData, result.gridData)
        XCTAssertEqual(
            round.submittedAt.timeIntervalSince1970,
            result.submittedAt.timeIntervalSince1970,
            accuracy: 0.01,
            "submittedAt round-trip should be within 10 ms"
        )
    }

    func testRemoveDeletesEntry() throws {
        let result = sampleResult()
        try queue.enqueue(result)
        XCTAssertEqual(try queue.count(), 1)
        queue.remove(result.id)
        XCTAssertEqual(try queue.count(), 0)
    }

    func testMultipleEntriesSortedByModificationTime() throws {
        let first = sampleResult(id: "a")
        try queue.enqueue(first)
        Thread.sleep(forTimeInterval: 0.05)
        let second = sampleResult(id: "b")
        try queue.enqueue(second)
        let pending = try queue.pending()
        XCTAssertEqual(pending.map(\.id), ["a", "b"])
    }

    func testRemoveOfMissingIDIsHarmless() throws {
        queue.remove("does-not-exist")
        XCTAssertEqual(try queue.count(), 0)
    }
}

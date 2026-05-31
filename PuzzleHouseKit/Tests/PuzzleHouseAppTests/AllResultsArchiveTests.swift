import XCTest
import PuzzleCore
import PuzzleCloudKit
@testable import PuzzleHouseApp

@MainActor
final class AllResultsArchiveTests: XCTestCase {

    private func household(_ id: String = "h1") -> Household {
        Household(id: id, name: "Family", iconEmoji: "🏠", createdByUserID: "me")
    }

    private func result(_ puzzleNumber: Int, day: PuzzleDay) -> PuzzleResult {
        PuzzleResult(
            id: PuzzleResult.deterministicID(authorUserID: "me", gameID: "wordle", puzzleNumber: puzzleNumber),
            householdID: "h1",
            authorUserID: "me",
            gameID: "wordle",
            puzzleNumber: puzzleNumber,
            puzzleDay: day,
            rawScore: .guesses(used: 3, outOf: 6, solved: true),
            rawPayload: ""
        )
    }

    private func tmpArchive() -> ResultArchiveStore {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ph-archive-\(UUID().uuidString)", isDirectory: true)
        return ResultArchiveStore(container: AppGroupContainer(baseURL: base))
    }

    func testAllResultsBackfillsBeyondRecentWindow() async {
        let todayDay = PuzzleDay(year: 2026, month: 5, day: 19)
        let oldDay = todayDay.advanced(by: -30)   // outside the 14-day window
        let service = FakeCloudKitService(
            households: [household()],
            members: ["h1": [Membership(householdID: "h1", userID: "me", displayName: "Me", role: .owner)]],
            resultsByDay: ["h1": [todayDay: [result(100, day: todayDay)], oldDay: [result(70, day: oldDay)]]]
        )
        let store = HouseholdStore(
            service: service,
            notifications: FakeNotificationService(),
            archiveStore: tmpArchive(),
            now: { HouseholdStoreTests.fixedNow() }
        )
        await store.bootstrap()

        // The 14-day window excludes the 30-day-old result...
        XCTAssertEqual(store.recentResults.count, 1)
        // ...but the all-time archive includes both.
        XCTAssertEqual(store.allResults.count, 2)
        XCTAssertTrue(store.allResults.contains { $0.puzzleNumber == 70 })
    }

    func testArchivePersistsAcrossStoresWithoutRefetch() async {
        let archive = tmpArchive()
        let todayDay = PuzzleDay(year: 2026, month: 5, day: 19)
        let oldDay = todayDay.advanced(by: -30)

        let seeded = FakeCloudKitService(
            households: [household()],
            members: ["h1": [Membership(householdID: "h1", userID: "me", displayName: "Me", role: .owner)]],
            resultsByDay: ["h1": [todayDay: [result(100, day: todayDay)], oldDay: [result(70, day: oldDay)]]]
        )
        let first = HouseholdStore(
            service: seeded, notifications: FakeNotificationService(),
            archiveStore: archive, now: { HouseholdStoreTests.fixedNow() }
        )
        await first.bootstrap()
        XCTAssertEqual(first.allResults.count, 2)

        // A second store whose service has NO results still sees full history
        // from the persisted archive (proves we don't depend on a re-fetch).
        let empty = FakeCloudKitService(
            households: [household()],
            members: ["h1": [Membership(householdID: "h1", userID: "me", displayName: "Me", role: .owner)]]
        )
        let second = HouseholdStore(
            service: empty, notifications: FakeNotificationService(),
            archiveStore: archive, now: { HouseholdStoreTests.fixedNow() }
        )
        await second.bootstrap()
        XCTAssertEqual(second.allResults.count, 2)
    }
}

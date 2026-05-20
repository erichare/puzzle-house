import XCTest
import PuzzleCore
import PuzzleParsers
import PuzzleCloudKit
@testable import PuzzleHouseApp

@MainActor
final class HouseholdStoreTests: XCTestCase {

    private let today = PuzzleDay(year: 2026, month: 5, day: 19)

    nonisolated static func fixedNow() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 19; c.hour = 12
        c.timeZone = .current
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func household(_ id: String = "h1") -> Household {
        Household(id: id, name: "Family", iconEmoji: "🏠", createdByUserID: "me")
    }

    func testBootstrapPicksFirstHousehold() async {
        let service = FakeCloudKitService(
            households: [household("h1"), household("h2")],
            members: [
                "h1": [
                    Membership(householdID: "h1", userID: "me", displayName: "Me", role: .owner),
                    Membership(householdID: "h1", userID: "mom", displayName: "Mom"),
                ],
            ]
        )
        let store = HouseholdStore(service: service, notifications: FakeNotificationService(), now: { Date() })
        await store.bootstrap()
        XCTAssertEqual(store.state, .ready)
        XCTAssertEqual(store.currentUserID, "me")
        XCTAssertEqual(store.households.count, 2)
        XCTAssertEqual(store.selectedHouseholdID, "h1")
        XCTAssertEqual(store.members.count, 2)
        XCTAssertEqual(store.displayName(for: "mom"), "Mom")
    }

    func testSwitchHouseholdLoadsItsData() async {
        let service = FakeCloudKitService(
            households: [household("h1"), household("h2")],
            members: [
                "h1": [Membership(householdID: "h1", userID: "me", displayName: "Me", role: .owner)],
                "h2": [
                    Membership(householdID: "h2", userID: "me", displayName: "Eric"),
                    Membership(householdID: "h2", userID: "friend", displayName: "Pat"),
                ],
            ]
        )
        let store = HouseholdStore(service: service, notifications: FakeNotificationService(), now: { HouseholdStoreTests.fixedNow() })
        await store.bootstrap()
        await store.switchHousehold("h2")
        XCTAssertEqual(store.selectedHouseholdID, "h2")
        XCTAssertEqual(store.members.count, 2)
        XCTAssertEqual(store.displayName(for: "me"), "Eric")
    }

    func testSubmitGoesThroughService() async throws {
        let service = FakeCloudKitService(
            households: [household("h1")],
            members: ["h1": [Membership(householdID: "h1", userID: "me", displayName: "Me", role: .owner)]]
        )
        let store = HouseholdStore(service: service, notifications: FakeNotificationService(), now: { HouseholdStoreTests.fixedNow() })
        await store.bootstrap()

        let parsed = ParserRegistry.parse("Wordle 1,247 3/6\n\n🟨🟨🟨⬛⬛\n🟩🟩🟩⬛⬛\n🟩🟩🟩🟩🟩")!
        try await store.submit(parsed: parsed, rawPayload: "Wordle 1,247 3/6")

        XCTAssertEqual(store.todayResults.count, 1)
        XCTAssertEqual(store.todayResults.first?.gameID, "wordle")
        XCTAssertEqual(store.todayResults.first?.puzzleNumber, 1247)
    }

    func testLeaderboardSurfacesTopPlayer() async throws {
        let service = FakeCloudKitService(
            households: [household("h1")],
            members: [
                "h1": [
                    Membership(householdID: "h1", userID: "me", displayName: "Me", role: .owner),
                    Membership(householdID: "h1", userID: "mom", displayName: "Mom"),
                ],
            ]
        )
        let store = HouseholdStore(service: service, notifications: FakeNotificationService(), now: { HouseholdStoreTests.fixedNow() })
        await store.bootstrap()

        // Mom beats me at Wordle.
        try await service.submit(PuzzleResult(
            householdID: "h1", authorUserID: "mom",
            gameID: "wordle", puzzleNumber: 1247, puzzleDay: store.today,
            rawScore: .guesses(used: 2, outOf: 6, solved: true), rawPayload: ""
        ))
        try await service.submit(PuzzleResult(
            householdID: "h1", authorUserID: "me",
            gameID: "wordle", puzzleNumber: 1247, puzzleDay: store.today,
            rawScore: .guesses(used: 5, outOf: 6, solved: true), rawPayload: ""
        ))
        await store.refresh()

        let board = store.leaderboard
        XCTAssertEqual(board.first?.userID, "mom")
        XCTAssertEqual(board.last?.userID, "me")
    }

    func testHouseStreakReflectsRecentResults() async throws {
        let service = FakeCloudKitService(
            households: [household("h1")],
            members: [
                "h1": [
                    Membership(householdID: "h1", userID: "me", displayName: "Me", role: .owner),
                    Membership(householdID: "h1", userID: "mom", displayName: "Mom"),
                ],
            ]
        )
        let store = HouseholdStore(service: service, notifications: FakeNotificationService(), now: { HouseholdStoreTests.fixedNow() })
        await store.bootstrap()

        // Both members played today, yesterday, and the day before.
        for offset in 0..<3 {
            let day = store.today.advanced(by: -offset)
            for uid in ["me", "mom"] {
                try await service.submit(PuzzleResult(
                    householdID: "h1", authorUserID: uid,
                    gameID: "wordle",
                    puzzleNumber: 1000 + offset,
                    puzzleDay: day,
                    rawScore: .guesses(used: 4, outOf: 6, solved: true),
                    rawPayload: ""
                ))
            }
        }
        await store.refresh()
        XCTAssertEqual(store.houseStreak, 3)
        XCTAssertEqual(store.gameStreak(userID: "me", gameID: "wordle"), 3)
    }

    func testDrainPendingResultsFlushesQueueAndStripsPlaceholderIDs() async throws {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("drain-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let queue = OfflineWriteQueue(container: AppGroupContainer(baseURL: tmpDir))

        let service = FakeCloudKitService(
            households: [household("h1")],
            members: ["h1": [Membership(householdID: "h1", userID: "me", displayName: "Me", role: .owner)]]
        )
        let store = HouseholdStore(service: service, queue: queue, notifications: FakeNotificationService(), now: { HouseholdStoreTests.fixedNow() })
        await store.bootstrap()

        // Share Extension dropped a placeholder with "pending" household/author.
        let placeholder = PuzzleResult(
            householdID: "pending", authorUserID: "pending",
            gameID: "wordle", puzzleNumber: 1247,
            puzzleDay: store.today,
            rawScore: .guesses(used: 3, outOf: 6, solved: true),
            rawPayload: "Wordle 1,247 3/6"
        )
        try queue.enqueue(placeholder)
        XCTAssertEqual(try queue.count(), 1)

        await store.drainPendingResults()

        XCTAssertEqual(try queue.count(), 0)
        XCTAssertEqual(store.todayResults.count, 1)
        let submitted = store.todayResults.first!
        XCTAssertEqual(submitted.householdID, "h1")
        XCTAssertEqual(submitted.authorUserID, "me")
        XCTAssertEqual(
            submitted.id,
            PuzzleResult.deterministicID(authorUserID: "me", gameID: "wordle", puzzleNumber: 1247),
            "Drain rewrites to a deterministic record ID so duplicates collide and overwrite"
        )
    }

    func testDrainKeepsItemsOnSubmitFailure() async throws {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("drain-fail-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let queue = OfflineWriteQueue(container: AppGroupContainer(baseURL: tmpDir))

        let service = FailingFakeService()
        let store = HouseholdStore(service: service, queue: queue, notifications: FakeNotificationService(), now: { HouseholdStoreTests.fixedNow() })
        await store.bootstrap()
        // bootstrap will error because of FailingFakeService, but set selection from injected state
        service.households = [household("h1")]
        service.members["h1"] = [Membership(householdID: "h1", userID: "me", displayName: "Me", role: .owner)]
        service.shouldFailSubmit = false
        await store.bootstrap()
        service.shouldFailSubmit = true

        try queue.enqueue(PuzzleResult(
            householdID: "pending", authorUserID: "pending",
            gameID: "wordle", puzzleNumber: 1247, puzzleDay: store.today,
            rawScore: .guesses(used: 3, outOf: 6, solved: true), rawPayload: ""
        ))
        await store.drainPendingResults()
        XCTAssertEqual(try queue.count(), 1, "Failed submit should keep item in queue")
    }

    func testReactionReplacesOnSecondTap() async throws {
        let service = FakeCloudKitService(
            households: [household("h1")],
            members: ["h1": [Membership(householdID: "h1", userID: "me", displayName: "Me", role: .owner)]]
        )
        let store = HouseholdStore(service: service, notifications: FakeNotificationService(), now: { HouseholdStoreTests.fixedNow() })
        await store.bootstrap()
        try await store.react(to: "result-1", emoji: "🔥")
        XCTAssertEqual(store.myReaction(for: "result-1"), "🔥")
        try await store.react(to: "result-1", emoji: "🎉")
        XCTAssertEqual(store.myReaction(for: "result-1"), "🎉")
        XCTAssertEqual(store.reactions(for: "result-1").count, 1)
    }

    func testClearReactionRemovesIt() async throws {
        let service = FakeCloudKitService(
            households: [household("h1")],
            members: ["h1": [Membership(householdID: "h1", userID: "me", displayName: "Me", role: .owner)]]
        )
        let store = HouseholdStore(service: service, notifications: FakeNotificationService(), now: { HouseholdStoreTests.fixedNow() })
        await store.bootstrap()
        try await store.react(to: "result-1", emoji: "🔥")
        try await store.clearMyReaction(on: "result-1")
        XCTAssertNil(store.myReaction(for: "result-1"))
    }

    func testDeleteResultRemovesFromCloudAndLocal() async throws {
        let service = FakeCloudKitService(
            households: [household("h1")],
            members: ["h1": [Membership(householdID: "h1", userID: "me", displayName: "Me", role: .owner)]]
        )
        let store = HouseholdStore(service: service, notifications: FakeNotificationService(), now: { HouseholdStoreTests.fixedNow() })
        await store.bootstrap()

        let result = PuzzleResult(
            householdID: "h1", authorUserID: "me",
            gameID: "wordle", puzzleNumber: 1247, puzzleDay: store.today,
            rawScore: .guesses(used: 3, outOf: 6, solved: true),
            rawPayload: ""
        )
        try await service.submit(result)
        await store.refresh()
        XCTAssertEqual(store.todayResults.count, 1)

        try await store.deleteResult(result)
        XCTAssertEqual(store.todayResults.count, 0)
        let cloudRemaining = try await service.results(in: "h1", on: store.today)
        XCTAssertEqual(cloudRemaining.count, 0)
    }

    func testSpoilerMapHidesUntilSubmit() async throws {
        let service = FakeCloudKitService(
            households: [household("h1")],
            members: [
                "h1": [
                    Membership(householdID: "h1", userID: "me", displayName: "Me", role: .owner),
                    Membership(householdID: "h1", userID: "mom", displayName: "Mom"),
                ],
            ]
        )
        let store = HouseholdStore(service: service, notifications: FakeNotificationService(), now: { HouseholdStoreTests.fixedNow() })
        await store.bootstrap()

        try await service.submit(PuzzleResult(
            householdID: "h1", authorUserID: "mom",
            gameID: "wordle", puzzleNumber: 1247, puzzleDay: store.today,
            rawScore: .guesses(used: 2, outOf: 6, solved: true), rawPayload: ""
        ))
        await store.refresh()

        let momResult = store.todayResults.first!
        XCTAssertEqual(store.spoilerMap[momResult.id], .hidden)
    }
}

import Foundation
import CloudKit
import PuzzleCore
import PuzzleCloudKit

/// Fake service with toggleable failures for retry/queue tests.
final class FailingFakeService: CloudKitServicing, @unchecked Sendable {
    var userID: String = "me"
    var households: [Household] = []
    var members: [Household.ID: [Membership]] = [:]
    var shouldFailSubmit: Bool = false

    func currentUserRecordName() async throws -> String { userID }
    func households() async throws -> [Household] { households }
    func createHousehold(name: String, iconEmoji: String) async throws -> Household {
        throw CloudKitServiceError.accountUnavailable
    }
    func update(_ household: Household) async throws {
        throw CloudKitServiceError.accountUnavailable
    }
    func deleteHousehold(_ id: Household.ID) async throws {
        throw CloudKitServiceError.accountUnavailable
    }
    func shareURL(for household: Household) async throws -> URL {
        throw CloudKitServiceError.accountUnavailable
    }
    func acceptShare(_ metadata: CKShare.Metadata) async throws -> Household.ID {
        throw CloudKitServiceError.accountUnavailable
    }
    func ensureSyncSubscriptions() async {}
    func members(in householdID: Household.ID) async throws -> [Membership] {
        members[householdID] ?? []
    }
    func ensureMembership(in householdID: Household.ID) async throws -> Membership? {
        throw CloudKitServiceError.accountUnavailable
    }
    func removeMember(userID: String, from householdID: Household.ID) async throws {
        throw CloudKitServiceError.accountUnavailable
    }
    func submit(_ result: PuzzleResult) async throws {
        if shouldFailSubmit { throw CloudKitServiceError.accountUnavailable }
    }
    func deleteResult(_ resultID: PuzzleResult.ID, in householdID: Household.ID) async throws {}
    func results(in householdID: Household.ID, on day: PuzzleDay) async throws -> [PuzzleResult] {
        []
    }
    func recentResults(in householdID: Household.ID, since day: PuzzleDay) async throws -> [PuzzleResult] {
        []
    }
    func react(to resultID: PuzzleResult.ID, in householdID: Household.ID, emoji: String) async throws {}
    func clearReaction(to resultID: PuzzleResult.ID, in householdID: Household.ID) async throws {}
    func reactions(in householdID: Household.ID, since day: PuzzleDay) async throws -> [Reaction] { [] }
    func updateMembership(_ membership: Membership) async throws {
        throw CloudKitServiceError.accountUnavailable
    }
}

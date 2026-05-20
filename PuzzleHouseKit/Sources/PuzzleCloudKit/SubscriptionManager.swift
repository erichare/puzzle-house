import Foundation
import CloudKit
import PuzzleCore

public protocol SubscriptionManaging: Sendable {
    func ensureNewResultSubscription(for householdID: Household.ID, in database: CKDatabase) async throws
    func ensureDailyDigestSubscription(for householdID: Household.ID, in database: CKDatabase) async throws
}

public final class SubscriptionManager: SubscriptionManaging, @unchecked Sendable {

    public init() {}

    public func ensureNewResultSubscription(
        for householdID: Household.ID,
        in database: CKDatabase
    ) async throws {
        let id = "new-result-\(householdID)"
        let predicate = NSPredicate(format: "householdID == %@", householdID)
        let subscription = CKQuerySubscription(
            recordType: RecordType.puzzleResult,
            predicate: predicate,
            subscriptionID: id,
            options: [.firesOnRecordCreation]
        )
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true   // silent push; client decides UI
        subscription.notificationInfo = info

        try await save(subscription, to: database)
    }

    public func ensureDailyDigestSubscription(
        for householdID: Household.ID,
        in database: CKDatabase
    ) async throws {
        let id = "daily-digest-\(householdID)"
        let predicate = NSPredicate(format: "householdID == %@", householdID)
        let subscription = CKQuerySubscription(
            recordType: RecordType.dailyDigest,
            predicate: predicate,
            subscriptionID: id,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info

        try await save(subscription, to: database)
    }

    private func save(_ subscription: CKSubscription, to database: CKDatabase) async throws {
        do {
            let _ = try await database.modifySubscriptions(
                saving: [subscription], deleting: []
            )
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Existing subscription with that ID; treat as success.
            return
        }
    }
}

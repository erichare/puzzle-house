import Foundation
import os
import CloudKit
import PuzzleCore

/// High-level facade over CloudKit. The runtime targets (main app, Share Ext,
/// iMessage app) all talk through this surface so the underlying CKContainer
/// wiring stays in one place.
public protocol CloudKitServicing: Sendable {
    func currentUserRecordName() async throws -> String

    func households() async throws -> [Household]
    func createHousehold(name: String, iconEmoji: String) async throws -> Household
    func update(_ household: Household) async throws
    func deleteHousehold(_ id: Household.ID) async throws
    func shareURL(for household: Household) async throws -> URL
    func acceptShare(_ metadata: CKShare.Metadata) async throws -> Household.ID

    func members(in householdID: Household.ID) async throws -> [Membership]

    func submit(_ result: PuzzleResult) async throws
    func deleteResult(_ resultID: PuzzleResult.ID, in householdID: Household.ID) async throws
    func results(
        in householdID: Household.ID,
        on day: PuzzleDay
    ) async throws -> [PuzzleResult]
    func recentResults(
        in householdID: Household.ID,
        since day: PuzzleDay
    ) async throws -> [PuzzleResult]

    func react(
        to resultID: PuzzleResult.ID,
        in householdID: Household.ID,
        emoji: String
    ) async throws
    func clearReaction(
        to resultID: PuzzleResult.ID,
        in householdID: Household.ID
    ) async throws
    func reactions(
        in householdID: Household.ID,
        since day: PuzzleDay
    ) async throws -> [Reaction]

    func updateMembership(_ membership: Membership) async throws
}

public enum CloudKitServiceError: Error, Sendable {
    case missingContainer
    case accountUnavailable
    case householdNotFound(Household.ID)
    case zoneCreationFailed(Household.ID)
    case shareCreationFailed(Household.ID)
}

public final class CloudKitService: CloudKitServicing, @unchecked Sendable {
    public let container: CKContainer
    public let zoneManager: ZoneManaging
    public let shareManager: ShareManaging
    public let subscriptionManager: SubscriptionManaging
    public let writeQueue: OfflineWriteQueue?

    /// Cache: which database does each household ID live in? Populated lazily
    /// from `households()`. Reset on sign-out.
    private let scopeByHousehold = OSAllocatedUnfairLock<[Household.ID: CKDatabase.Scope]>(initialState: [:])

    public init(
        container: CKContainer = .default(),
        zoneManager: ZoneManaging? = nil,
        shareManager: ShareManaging? = nil,
        subscriptionManager: SubscriptionManaging? = nil,
        writeQueue: OfflineWriteQueue? = nil
    ) {
        self.container = container
        self.zoneManager = zoneManager ?? ZoneManager(container: container)
        self.shareManager = shareManager ?? ShareManager(container: container)
        self.subscriptionManager = subscriptionManager ?? SubscriptionManager()
        self.writeQueue = writeQueue
    }

    // MARK: - Identity

    public func currentUserRecordName() async throws -> String {
        let id = try await container.userRecordID()
        return id.recordName
    }

    // MARK: - Households

    public func households() async throws -> [Household] {
        async let owned = zoneManager.ownedZones()
        async let shared = zoneManager.sharedZones()
        let (ownedZones, sharedZones) = try await (owned, shared)

        var results: [Household] = []

        for zone in ownedZones where zone.zoneID.zoneName.hasPrefix("household-") {
            if let h = try? await fetchHousehold(zone: zone, database: container.privateCloudDatabase) {
                results.append(h)
                rememberScope(h.id, .private)
            }
        }
        for zone in sharedZones where zone.zoneID.zoneName.hasPrefix("household-") {
            if let h = try? await fetchHousehold(zone: zone, database: container.sharedCloudDatabase) {
                results.append(h)
                rememberScope(h.id, .shared)
            }
        }
        return results.sorted { $0.createdAt < $1.createdAt }
    }

    public func createHousehold(name: String, iconEmoji: String) async throws -> Household {
        let userID = try await currentUserRecordName()
        let household = Household(
            id: Household.newZoneName(),
            name: name,
            iconEmoji: iconEmoji,
            createdByUserID: userID
        )
        let zoneID = try await zoneManager.createZone(for: household.id)
        rememberScope(household.id, .private)

        let householdRecord = RecordMapping.householdRecord(from: household, zoneID: zoneID)
        let membership = Membership(
            householdID: household.id,
            userID: userID,
            displayName: "Me",
            role: .owner
        )
        let membershipRecord = RecordMapping.membershipRecord(from: membership, zoneID: zoneID)

        let _ = try await container.privateCloudDatabase.modifyRecords(
            saving: [householdRecord, membershipRecord], deleting: []
        )

        try? await subscriptionManager.ensureNewResultSubscription(
            for: household.id, in: container.privateCloudDatabase
        )
        return household
    }

    public func update(_ household: Household) async throws {
        let (database, zoneID) = try resolve(household.id)
        let record = RecordMapping.householdRecord(from: household, zoneID: zoneID)
        let _ = try await database.modifyRecords(
            saving: [record], deleting: [], savePolicy: .changedKeys
        )
    }

    public func deleteHousehold(_ id: Household.ID) async throws {
        let scope = scope(for: id) ?? .private
        if scope == .private {
            let zoneID = CKRecordZone.ID(zoneName: id, ownerName: CKCurrentUserDefaultName)
            try await zoneManager.deleteZone(zoneID)
        } else {
            // Participant leaving a shared household: remove the share from
            // our shared DB by deleting the zone reference. CloudKit cleans
            // up the participant relationship.
            let zoneID = CKRecordZone.ID(zoneName: id, ownerName: CKCurrentUserDefaultName)
            try await container.sharedCloudDatabase.modifyRecordZones(
                saving: [], deleting: [zoneID]
            )
        }
        scopeByHousehold.withLock { $0.removeValue(forKey: id) }
    }

    public func shareURL(for household: Household) async throws -> URL {
        try await shareManager.createShare(for: household)
    }

    public func acceptShare(_ metadata: CKShare.Metadata) async throws -> Household.ID {
        let id = try await shareManager.accept(shareMetadata: metadata)
        // Newly-accepted shared zones live in the shared DB; cache the scope
        // so subsequent `members`/`results` calls hit the right database.
        rememberScope(id, .shared)
        return id
    }

    // MARK: - Members

    public func members(in householdID: Household.ID) async throws -> [Membership] {
        let (database, zoneID) = try resolve(householdID)
        let query = CKQuery(
            recordType: RecordType.membership,
            predicate: NSPredicate(format: "householdID == %@", householdID)
        )
        let (matches, _) = try await database.records(matching: query, inZoneWith: zoneID)
        return matches.compactMap { _, result in
            guard case .success(let record) = result else { return nil }
            return try? RecordMapping.membership(from: record)
        }
    }

    // MARK: - Results

    public func submit(_ result: PuzzleResult) async throws {
        do {
            let (database, zoneID) = try resolve(result.householdID)
            let record = try RecordMapping.puzzleResultRecord(from: result, zoneID: zoneID)
            // `.changedKeys` overwrites an existing record with the same ID
            // instead of failing — important because we use deterministic IDs
            // so re-submits collide on purpose.
            let _ = try await database.modifyRecords(
                saving: [record], deleting: [], savePolicy: .changedKeys
            )
        } catch {
            // Queue for retry if we have a write queue.
            if let queue = writeQueue {
                _ = try? queue.enqueue(result)
            }
            throw error
        }
    }

    public func deleteResult(_ resultID: PuzzleResult.ID, in householdID: Household.ID) async throws {
        let (database, zoneID) = try resolve(householdID)
        let recordID = CKRecord.ID(recordName: resultID, zoneID: zoneID)
        let _ = try await database.modifyRecords(saving: [], deleting: [recordID])
    }

    public func results(
        in householdID: Household.ID,
        on day: PuzzleDay
    ) async throws -> [PuzzleResult] {
        let (database, zoneID) = try resolve(householdID)
        let predicate = NSPredicate(
            format: "householdID == %@ AND puzzleDayISO == %@",
            householdID, day.isoString
        )
        let query = CKQuery(recordType: RecordType.puzzleResult, predicate: predicate)
        let (matches, _) = try await database.records(matching: query, inZoneWith: zoneID)
        return matches.compactMap { _, r in
            guard case .success(let record) = r else { return nil }
            return try? RecordMapping.puzzleResult(from: record)
        }
    }

    public func recentResults(
        in householdID: Household.ID,
        since day: PuzzleDay
    ) async throws -> [PuzzleResult] {
        let (database, zoneID) = try resolve(householdID)
        // puzzleDayEpoch is Int(64) Queryable+Sortable in the CloudKit schema;
        // String fields don't support >= so we can't use puzzleDayISO here.
        let predicate = NSPredicate(
            format: "householdID == %@ AND puzzleDayEpoch >= %lld",
            householdID, day.epoch
        )
        let query = CKQuery(recordType: RecordType.puzzleResult, predicate: predicate)
        let (matches, _) = try await database.records(matching: query, inZoneWith: zoneID)
        return matches.compactMap { _, r in
            guard case .success(let record) = r else { return nil }
            return try? RecordMapping.puzzleResult(from: record)
        }
    }

    // MARK: - Reactions

    public func react(
        to resultID: PuzzleResult.ID,
        in householdID: Household.ID,
        emoji: String
    ) async throws {
        let userID = try await currentUserRecordName()
        let (database, zoneID) = try resolve(householdID)
        // Deterministic ID per (target, author) only — re-reacting with a
        // different emoji overwrites the same record, enforcing "one
        // reaction per person per result".
        let reactionID = Reaction.deterministicID(targetResultID: resultID, authorUserID: userID)
        let reaction = Reaction(
            id: reactionID,
            targetResultID: resultID,
            authorUserID: userID,
            emoji: emoji
        )
        let record = RecordMapping.reactionRecord(from: reaction, zoneID: zoneID)
        let _ = try await database.modifyRecords(
            saving: [record], deleting: [], savePolicy: .changedKeys
        )
    }

    public func clearReaction(
        to resultID: PuzzleResult.ID,
        in householdID: Household.ID
    ) async throws {
        let userID = try await currentUserRecordName()
        let (_, zoneID) = try resolve(householdID)
        let reactionID = Reaction.deterministicID(targetResultID: resultID, authorUserID: userID)
        let recordID = CKRecord.ID(recordName: reactionID, zoneID: zoneID)
        let database: CKDatabase = (scope(for: householdID) == .shared)
            ? container.sharedCloudDatabase
            : container.privateCloudDatabase
        let _ = try await database.modifyRecords(saving: [], deleting: [recordID])
    }

    public func reactions(
        in householdID: Household.ID,
        since day: PuzzleDay
    ) async throws -> [Reaction] {
        let (database, zoneID) = try resolve(householdID)
        // Reactions don't have a puzzleDay — filter by createdAt instead.
        let cutoff = day.startOfDay(in: TimeZone(identifier: "UTC") ?? .gmt)
        let predicate = NSPredicate(format: "createdAt >= %@", cutoff as NSDate)
        let query = CKQuery(recordType: RecordType.reaction, predicate: predicate)
        let (matches, _) = try await database.records(matching: query, inZoneWith: zoneID)
        return matches.compactMap { _, r in
            guard case .success(let record) = r else { return nil }
            return try? RecordMapping.reaction(from: record)
        }
    }

    public func updateMembership(_ membership: Membership) async throws {
        let (database, zoneID) = try resolve(membership.householdID)
        let record = RecordMapping.membershipRecord(from: membership, zoneID: zoneID)
        let _ = try await database.modifyRecords(
            saving: [record], deleting: [], savePolicy: .changedKeys
        )
    }

    // MARK: - Internals

    private func fetchHousehold(zone: CKRecordZone, database: CKDatabase) async throws -> Household? {
        let query = CKQuery(recordType: RecordType.household, predicate: NSPredicate(value: true))
        let (matches, _) = try await database.records(
            matching: query, inZoneWith: zone.zoneID, resultsLimit: 1
        )
        for (_, result) in matches {
            if case .success(let record) = result {
                return try RecordMapping.household(from: record)
            }
        }
        return nil
    }

    private func resolve(_ householdID: Household.ID) throws -> (CKDatabase, CKRecordZone.ID) {
        let scope = scope(for: householdID) ?? .private
        let database: CKDatabase = (scope == .shared)
            ? container.sharedCloudDatabase
            : container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(
            zoneName: householdID,
            ownerName: scope == .private ? CKCurrentUserDefaultName : (scope == .shared ? CKCurrentUserDefaultName : CKCurrentUserDefaultName)
        )
        return (database, zoneID)
    }

    private func rememberScope(_ householdID: Household.ID, _ scope: CKDatabase.Scope) {
        scopeByHousehold.withLock { $0[householdID] = scope }
    }

    private func scope(for householdID: Household.ID) -> CKDatabase.Scope? {
        scopeByHousehold.withLock { $0[householdID] }
    }
}

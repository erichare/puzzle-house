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
    /// Ensure silent-push subscriptions exist on both the private and shared
    /// databases, so a change by any member triggers a refresh on everyone
    /// else's device.
    func ensureSyncSubscriptions() async

    func members(in householdID: Household.ID) async throws -> [Membership]
    /// Idempotently writes the current user's membership into a household so
    /// they appear in the roster. Returns the membership it created, or nil if
    /// one already existed. Used when joining a shared house and to self-heal
    /// guests who joined before membership-on-join existed.
    func ensureMembership(in householdID: Household.ID) async throws -> Membership?
    /// Owner action: removes another member from a household — drops them as a
    /// CKShare participant and deletes their membership record.
    func removeMember(userID: String, from householdID: Household.ID) async throws

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

    /// Cache: which database + zone-owner does each household live in? Owned
    /// households are owned by the current user; shared households are owned by
    /// the *inviter*, so we must remember the real `ownerName` to build a
    /// correct `CKRecordZone.ID`. Populated from `households()`,
    /// `createHousehold`, and `acceptShare`. Reset on sign-out.
    private let zoneByHousehold = OSAllocatedUnfairLock<[Household.ID: ZoneRef]>(initialState: [:])

    private struct ZoneRef: Sendable {
        let scope: CKDatabase.Scope
        let ownerName: String
    }

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
                rememberZone(h.id, scope: .private, ownerName: zone.zoneID.ownerName)
            }
        }
        for zone in sharedZones where zone.zoneID.zoneName.hasPrefix("household-") {
            if let h = try? await fetchHousehold(zone: zone, database: container.sharedCloudDatabase) {
                results.append(h)
                rememberZone(h.id, scope: .shared, ownerName: zone.zoneID.ownerName)
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
        rememberZone(household.id, scope: .private, ownerName: CKCurrentUserDefaultName)

        let householdRecord = RecordMapping.householdRecord(from: household, zoneID: zoneID)
        let membership = Membership(
            id: Membership.deterministicID(householdID: household.id, userID: userID),
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
        let (database, zoneID) = try await resolve(household.id)
        let record = RecordMapping.householdRecord(from: household, zoneID: zoneID)
        let _ = try await database.modifyRecords(
            saving: [record], deleting: [], savePolicy: .changedKeys
        )
    }

    public func deleteHousehold(_ id: Household.ID) async throws {
        let ref = zoneRef(for: id)
        if (ref?.scope ?? .private) == .private {
            let zoneID = CKRecordZone.ID(zoneName: id, ownerName: CKCurrentUserDefaultName)
            try await zoneManager.deleteZone(zoneID)
        } else {
            // Participant leaving a shared household: first delete our own
            // membership record so we vanish from everyone else's roster, then
            // drop the shared-zone reference. CloudKit cleans up the
            // participant relationship.
            try? await deleteMyMembership(in: id)
            let zoneID = CKRecordZone.ID(
                zoneName: id, ownerName: ref?.ownerName ?? CKCurrentUserDefaultName
            )
            try await container.sharedCloudDatabase.modifyRecordZones(
                saving: [], deleting: [zoneID]
            )
        }
        zoneByHousehold.withLock { $0.removeValue(forKey: id) }
    }

    public func shareURL(for household: Household) async throws -> URL {
        try await shareManager.createShare(for: household)
    }

    public func acceptShare(_ metadata: CKShare.Metadata) async throws -> Household.ID {
        // Zone-wide share: the shared zone's identity comes from the share
        // record (a zone share has no hierarchical root record).
        let sharedZoneID = metadata.share.recordID.zoneID
        let id = try await shareManager.accept(shareMetadata: metadata)
        // Newly-accepted shared zones live in the shared DB and are owned by
        // the inviter — remember the real ownerName so subsequent
        // `members`/`results` calls build the correct zone ID.
        rememberZone(id, scope: .shared, ownerName: sharedZoneID.ownerName)
        // Subscribe to the shared DB so we're pushed about future changes.
        await ensureSyncSubscriptions()
        // Write our membership so we show up in everyone's roster immediately.
        _ = try? await ensureMembership(in: id)
        return id
    }

    public func ensureSyncSubscriptions() async {
        try? await subscriptionManager.ensureDatabaseSubscription(
            id: "private-db-changes", in: container.privateCloudDatabase
        )
        try? await subscriptionManager.ensureDatabaseSubscription(
            id: "shared-db-changes", in: container.sharedCloudDatabase
        )
    }

    // MARK: - Members

    public func members(in householdID: Household.ID) async throws -> [Membership] {
        let (database, zoneID) = try await resolve(householdID)
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

    public func ensureMembership(in householdID: Household.ID) async throws -> Membership? {
        let userID = try await currentUserRecordName()
        let (database, zoneID) = try await resolve(householdID)
        let recordID = CKRecord.ID(
            recordName: Membership.deterministicID(householdID: householdID, userID: userID),
            zoneID: zoneID
        )
        // Use a point lookup, not a CKQuery: a query's index can lag a record
        // written moments ago (e.g. the owner's membership right after they
        // create a house), and we must never clobber an existing membership —
        // that would downgrade the owner to "New member"/.member.
        if (try? await database.record(for: recordID)) != nil {
            return nil
        }
        let membership = Membership(
            id: recordID.recordName,
            householdID: householdID,
            userID: userID,
            displayName: "New member",
            role: .member
        )
        let record = RecordMapping.membershipRecord(from: membership, zoneID: zoneID)
        let _ = try await database.modifyRecords(
            saving: [record], deleting: [], savePolicy: .changedKeys
        )
        return membership
    }

    public func removeMember(userID: String, from householdID: Household.ID) async throws {
        let (database, zoneID) = try await resolve(householdID)
        // Drop them as a CKShare participant (best-effort — for a public
        // "anyone with the link" share this removes their explicit entry but
        // can't stop a re-tap of the same link; full lockout needs a new link).
        let rootID = CKRecord.ID(recordName: householdID, zoneID: zoneID)
        if let root = try? await database.record(for: rootID),
           let shareRef = root.share,
           let share = try? await database.record(for: shareRef.recordID) as? CKShare,
           let participant = share.participants.first(where: {
               $0.userIdentity.userRecordID?.recordName == userID
           }) {
            share.removeParticipant(participant)
            let _ = try await database.modifyRecords(
                saving: [share], deleting: [], savePolicy: .changedKeys
            )
        }
        // Delete their membership record(s) so they leave the roster.
        let toDelete = ((try? await members(in: householdID)) ?? [])
            .filter { $0.userID == userID }
            .map { CKRecord.ID(recordName: $0.id, zoneID: zoneID) }
        if !toDelete.isEmpty {
            let _ = try await database.modifyRecords(saving: [], deleting: toDelete)
        }
    }

    // MARK: - Results

    public func submit(_ result: PuzzleResult) async throws {
        do {
            let (database, zoneID) = try await resolve(result.householdID)
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
        let (database, zoneID) = try await resolve(householdID)
        let recordID = CKRecord.ID(recordName: resultID, zoneID: zoneID)
        let _ = try await database.modifyRecords(saving: [], deleting: [recordID])
    }

    public func results(
        in householdID: Household.ID,
        on day: PuzzleDay
    ) async throws -> [PuzzleResult] {
        let (database, zoneID) = try await resolve(householdID)
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
        let (database, zoneID) = try await resolve(householdID)
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
        let (database, zoneID) = try await resolve(householdID)
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
        let (database, zoneID) = try await resolve(householdID)
        let reactionID = Reaction.deterministicID(targetResultID: resultID, authorUserID: userID)
        let recordID = CKRecord.ID(recordName: reactionID, zoneID: zoneID)
        let _ = try await database.modifyRecords(saving: [], deleting: [recordID])
    }

    public func reactions(
        in householdID: Household.ID,
        since day: PuzzleDay
    ) async throws -> [Reaction] {
        let (database, zoneID) = try await resolve(householdID)
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
        let (database, zoneID) = try await resolve(membership.householdID)
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

    private func resolve(_ householdID: Household.ID) async throws -> (CKDatabase, CKRecordZone.ID) {
        let ref = try await resolveZoneRef(householdID)
        let database: CKDatabase = (ref.scope == .shared)
            ? container.sharedCloudDatabase
            : container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: householdID, ownerName: ref.ownerName)
        return (database, zoneID)
    }

    /// Resolve a household's database + zone-owner. Uses the cache populated by
    /// `households()`; if it's cold (a relaunch before any refresh ran, or a
    /// just-accepted share), repopulate by listing zones once, then fall back
    /// to assuming an owned zone in the private DB.
    private func resolveZoneRef(_ householdID: Household.ID) async throws -> ZoneRef {
        if let ref = zoneRef(for: householdID) { return ref }
        _ = try? await households()
        if let ref = zoneRef(for: householdID) { return ref }
        return ZoneRef(scope: .private, ownerName: CKCurrentUserDefaultName)
    }

    /// Deletes the current user's own membership record from a household — used
    /// when leaving a shared house so they disappear from the roster.
    private func deleteMyMembership(in householdID: Household.ID) async throws {
        let userID = try await currentUserRecordName()
        let (database, zoneID) = try await resolve(householdID)
        let mine = ((try? await members(in: householdID)) ?? [])
            .filter { $0.userID == userID }
            .map { CKRecord.ID(recordName: $0.id, zoneID: zoneID) }
        if !mine.isEmpty {
            let _ = try await database.modifyRecords(saving: [], deleting: mine)
        }
    }

    private func rememberZone(_ householdID: Household.ID, scope: CKDatabase.Scope, ownerName: String) {
        zoneByHousehold.withLock { $0[householdID] = ZoneRef(scope: scope, ownerName: ownerName) }
    }

    private func zoneRef(for householdID: Household.ID) -> ZoneRef? {
        zoneByHousehold.withLock { $0[householdID] }
    }
}

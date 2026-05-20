import Foundation
import CloudKit
import PuzzleCore

public protocol ShareManaging: Sendable {
    /// Creates a CKShare for the household root record. Returns the share URL
    /// suitable for sending via iMessage. The household must already exist in
    /// the user's private DB before calling this.
    func createShare(for household: Household) async throws -> URL

    /// Accepts an incoming share. Returns the household ID once the
    /// participant zone is available locally.
    func accept(shareMetadata: CKShare.Metadata) async throws -> Household.ID
}

public final class ShareManager: ShareManaging, @unchecked Sendable {
    public let container: CKContainer
    public let privateDatabase: CKDatabase

    public init(container: CKContainer = .default()) {
        self.container = container
        self.privateDatabase = container.privateCloudDatabase
    }

    public func createShare(for household: Household) async throws -> URL {
        let zoneID = CKRecordZone.ID(zoneName: household.id, ownerName: CKCurrentUserDefaultName)
        let householdRecord = RecordMapping.householdRecord(from: household, zoneID: zoneID)
        let share = CKShare(rootRecord: householdRecord)
        share[CKShare.SystemFieldKey.title] = "\(household.iconEmoji) \(household.name)" as CKRecordValue
        share.publicPermission = .none

        let result = try await privateDatabase.modifyRecords(
            saving: [householdRecord, share], deleting: []
        )
        if case .failure(let error)? = result.saveResults[share.recordID] {
            throw error
        }
        guard let url = share.url else {
            throw CloudKitServiceError.shareCreationFailed(household.id)
        }
        return url
    }

    public func accept(shareMetadata: CKShare.Metadata) async throws -> Household.ID {
        _ = try await container.accept(shareMetadata)
        // After acceptance, the household zone is in the sharedCloudDatabase.
        // The share metadata's root record points at the Household record.
        return shareMetadata.rootRecordID.recordName
    }
}

import Foundation
import CloudKit
import PuzzleCore

/// Per-household custom zone management. The household creator owns the zone
/// (private DB); participants receive a shared zone in the shared DB.
public protocol ZoneManaging: Sendable {
    func createZone(for householdID: Household.ID) async throws -> CKRecordZone.ID
    func deleteZone(_ zoneID: CKRecordZone.ID) async throws
    /// All zones owned by the user (private DB).
    func ownedZones() async throws -> [CKRecordZone]
    /// All zones shared *with* the user (shared DB).
    func sharedZones() async throws -> [CKRecordZone]
}

public final class ZoneManager: ZoneManaging, @unchecked Sendable {
    public let privateDatabase: CKDatabase
    public let sharedDatabase: CKDatabase

    public init(privateDatabase: CKDatabase, sharedDatabase: CKDatabase) {
        self.privateDatabase = privateDatabase
        self.sharedDatabase = sharedDatabase
    }

    public convenience init(container: CKContainer = .default()) {
        self.init(
            privateDatabase: container.privateCloudDatabase,
            sharedDatabase: container.sharedCloudDatabase
        )
    }

    public func createZone(for householdID: Household.ID) async throws -> CKRecordZone.ID {
        let zone = CKRecordZone(zoneName: householdID)
        let result = try await privateDatabase.modifyRecordZones(
            saving: [zone], deleting: []
        )
        guard let savedZoneResult = result.saveResults[zone.zoneID] else {
            throw CloudKitServiceError.zoneCreationFailed(householdID)
        }
        switch savedZoneResult {
        case .success(let saved):
            return saved.zoneID
        case .failure(let error):
            throw error
        }
    }

    public func deleteZone(_ zoneID: CKRecordZone.ID) async throws {
        let result = try await privateDatabase.modifyRecordZones(
            saving: [], deleting: [zoneID]
        )
        if let deleteResult = result.deleteResults[zoneID] {
            switch deleteResult {
            case .success: return
            case .failure(let error): throw error
            }
        }
    }

    public func ownedZones() async throws -> [CKRecordZone] {
        try await privateDatabase.allRecordZones()
    }

    public func sharedZones() async throws -> [CKRecordZone] {
        try await sharedDatabase.allRecordZones()
    }
}

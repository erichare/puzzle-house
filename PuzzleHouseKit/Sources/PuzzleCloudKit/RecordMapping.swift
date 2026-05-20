import Foundation
import CloudKit
import PuzzleCore

/// Conversion between domain models and CKRecord. Keeping this isolated means
/// every other CloudKit file can stay focused on orchestration.
public enum RecordType {
    public static let household = "Household"
    public static let membership = "Membership"
    public static let puzzleResult = "PuzzleResult"
    public static let reaction = "Reaction"
    public static let user = "User"
    public static let dailyDigest = "DailyDigest"
}

public enum RecordMappingError: Error, Sendable {
    case missingField(record: String, field: String)
    case decodeFailed(record: String, detail: String)
}

public enum RecordMapping {

    // MARK: - Household

    public static func householdRecord(from household: Household, zoneID: CKRecordZone.ID) -> CKRecord {
        let id = CKRecord.ID(recordName: household.id, zoneID: zoneID)
        let record = CKRecord(recordType: RecordType.household, recordID: id)
        record["name"] = household.name as CKRecordValue
        record["iconEmoji"] = household.iconEmoji as CKRecordValue
        record["timeZoneIdentifier"] = household.timeZoneIdentifier as CKRecordValue
        record["createdByUserID"] = household.createdByUserID as CKRecordValue
        record["createdAt"] = household.createdAt as CKRecordValue
        return record
    }

    public static func household(from record: CKRecord) throws -> Household {
        guard let name = record["name"] as? String,
              let icon = record["iconEmoji"] as? String,
              let tz = record["timeZoneIdentifier"] as? String,
              let createdBy = record["createdByUserID"] as? String,
              let createdAt = record["createdAt"] as? Date
        else {
            throw RecordMappingError.missingField(record: RecordType.household, field: "core")
        }
        return Household(
            id: record.recordID.recordName,
            name: name,
            iconEmoji: icon,
            timeZoneIdentifier: tz,
            createdByUserID: createdBy,
            createdAt: createdAt
        )
    }

    // MARK: - Membership

    public static func membershipRecord(from membership: Membership, zoneID: CKRecordZone.ID) -> CKRecord {
        let id = CKRecord.ID(recordName: membership.id, zoneID: zoneID)
        let record = CKRecord(recordType: RecordType.membership, recordID: id)
        record["householdID"] = membership.householdID as CKRecordValue
        record["userID"] = membership.userID as CKRecordValue
        record["displayName"] = membership.displayName as CKRecordValue
        record["avatarEmoji"] = membership.avatarEmoji as CKRecordValue
        record["role"] = membership.role.rawValue as CKRecordValue
        record["joinedAt"] = membership.joinedAt as CKRecordValue
        if let photo = membership.avatarPhotoData {
            record["avatarPhotoData"] = photo as CKRecordValue
        }
        return record
    }

    public static func membership(from record: CKRecord) throws -> Membership {
        guard let householdID = record["householdID"] as? String,
              let userID = record["userID"] as? String,
              let displayName = record["displayName"] as? String,
              let avatar = record["avatarEmoji"] as? String,
              let roleRaw = record["role"] as? String,
              let role = Membership.Role(rawValue: roleRaw),
              let joinedAt = record["joinedAt"] as? Date
        else {
            throw RecordMappingError.missingField(record: RecordType.membership, field: "core")
        }
        return Membership(
            id: record.recordID.recordName,
            householdID: householdID,
            userID: userID,
            displayName: displayName,
            avatarEmoji: avatar,
            avatarPhotoData: record["avatarPhotoData"] as? Data,
            role: role,
            joinedAt: joinedAt
        )
    }

    // MARK: - PuzzleResult

    public static func puzzleResultRecord(
        from result: PuzzleResult,
        zoneID: CKRecordZone.ID
    ) throws -> CKRecord {
        let id = CKRecord.ID(recordName: result.id, zoneID: zoneID)
        let record = CKRecord(recordType: RecordType.puzzleResult, recordID: id)
        record["householdID"] = result.householdID as CKRecordValue
        record["authorUserID"] = result.authorUserID as CKRecordValue
        record["gameID"] = result.gameID as CKRecordValue
        record["puzzleNumber"] = result.puzzleNumber as CKRecordValue
        record["puzzleDayISO"] = result.puzzleDay.isoString as CKRecordValue
        record["puzzleDayEpoch"] = NSNumber(value: result.puzzleDay.epoch)
        record["rawPayload"] = result.rawPayload as CKRecordValue
        record["submittedAt"] = result.submittedAt as CKRecordValue
        if let grid = result.gridData {
            record["gridData"] = grid as CKRecordValue
        }
        record["rawScoreEncoded"] = try JSONEncoder().encode(result.rawScore) as CKRecordValue
        return record
    }

    public static func puzzleResult(from record: CKRecord) throws -> PuzzleResult {
        guard let householdID = record["householdID"] as? String,
              let authorUserID = record["authorUserID"] as? String,
              let gameID = record["gameID"] as? String,
              let puzzleNumber = record["puzzleNumber"] as? Int,
              let rawPayload = record["rawPayload"] as? String,
              let submittedAt = record["submittedAt"] as? Date,
              let scoreData = record["rawScoreEncoded"] as? Data
        else {
            throw RecordMappingError.missingField(record: RecordType.puzzleResult, field: "core")
        }
        // Prefer the newer epoch field; fall back to ISO string for records
        // written before the migration.
        let day: PuzzleDay
        if let epoch = (record["puzzleDayEpoch"] as? NSNumber)?.int64Value {
            day = PuzzleDay(epoch: epoch)
        } else if let dayISO = record["puzzleDayISO"] as? String,
                  let parsed = parseISODay(dayISO) {
            day = parsed
        } else {
            throw RecordMappingError.missingField(record: RecordType.puzzleResult, field: "puzzleDay")
        }
        let rawScore: RawScore
        do {
            rawScore = try JSONDecoder().decode(RawScore.self, from: scoreData)
        } catch {
            throw RecordMappingError.decodeFailed(
                record: RecordType.puzzleResult,
                detail: "rawScore: \(error)"
            )
        }
        return PuzzleResult(
            id: record.recordID.recordName,
            householdID: householdID,
            authorUserID: authorUserID,
            gameID: gameID,
            puzzleNumber: puzzleNumber,
            puzzleDay: day,
            rawScore: rawScore,
            rawPayload: rawPayload,
            gridData: record["gridData"] as? String,
            submittedAt: submittedAt
        )
    }

    // MARK: - Reaction

    public static func reactionRecord(from reaction: Reaction, zoneID: CKRecordZone.ID) -> CKRecord {
        let id = CKRecord.ID(recordName: reaction.id, zoneID: zoneID)
        let record = CKRecord(recordType: RecordType.reaction, recordID: id)
        record["targetResultID"] = reaction.targetResultID as CKRecordValue
        record["authorUserID"] = reaction.authorUserID as CKRecordValue
        record["emoji"] = reaction.emoji as CKRecordValue
        record["createdAt"] = reaction.createdAt as CKRecordValue
        return record
    }

    public static func reaction(from record: CKRecord) throws -> Reaction {
        guard let targetResultID = record["targetResultID"] as? String,
              let authorUserID = record["authorUserID"] as? String,
              let emoji = record["emoji"] as? String,
              let createdAt = record["createdAt"] as? Date
        else {
            throw RecordMappingError.missingField(record: RecordType.reaction, field: "core")
        }
        return Reaction(
            id: record.recordID.recordName,
            targetResultID: targetResultID,
            authorUserID: authorUserID,
            emoji: emoji,
            createdAt: createdAt
        )
    }

    // MARK: - Helpers

    static func parseISODay(_ s: String) -> PuzzleDay? {
        let parts = s.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              let d = Int(parts[2])
        else { return nil }
        return PuzzleDay(year: y, month: m, day: d)
    }
}

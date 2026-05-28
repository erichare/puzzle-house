import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import CloudKit
import PuzzleCore

public protocol ShareManaging: Sendable {
    /// Creates a CKShare for the household root record. Returns the share URL
    /// suitable for sending via iMessage. The household must already exist in
    /// the user's private DB before calling this.
    func createShare(for household: Household) async throws -> URL

    /// Fetch-or-create the household's CKShare and return it with its
    /// container, ready to hand to a `CKShareTransferRepresentation` /
    /// `ShareLink`. The household must exist in the caller's private DB.
    /// This is the single source of truth for share lifecycle — both the
    /// modern share UI and `createShare(for:)` go through it.
    func shareForSharing(_ household: Household) async throws -> (CKShare, CKContainer)

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
        let (share, _) = try await shareForSharing(household)
        guard let url = share.url else {
            throw CloudKitServiceError.shareCreationFailed(household.id)
        }
        return url
    }

    public func shareForSharing(_ household: Household) async throws -> (CKShare, CKContainer) {
        let zoneID = CKRecordZone.ID(zoneName: household.id, ownerName: CKCurrentUserDefaultName)

        // We share the *entire household zone*, not just the Household record.
        // A record-level share (`CKShare(rootRecord:)`) only shares the root
        // and records linked to it by `parent` reference — and our Membership /
        // PuzzleResult / Reaction records aren't parented, so they never synced
        // to participants. A zone-wide share shares every record in the zone,
        // current and future, in both directions. The zone-wide share lives at
        // the reserved record name `CKRecordNameZoneWideShare`.
        let shareRecordID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)

        // Reuse an existing zone-wide share, refreshing its metadata.
        if let existing = try? await privateDatabase.record(for: shareRecordID) as? CKShare {
            try await refreshShareMetadataIfNeeded(existing, household: household)
            return (existing, container)
        }

        // Migrate off any legacy hierarchical share on the Household root — it
        // shared only that one record, and would otherwise linger in the zone.
        let rootID = CKRecord.ID(recordName: household.id, zoneID: zoneID)
        if let root = try? await privateDatabase.record(for: rootID), let oldShare = root.share {
            _ = try? await privateDatabase.modifyRecords(saving: [], deleting: [oldShare.recordID])
        }

        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = household.name as CKRecordValue
        share[CKShare.SystemFieldKey.shareType] = "house.puzzle.household" as CKRecordValue
        if let thumb = ShareManager.renderThumbnail(emoji: household.iconEmoji) {
            share[CKShare.SystemFieldKey.thumbnailImageData] = thumb as CKRecordValue
        }
        // Anyone with the URL can accept and contribute (read + write). The URL
        // itself is the secret; the owner can still see + remove participants
        // from the system share UI and our Manage Members screen.
        share.publicPermission = .readWrite

        let result = try await privateDatabase.modifyRecords(
            saving: [share], deleting: [], savePolicy: .ifServerRecordUnchanged
        )
        switch result.saveResults[share.recordID] {
        case .success(let saved):
            // Return the server's copy — it's the one carrying the share URL.
            return ((saved as? CKShare) ?? share, container)
        case .failure(let error):
            throw error
        case nil:
            throw CloudKitServiceError.shareCreationFailed(household.id)
        }
    }

    /// Bring an existing zone-wide share's permission/title/thumbnail up to date
    /// without recreating it.
    private func refreshShareMetadataIfNeeded(_ share: CKShare, household: Household) async throws {
        var dirty = false
        if share.publicPermission != .readWrite {
            share.publicPermission = .readWrite
            dirty = true
        }
        if (share[CKShare.SystemFieldKey.title] as? String) != household.name {
            share[CKShare.SystemFieldKey.title] = household.name as CKRecordValue
            dirty = true
        }
        if let thumb = ShareManager.renderThumbnail(emoji: household.iconEmoji),
           (share[CKShare.SystemFieldKey.thumbnailImageData] as? Data) != thumb {
            share[CKShare.SystemFieldKey.thumbnailImageData] = thumb as CKRecordValue
            dirty = true
        }
        guard dirty else { return }
        let result = try await privateDatabase.modifyRecords(
            saving: [share], deleting: [], savePolicy: .changedKeys
        )
        if case .failure(let error)? = result.saveResults[share.recordID] {
            throw error
        }
    }

    public func accept(shareMetadata: CKShare.Metadata) async throws -> Household.ID {
        _ = try await container.accept(shareMetadata)
        // Zone-wide share: the household ID is the shared zone's name (a
        // zone-wide share has no hierarchical root record, so we can't use
        // `rootRecordID`). After acceptance the zone lives in sharedCloudDatabase.
        return shareMetadata.share.recordID.zoneID.zoneName
    }

    /// Renders the household icon emoji onto a 256×256 peach gradient — used
    /// as the CKShare thumbnail so the iMessage bubble previews the house
    /// instead of a generic iCloud icon. Returns PNG data; pure CoreGraphics
    /// so it works on iOS, iPadOS, and macOS Catalyst alike. Public so the
    /// SwiftUI invite sheet can re-use it for its SharePreview image.
    public static func renderThumbnail(emoji: String) -> Data? {
        let side = 256
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Background gradient (matches the Today view's peach).
        let top = CGColor(srgbRed: 1.00, green: 0.91, blue: 0.83, alpha: 1)
        let bot = CGColor(srgbRed: 1.00, green: 0.69, blue: 0.53, alpha: 1)
        guard let gradient = CGGradient(
            colorsSpace: colorSpace, colors: [top, bot] as CFArray, locations: [0, 1]
        ) else { return nil }
        let radius: CGFloat = 56
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: side), end: .zero, options: [])
        ctx.restoreGState()

        // Emoji glyph centered.
        let font = CTFontCreateWithName("AppleColorEmoji" as CFString, 160, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: emoji, attributes: attrs))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        ctx.textPosition = CGPoint(x: CGFloat(side) / 2 - width / 2,
                                   y: CGFloat(side) / 2 - (ascent + descent) / 2 - 8)
        CTLineDraw(line, ctx)

        guard let image = ctx.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

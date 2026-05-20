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
        let recordID = CKRecord.ID(recordName: household.id, zoneID: zoneID)

        // Fetch the live household record so we have its serverChangeTag.
        // Saving a freshly-constructed CKRecord (no tag) alongside the share
        // causes CloudKit to throw "Atomic failure" because the server record
        // already exists.
        let existingRecord = try await privateDatabase.record(for: recordID)

        // If a share already exists for this record, just return its URL —
        // creating a second share on the same root is rejected by CloudKit.
        if let shareReference = existingRecord.share {
            if let share = try? await privateDatabase.record(for: shareReference.recordID) as? CKShare,
               let url = share.url {
                return url
            }
        }

        let share = CKShare(rootRecord: existingRecord)
        share[CKShare.SystemFieldKey.title] = household.name as CKRecordValue
        share[CKShare.SystemFieldKey.shareType] = "house.puzzle.household" as CKRecordValue
        if let thumb = ShareManager.renderThumbnail(emoji: household.iconEmoji) {
            share[CKShare.SystemFieldKey.thumbnailImageData] = thumb as CKRecordValue
        }
        share.publicPermission = .none

        let result = try await privateDatabase.modifyRecords(
            saving: [existingRecord, share], deleting: [], savePolicy: .ifServerRecordUnchanged
        )
        if case .failure(let error)? = result.saveResults[share.recordID] {
            throw error
        }
        if case .failure(let error)? = result.saveResults[existingRecord.recordID] {
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

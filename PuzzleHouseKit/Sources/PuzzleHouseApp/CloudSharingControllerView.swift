import SwiftUI
import CloudKit
#if canImport(UIKit)
import UIKit
#endif
import PuzzleCore
import PuzzleCloudKit

#if canImport(UIKit)

/// SwiftUI wrapper around Apple's `UICloudSharingController`. This is the
/// canonical CloudKit-sharing UI — it handles the entire lifecycle:
/// fetching or creating the CKShare, presenting the system share sheet
/// (Messages / Mail / AirDrop), letting the owner manage participants /
/// permissions, and saving the resulting share back to CloudKit. The plain
/// `ShareLink(item: url)` approach we used before relied on a bare URL,
/// which iCloud sometimes refuses to honor — UICloudSharingController is
/// the contract iCloud expects for share invitations.
public struct CloudSharingControllerView: UIViewControllerRepresentable {
    public let household: Household
    public let container: CKContainer
    public let onSave: () -> Void
    public let onStop: () -> Void
    public let onError: (Error) -> Void

    public init(
        household: Household,
        container: CKContainer = .default(),
        onSave: @escaping () -> Void = {},
        onStop: @escaping () -> Void = {},
        onError: @escaping (Error) -> Void = { _ in }
    ) {
        self.household = household
        self.container = container
        self.onSave = onSave
        self.onStop = onStop
        self.onError = onError
    }

    public func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController { _, completion in
            Task {
                do {
                    let (share, container) = try await context.coordinator.prepareShare()
                    await MainActor.run {
                        completion(share, container, nil)
                    }
                } catch {
                    await MainActor.run {
                        completion(nil, nil, error)
                    }
                }
            }
        }
        controller.availablePermissions = [.allowPublic, .allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }

    public func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(
            household: household,
            container: container,
            onSave: onSave,
            onStop: onStop,
            onError: onError
        )
    }

    public final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let household: Household
        let container: CKContainer
        let onSave: () -> Void
        let onStop: () -> Void
        let onError: (Error) -> Void

        init(
            household: Household,
            container: CKContainer,
            onSave: @escaping () -> Void,
            onStop: @escaping () -> Void,
            onError: @escaping (Error) -> Void
        ) {
            self.household = household
            self.container = container
            self.onSave = onSave
            self.onStop = onStop
            self.onError = onError
        }

        /// Fetches the live Household root record and either reuses its
        /// existing CKShare or constructs a fresh unsaved one. Either way
        /// UICloudSharingController takes over saving + participant
        /// management from here.
        func prepareShare() async throws -> (CKShare, CKContainer) {
            let zoneID = CKRecordZone.ID(
                zoneName: household.id, ownerName: CKCurrentUserDefaultName
            )
            let recordID = CKRecord.ID(recordName: household.id, zoneID: zoneID)
            let db = container.privateCloudDatabase
            let root = try await db.record(for: recordID)

            if let shareReference = root.share,
               let existing = try await db.record(for: shareReference.recordID) as? CKShare {
                return (existing, container)
            }

            let share = CKShare(rootRecord: root)
            share[CKShare.SystemFieldKey.title] = household.name as CKRecordValue
            share[CKShare.SystemFieldKey.shareType] = "house.puzzle.household" as CKRecordValue
            if let thumb = ShareManager.renderThumbnail(emoji: household.iconEmoji) {
                share[CKShare.SystemFieldKey.thumbnailImageData] = thumb as CKRecordValue
            }
            // Pre-set readWrite so the controller's initial permission
            // toggle matches what we want. The user can still adjust before
            // sending.
            share.publicPermission = .readWrite
            return (share, container)
        }

        public func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            onSave()
        }

        public func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onStop()
        }

        public func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            onError(error)
        }

        public func itemTitle(for csc: UICloudSharingController) -> String? {
            household.name
        }

        public func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
            ShareManager.renderThumbnail(emoji: household.iconEmoji)
        }

        public func itemType(for csc: UICloudSharingController) -> String? {
            // Apple's docs recommend "com.apple.cloudkit.share" for the
            // generic share UTI.
            "com.apple.cloudkit.share"
        }
    }
}

#endif

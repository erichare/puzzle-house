import Foundation
import CloudKit
#if canImport(UIKit)
import UIKit
#endif
import PuzzleCore
import PuzzleCloudKit

#if canImport(UIKit)

/// Presents Apple's native `UICloudSharingController` for a Puzzle House
/// household.
///
/// Why this isn't a `UIViewControllerRepresentable`: when the controller is
/// embedded inside a SwiftUI `.sheet`, iOS doesn't run its real
/// presentation lifecycle and the share sheet renders blank with no
/// actionable buttons. Apple's CKShare APIs expect the controller to be
/// presented modally through `UIViewController.present(_:animated:)` from
/// the topmost VC in the active window. This class does exactly that —
/// SwiftUI views just allocate one and call `present()`.
@MainActor
public final class CloudSharingPresenter: NSObject, UICloudSharingControllerDelegate {
    public let household: Household
    public let container: CKContainer
    public var onDismiss: () -> Void
    public var onError: (Error) -> Void

    /// `UICloudSharingController.delegate` is `weak`, so without an external
    /// reference the presenter would get deallocated the moment we return
    /// from `present()`. Owning views keep an `@State` reference to the
    /// active presenter until `onDismiss` fires.
    public init(
        household: Household,
        container: CKContainer = .default(),
        onDismiss: @escaping () -> Void = {},
        onError: @escaping (Error) -> Void = { _ in }
    ) {
        self.household = household
        self.container = container
        self.onDismiss = onDismiss
        self.onError = onError
    }

    public func present() {
        let controller = UICloudSharingController { [weak self] _, completion in
            guard let self else {
                completion(nil, nil, NSError(domain: "PuzzleHouse", code: -1))
                return
            }
            Task { @MainActor in
                do {
                    let (share, container) = try await self.prepareShare()
                    completion(share, container, nil)
                } catch {
                    completion(nil, nil, error)
                }
            }
        }
        controller.availablePermissions = [.allowPublic, .allowPrivate, .allowReadWrite]
        controller.delegate = self

        guard let topmost = CloudSharingPresenter.topmostViewController() else {
            onError(NSError(
                domain: "PuzzleHouse",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Couldn't find a view controller to present from."]
            ))
            return
        }
        topmost.present(controller, animated: true)
    }

    // MARK: - Share preparation

    private func prepareShare() async throws -> (CKShare, CKContainer) {
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
        share.publicPermission = .readWrite
        return (share, container)
    }

    // MARK: - Topmost view controller

    private static func topmostViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first
        guard var top = window?.rootViewController else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    // MARK: - UICloudSharingControllerDelegate

    public func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        onDismiss()
    }

    public func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        onDismiss()
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
        "com.apple.cloudkit.share"
    }
}

#endif

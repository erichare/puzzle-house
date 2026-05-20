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
/// Two init paths are used depending on share state:
/// - **Existing share** → `init(share:container:)` is the direct path. The
///   controller manages participants on an already-saved share.
/// - **No share yet** → `init(preparationHandler:)` lets us create a fresh
///   CKShare lazily; the controller saves it (with the root record) when
///   the user picks recipients.
///
/// We pre-resolve which path to take before presentation so the controller
/// has the cleanest possible setup — using `preparationHandler` for an
/// existing share has historically been unreliable.
@MainActor
public final class CloudSharingPresenter: NSObject, UICloudSharingControllerDelegate {
    public let household: Household
    public let container: CKContainer
    public var onDismiss: () -> Void
    public var onError: (Error) -> Void

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
        Task { @MainActor in
            do {
                let controller = try await makeController()
                controller.availablePermissions = [.allowPublic, .allowReadWrite]
                controller.delegate = self

                guard let topmost = CloudSharingPresenter.topmostViewController() else {
                    surface(error: NSError(
                        domain: "PuzzleHouse",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Couldn't find a view controller to present from."]
                    ))
                    return
                }
                topmost.present(controller, animated: true)
            } catch {
                surface(error: error)
            }
        }
    }

    // MARK: - Controller construction

    private func makeController() async throws -> UICloudSharingController {
        if let (existingShare, container) = try await loadExistingShare() {
            // Already saved — use the synchronous init so the controller
            // can immediately render participants + permissions.
            return UICloudSharingController(share: existingShare, container: container)
        }

        // No share yet — defer creation to the preparationHandler so the
        // controller saves the share + root together when the user confirms.
        let household = self.household
        let container = self.container
        return UICloudSharingController { [weak self] _, completion in
            Task { @MainActor in
                guard let self else {
                    completion(nil, nil, NSError(
                        domain: "PuzzleHouse", code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "Share presenter was deallocated."]
                    ))
                    return
                }
                do {
                    let (share, container) = try await self.createFreshShare(
                        household: household, container: container
                    )
                    completion(share, container, nil)
                } catch {
                    completion(nil, nil, error)
                }
            }
        }
    }

    /// Looks up an active CKShare for the household, if any. Returns nil
    /// (not an error) when no share exists yet — the caller will create
    /// one via the preparationHandler path.
    private func loadExistingShare() async throws -> (CKShare, CKContainer)? {
        let zoneID = CKRecordZone.ID(
            zoneName: household.id, ownerName: CKCurrentUserDefaultName
        )
        let recordID = CKRecord.ID(recordName: household.id, zoneID: zoneID)
        let db = container.privateCloudDatabase
        let root = try await db.record(for: recordID)

        guard let shareReference = root.share else { return nil }
        guard let share = try await db.record(for: shareReference.recordID) as? CKShare else {
            return nil
        }
        return (share, container)
    }

    private func createFreshShare(
        household: Household,
        container: CKContainer
    ) async throws -> (CKShare, CKContainer) {
        let zoneID = CKRecordZone.ID(
            zoneName: household.id, ownerName: CKCurrentUserDefaultName
        )
        let recordID = CKRecord.ID(recordName: household.id, zoneID: zoneID)
        let db = container.privateCloudDatabase
        let root = try await db.record(for: recordID)

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

    // MARK: - Error surface

    /// CloudKit share errors are easy to lose if we only relay them via
    /// callbacks — the SwiftUI sheet can be torn down by the time the
    /// presenter's onError fires. As a fallback, present a UIAlert from the
    /// topmost VC so the user can see what went wrong.
    private func surface(error: Error) {
        onError(error)
        let alert = UIAlertController(
            title: "Couldn't open share",
            message: String(describing: error),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        if let topmost = CloudSharingPresenter.topmostViewController() {
            topmost.present(alert, animated: true)
        }
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
        // The controller's built-in alert may not always fire; surface to be safe.
        surface(error: error)
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

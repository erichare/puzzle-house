import CloudKit

/// Accept an incoming CloudKit share now if the store is ready; otherwise stash
/// it for `PuzzleHouseRootView` (iOS) / `RootMacView` (macOS) to drain after
/// `bootstrap()` via ``HouseholdStore/drainPendingShareIfNeeded()``.
///
/// Lives in the shared package so both the iOS scene delegate
/// (`ShareSceneDelegate`) and the macOS `NSApplicationDelegate` accept invites
/// through one identical code path — keeping share acceptance in sync across
/// platforms. Only touches `PuzzleHouseSharedStore` and
/// ``HouseholdStore/acceptIncomingShare(_:)``, both already in this module.
@MainActor
public func acceptOrStashIncomingShare(_ metadata: CKShare.Metadata) {
    if let store = PuzzleHouseSharedStore.current {
        Task { await store.acceptIncomingShare(metadata) }
    } else {
        PuzzleHouseSharedStore.pendingShareMetadata = metadata
    }
}

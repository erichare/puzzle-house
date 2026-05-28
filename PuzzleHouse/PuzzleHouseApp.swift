import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import CloudKit
import PuzzleCloudKit
import PuzzleHouseApp

@main
struct PuzzleHouseAppEntry: App {
    @State private var store: HouseholdStore
    @Environment(\.scenePhase) private var scenePhase
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        let appGroup = AppGroupContainer(appGroupIdentifier: PuzzleHouseIdentifiers.appGroup)
        let queue = appGroup.map { OfflineWriteQueue(container: $0) }
        let widgetStore = appGroup.map { WidgetSnapshotStore(container: $0) }
        let service = CloudKitService(writeQueue: queue)
        let store = HouseholdStore(
            service: service, queue: queue, widgetStore: widgetStore
        )
        _store = State(wrappedValue: store)
        PuzzleHouseSharedStore.current = store
    }

    var body: some Scene {
        WindowGroup {
            PuzzleHouseRootView(store: store)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        await store.drainPendingShareIfNeeded()
                        await store.drainPendingResults()
                        await store.refresh()
                    }
                }
        }
    }
}

#if canImport(UIKit)
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register for silent CloudKit pushes. The actual auth prompt is
        // separately gated by NotificationService.requestAuthorization() in
        // Settings — this call only enables APNs delivery for content-only
        // (silent) pushes, which don't require user permission.
        application.registerForRemoteNotifications()
        return true
    }

    /// SwiftUI uses a scene-based lifecycle, so iOS delivers CloudKit share
    /// acceptance to a *scene* delegate, not this app delegate. Vend one
    /// programmatically (so we don't have to hand-author a scene manifest that
    /// fights `UIApplicationSceneManifest_Generation`). SwiftUI's `WindowGroup`
    /// keeps rendering — `ShareSceneDelegate` never creates its own window, it
    /// only forwards the share metadata.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = ShareSceneDelegate.self
        return config
    }

    /// Fallback share handler. On a scene-based SwiftUI app iOS routes share
    /// acceptance to `ShareSceneDelegate` instead, so this rarely (if ever)
    /// fires — but it's harmless to keep and routes the same way.
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task { @MainActor in acceptOrStashIncomingShare(cloudKitShareMetadata) }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let payload = userInfo as? [String: NSObject] ?? [:]
        guard let cloudNotification = CKNotification(fromRemoteNotificationDictionary: payload),
              cloudNotification is CKQueryNotification || cloudNotification is CKDatabaseNotification
        else {
            completionHandler(.noData)
            return
        }
        Task { @MainActor in
            await PuzzleHouseSharedStore.current?.handleRemoteCloudKitNotification()
            completionHandler(.newData)
        }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // We don't need to send the token anywhere — CloudKit manages tokens
        // for us. The registration just kicks the OS into delivering pushes.
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Not fatal — silent pushes won't fire, but the app still works.
        // Common in Simulator (no APNs) or when push entitlement isn't fully
        // provisioned. We surface this via Settings > Diagnostics if needed.
    }
}

/// Receives CloudKit share acceptance for the scene-based SwiftUI lifecycle.
/// It deliberately does **not** create a window — SwiftUI's `WindowGroup` owns
/// the UI; this delegate only forwards the share metadata.
final class ShareSceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Cold launch: the app wasn't running when the invite was tapped, so the
    /// metadata rides in on the connection options (the warm callback below is
    /// NOT called in this case). Stash it; `PuzzleHouseRootView` drains it once
    /// `bootstrap()` has run, so the accept happens against a ready store.
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            Task { @MainActor in
                PuzzleHouseSharedStore.pendingShareMetadata = metadata
            }
        }
    }

    /// Warm: the app was already running (foreground or background) when the
    /// invite link was tapped.
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task { @MainActor in acceptOrStashIncomingShare(cloudKitShareMetadata) }
    }
}

/// Accept the share now if the store is ready; otherwise stash it for the
/// root view to drain after `bootstrap()`.
@MainActor
private func acceptOrStashIncomingShare(_ metadata: CKShare.Metadata) {
    if let store = PuzzleHouseSharedStore.current {
        Task { await store.acceptIncomingShare(metadata) }
    } else {
        PuzzleHouseSharedStore.pendingShareMetadata = metadata
    }
}
#endif

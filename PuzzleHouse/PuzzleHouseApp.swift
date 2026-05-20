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

    /// Silent CloudKit pushes land here. We refresh data and then run the
    /// "solved before you" / "today's champion" checks, both of which schedule
    /// local notifications if anything is new.
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
#endif

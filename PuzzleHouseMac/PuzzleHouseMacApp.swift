import SwiftUI
import AppKit
import CloudKit
import PuzzleCloudKit
import PuzzleHouseApp

/// Native macOS entry point. The store wiring in `init()` is **identical** to
/// the iOS app (`PuzzleHouse/PuzzleHouseApp.swift`) so both platforms share one
/// `HouseholdStore` / CloudKit configuration. The macOS-specific differences are
/// the lifecycle adaptor (`NSApplicationDelegate` instead of
/// `UIApplicationDelegate`) and the absence of a scene delegate — on macOS,
/// CloudKit share acceptance and silent pushes land directly on the app delegate.
@main
struct PuzzleHouseMacApp: App {
    @State private var store: HouseholdStore
    @State private var coordinator = MacUICoordinator()
    @Environment(\.scenePhase) private var scenePhase
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate

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
        WindowGroup(id: "main") {
            RootMacView(store: store, coordinator: coordinator)
                .frame(minWidth: 820, minHeight: 560)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        await store.drainPendingShareIfNeeded()
                        await store.drainPendingResults()
                        await store.refresh()
                    }
                }
        }
        .defaultSize(width: 1100, height: 720)
        .commands { PuzzleHouseCommands(store: store, coordinator: coordinator) }

        // Native ⌘, Settings window. Reuses the shared SettingsView so prefs
        // (spoilers, notifications, profile, diagnostics) stay in sync with iOS.
        Settings {
            SettingsView(store: store)
                .frame(minWidth: 460, minHeight: 420)
        }

        // Menu-bar quick entry: paste/submit a result and peek at today's
        // leaderboard without opening the main window.
        MenuBarExtra("Puzzle House", systemImage: "puzzlepiece.fill") {
            MenuBarQuickEntry(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Thin wrapper so the menu-bar quick-entry can open/focus the main window via
/// the SwiftUI `openWindow` action (only available inside a `View`).
private struct MenuBarQuickEntry: View {
    let store: HouseholdStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        QuickEntryView(store: store) {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}

/// macOS lifecycle delegate. Replaces both the iOS `AppDelegate` and
/// `ShareSceneDelegate`: on macOS there is no scene delegate, so CloudKit share
/// acceptance (`userDidAcceptCloudKitShareWith`) and silent pushes
/// (`didReceiveRemoteNotification`, the no-completion-handler variant) are
/// delivered here for both cold and warm launches.
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Enable silent CloudKit pushes. The auth prompt for *visible*
        // notifications is gated separately by NotificationService; this only
        // enables APNs delivery of content-available pushes.
        NSApplication.shared.registerForRemoteNotifications()
    }

    /// macOS delivers CloudKit share acceptance here for BOTH cold and warm
    /// launches (no scene-delegate split like iOS). Funnels into the same shared
    /// `acceptOrStashIncomingShare` helper the iOS scene delegate uses.
    func application(
        _ application: NSApplication,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        Task { @MainActor in acceptOrStashIncomingShare(metadata) }
    }

    /// Silent push — the macOS signature has no `fetchCompletionHandler`. Body
    /// mirrors the iOS handler: confirm it's a CloudKit notification, then ask
    /// the store to refresh.
    func application(
        _ application: NSApplication,
        didReceiveRemoteNotification userInfo: [String: Any]
    ) {
        let payload = userInfo as? [String: NSObject] ?? [:]
        guard let cloudNotification = CKNotification(fromRemoteNotificationDictionary: payload),
              cloudNotification is CKQueryNotification || cloudNotification is CKDatabaseNotification
        else { return }
        Task { @MainActor in
            await PuzzleHouseSharedStore.current?.handleRemoteCloudKitNotification()
        }
    }

    func application(
        _ application: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // CloudKit manages tokens for us — registration just enables delivery.
    }

    func application(
        _ application: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Non-fatal: silent pushes won't fire (common when unsigned / no APNs),
        // but the app still works via manual refresh.
    }
}

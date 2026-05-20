import SwiftUI
import PuzzleCloudKit
import PuzzleHouseApp

@main
struct PuzzleHouseAppEntry: App {
    @State private var store: HouseholdStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let appGroup = AppGroupContainer(appGroupIdentifier: PuzzleHouseIdentifiers.appGroup)
        let queue = appGroup.map { OfflineWriteQueue(container: $0) }
        let service = CloudKitService(writeQueue: queue)
        _store = State(wrappedValue: HouseholdStore(service: service, queue: queue))
    }

    var body: some Scene {
        WindowGroup {
            PuzzleHouseRootView(store: store)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await store.drainPendingResults() }
                }
        }
    }
}

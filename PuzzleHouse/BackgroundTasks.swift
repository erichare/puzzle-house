#if canImport(UIKit)
import UIKit
import BackgroundTasks
import PuzzleHouseApp

/// Background drain of the Share Extension's offline write queue, so results
/// shared while the app was closed flush without the user reopening it. The
/// drain logic itself lives in `HouseholdStore.drainPendingResults()`; this is
/// only the `BGTaskScheduler` plumbing around it.
enum BackgroundDrain {
    /// Must match `BGTaskSchedulerPermittedIdentifiers` in project.yml.
    static let taskIdentifier = "com.jestats.PuzzleHouse.drain"

    /// Register the handler. Must be called during `didFinishLaunching`, before
    /// it returns.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refresh)
        }
    }

    /// Schedule a future drain — but only when something is actually queued, so
    /// we don't ask iOS to wake us for nothing.
    static func schedule() {
        Task { @MainActor in
            guard (PuzzleHouseSharedStore.current?.pendingQueueCount() ?? 0) > 0 else { return }
            let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
            request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
            try? BGTaskScheduler.shared.submit(request)
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        // Reschedule so the queue keeps draining on future opportunities.
        schedule()
        let work = Task { @MainActor in
            let store = PuzzleHouseSharedStore.current
            // Cold background launch: the store may not be bootstrapped yet, so
            // `drainPendingResults` would have no household/user to submit under.
            if store?.currentUserID == nil {
                await store?.bootstrap()
            }
            await store?.drainPendingResults()
            task.setTaskCompleted(success: store?.lastDrainError == nil)
        }
        task.expirationHandler = { work.cancel() }
    }
}
#endif

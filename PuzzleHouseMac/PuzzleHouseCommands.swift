import SwiftUI
import PuzzleHouseApp

/// Native macOS menu-bar commands with ⌘-keyboard shortcuts. View-presenting
/// actions (Add Result, New House, switch pane) flow through `MacUICoordinator`
/// so the menu and `RootMacView` share one source of truth; store actions
/// (refresh, switch house) call the store directly.
struct PuzzleHouseCommands: Commands {
    let store: HouseholdStore
    @Bindable var coordinator: MacUICoordinator

    var body: some Commands {
        // File ▸ (after the standard "New" group)
        CommandGroup(after: .newItem) {
            Button("Add Result\u{2026}") { coordinator.showAddResult = true }
                .keyboardShortcut("n", modifiers: .command)
            Button("New House\u{2026}") { coordinator.showCreateHouse = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        // A dedicated "House" menu for navigation + sync.
        CommandMenu("House") {
            Button("Today") { coordinator.detailTab = .today }
                .keyboardShortcut("1", modifiers: .command)
            Button("This Week") { coordinator.detailTab = .stats }
                .keyboardShortcut("2", modifiers: .command)
            Button("History") { coordinator.detailTab = .history }
                .keyboardShortcut("3", modifiers: .command)

            Divider()

            Button("Refresh from iCloud") { Task { await store.refresh() } }
                .keyboardShortcut("r", modifiers: .command)

            Divider()

            Button("Next House") { switchHouse(by: 1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(store.households.count < 2)
            Button("Previous House") { switchHouse(by: -1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(store.households.count < 2)
        }
    }

    /// Cycle the selected household by `delta`, wrapping around.
    private func switchHouse(by delta: Int) {
        let houses = store.households
        guard houses.count > 1 else { return }
        let current = houses.firstIndex { $0.id == store.selectedHouseholdID } ?? 0
        let next = (current + delta + houses.count) % houses.count
        let id = houses[next].id
        Task { await store.switchHousehold(id) }
    }
}

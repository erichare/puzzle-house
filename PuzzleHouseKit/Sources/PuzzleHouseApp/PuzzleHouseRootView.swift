import SwiftUI
import PuzzleCore

public struct PuzzleHouseRootView: View {
    @Bindable var store: HouseholdStore

    public init(store: HouseholdStore) {
        self.store = store
    }

    public var body: some View {
        Group {
            switch store.state {
            case .idle, .loading:
                ProgressView("Loading your houses\u{2026}")
            case .error(let message):
                ContentUnavailableView(
                    "Couldn't load",
                    systemImage: "exclamationmark.icloud",
                    description: Text(message)
                )
            case .ready:
                content
            }
        }
        .task { if store.state == .idle { await store.bootstrap() } }
    }

    private var content: some View {
        TabView {
            TodayView(store: store)
                .tabItem { Label("Today", systemImage: "calendar.circle") }

            HistoryView(store: store)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            HouseSwitcherView(store: store)
                .tabItem { Label("Houses", systemImage: "house") }

            SettingsView(store: store)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

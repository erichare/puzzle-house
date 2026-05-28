import SwiftUI
import PuzzleCore

public struct PuzzleHouseRootView: View {
    @Bindable var store: HouseholdStore
    @State private var didPromptProfile = false

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
        .task {
            if store.state == .idle { await store.bootstrap() }
            // Cold-launch invite: the scene stashed the metadata before we were
            // ready; now that we're bootstrapped, accept it.
            await store.drainPendingShareIfNeeded()
        }
        .overlay {
            if store.isJoining { JoiningOverlay() }
        }
        .animation(.snappy, value: store.isJoining)
        // One-time prompt to pick a name + avatar so we don't show "Me" /
        // "New member" to the rest of the house.
        .sheet(isPresented: Binding(
            get: { store.needsProfileSetup && !didPromptProfile },
            set: { presenting in if !presenting { didPromptProfile = true } }
        )) {
            EditMyMembershipSheet(store: store)
        }
    }

    private var content: some View {
        TabView {
            TodayView(store: store)
                .tabItem { Label("Today", systemImage: "calendar.circle") }

            StatsView(store: store)
                .tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }

            HistoryView(store: store)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            HouseSwitcherView(store: store)
                .tabItem { Label("Houses", systemImage: "house") }

            SettingsView(store: store)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

/// Shown while we're accepting an invite and waiting for the shared house to
/// replicate, so tapping a link gives immediate feedback instead of a blank
/// beat before the house appears.
private struct JoiningOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text("Joining house\u{2026}").font(.headline)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
        .transition(.opacity)
    }
}

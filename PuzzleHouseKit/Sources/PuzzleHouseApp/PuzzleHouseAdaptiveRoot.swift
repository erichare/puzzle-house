import SwiftUI

/// The top app section, shared by the iPhone tab bar and the iPad sidebar.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case today, stats, history, houses, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .stats: return "Stats"
        case .history: return "History"
        case .houses: return "Houses"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "calendar.circle"
        case .stats: return "chart.bar.xaxis"
        case .history: return "clock.arrow.circlepath"
        case .houses: return "house"
        case .settings: return "gearshape"
        }
    }
}

/// Adaptive shell: a bottom tab bar on a compact iPhone, a `NavigationSplitView`
/// sidebar on a regular-width iPad. The same feature views back both — the only
/// difference is the surrounding chrome (handled here + in `paneNavigation`).
struct PuzzleHouseAdaptiveRoot: View {
    @Bindable var store: HouseholdStore

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @State private var section: AppSection? = .today

    var body: some View {
        #if os(iOS)
        if sizeClass == .regular {
            splitView
        } else {
            tabs
        }
        #else
        tabs
        #endif
    }

    private var tabs: some View {
        TabView {
            ForEach(AppSection.allCases) { section in
                view(for: section)
                    .tabItem { Label(section.title, systemImage: section.symbol) }
            }
        }
    }

    private var splitView: some View {
        NavigationSplitView {
            List(selection: $section) {
                ForEach(AppSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol).tag(section)
                }
            }
            .navigationTitle(store.selectedHousehold.map { "\($0.iconEmoji) \($0.name)" } ?? "Puzzle House")
        } detail: {
            NavigationStack {
                view(for: section ?? .today)
                    .navigationTitle((section ?? .today).title)
            }
        }
    }

    @ViewBuilder
    private func view(for section: AppSection) -> some View {
        switch section {
        case .today: TodayView(store: store)
        case .stats: StatsView(store: store)
        case .history: HistoryView(store: store)
        case .houses: HouseSwitcherView(store: store)
        case .settings: SettingsView(store: store)
        }
    }
}

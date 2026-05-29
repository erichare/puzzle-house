#if os(macOS)
import SwiftUI
import PuzzleCore
import PuzzleParsers
import PuzzleUI

/// Detail panes available in the Mac window's segmented switcher.
public enum MacDetailTab: String, CaseIterable, Identifiable, Sendable {
    case today, stats, history
    public var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "Today"
        case .stats: return "This Week"
        case .history: return "History"
        }
    }
    var systemImage: String {
        switch self {
        case .today: return "calendar.circle"
        case .stats: return "chart.bar.xaxis"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

/// Shared UI intent between the macOS `App` scenes (Commands menu, menu-bar
/// quick entry) and `RootMacView`. The menu/commands set these flags; the root
/// view observes them to switch panes or present sheets. Keeps the window's
/// presentation state in one observable place instead of threading bindings
/// through the scene tree.
@MainActor
@Observable
public final class MacUICoordinator {
    public var detailTab: MacDetailTab = .today
    public var showAddResult = false
    public var showCreateHouse = false

    public init() {}
}

/// Native macOS root view. A `NavigationSplitView` with households in the
/// sidebar and Today / This Week / History in the detail pane. Reuses the
/// existing cross-platform feature views (`TodayView`, `StatsView`,
/// `HistoryView`) and sheets verbatim, so the Mac stays functionally in sync
/// with iOS — only the *navigation shell* differs from `PuzzleHouseRootView`.
public struct RootMacView: View {
    @Bindable var store: HouseholdStore
    @Bindable var coordinator: MacUICoordinator
    @State private var didPromptProfile = false

    // Sheet / dialog state — mirrors HouseSwitcherView's actions.
    @State private var editing: Household?
    @State private var inviting: Household?
    @State private var managingMembers: Household?
    @State private var deleting: Household?
    @State private var errorMessage: String?

    public init(store: HouseholdStore, coordinator: MacUICoordinator) {
        self.store = store
        self.coordinator = coordinator
    }

    public var body: some View {
        Group {
            switch store.state {
            case .idle, .loading:
                ProgressView("Loading your houses\u{2026}")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let message):
                ContentUnavailableView(
                    "Couldn't load",
                    systemImage: "exclamationmark.icloud",
                    description: Text(message)
                )
            case .ready:
                splitView
            }
        }
        .task {
            if store.state == .idle { await store.bootstrap() }
            // Cold-launch invite stashed by the app delegate before the store
            // was ready — accept it now that we're bootstrapped.
            await store.drainPendingShareIfNeeded()
            #if DEBUG
            // Debug-only UI hook: `open --args -PHOpenAddResult` jumps straight
            // to the Add Result sheet (handy for screenshots / manual checks).
            if ProcessInfo.processInfo.arguments.contains("-PHOpenAddResult") {
                coordinator.showAddResult = true
            }
            #endif
        }
        .overlay { if store.isJoining { joiningOverlay } }
        .animation(.snappy, value: store.isJoining)
        // One-time prompt for a real name + avatar (same as iOS).
        .sheet(isPresented: Binding(
            get: { store.needsProfileSetup && !didPromptProfile },
            set: { presenting in if !presenting { didPromptProfile = true } }
        )) {
            EditMyMembershipSheet(store: store)
        }
        // macOS defaults read small for this content-dense layout; bump the
        // base size a notch so the shared text styles scale up across the app.
        .dynamicTypeSize(.xLarge)
    }

    // MARK: Split view

    private var splitView: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .sheet(isPresented: $coordinator.showCreateHouse) { CreateHouseholdView(store: store) }
        .sheet(item: $editing) { HouseEditSheet(store: store, household: $0) }
        .sheet(item: $inviting) { InviteSheet(store: store, household: $0) }
        .sheet(item: $managingMembers) { ManageMembersSheet(store: store, household: $0) }
        .sheet(isPresented: $coordinator.showAddResult) {
            MacAddResultSheet { parsed, raw in
                try await store.submit(parsed: parsed, rawPayload: raw)
            }
        }
        .confirmationDialog(
            deleting.map { "Leave \($0.name)?" } ?? "",
            isPresented: deleteConfirmationBinding,
            presenting: deleting
        ) { household in
            Button(deleteButtonTitle(household), role: .destructive) {
                Task { await delete(household) }
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { household in
            let isOwner = household.createdByUserID == store.currentUserID
            Text(isOwner
                 ? "This permanently deletes \(household.name) and every result inside it for all members."
                 : "You'll stop seeing results for \(household.name). The owner keeps the house and its history.")
        }
        .alert(item: errorBinding) { msg in
            Alert(title: Text("Something went wrong"), message: Text(msg.text))
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: sidebarSelection) {
            Section("Your houses") {
                ForEach(store.households) { household in
                    sidebarRow(household).tag(household.id)
                }
            }
        }
        .navigationTitle("Puzzle House")
        .navigationSplitViewColumnWidth(min: 220, ideal: 264, max: 340)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if store.selectedHousehold != nil, store.houseStreak > 0 {
                    StreakBadge(count: store.houseStreak, label: "house streak")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                Button {
                    coordinator.showCreateHouse = true
                } label: {
                    Label("Create a house", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderless)
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func sidebarRow(_ household: Household) -> some View {
        let isSelected = household.id == store.selectedHouseholdID
        let isOwner = household.createdByUserID == store.currentUserID
        HStack(spacing: 10) {
            Text(household.iconEmoji).font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(household.name).lineLimit(1)
                Text(isOwner ? "Owner" : "Member")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if isSelected && store.isLoadingHousehold {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.vertical, 2)
        .contextMenu { rowContextMenu(household, isOwner: isOwner) }
    }

    @ViewBuilder
    private func rowContextMenu(_ household: Household, isOwner: Bool) -> some View {
        Button("Switch to this house") {
            Task { await store.switchHousehold(household.id) }
        }
        Divider()
        Button("Edit House\u{2026}") { editing = household }
        if isOwner {
            Button("Invite\u{2026}") { inviting = household }
        } else {
            Button("Members\u{2026}") { managingMembers = household }
        }
        Divider()
        Button(isOwner ? "Delete House\u{2026}" : "Leave House\u{2026}", role: .destructive) {
            deleting = household
        }
    }

    // MARK: Detail

    private var detail: some View {
        detailContent
            .navigationTitle(store.selectedHousehold?.name ?? "Puzzle House")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $coordinator.detailTab) {
                        ForEach(MacDetailTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(minWidth: 280)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        coordinator.showAddResult = true
                    } label: {
                        Label("Add Result", systemImage: "plus")
                    }
                    .help("Add a puzzle result")

                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Refresh from iCloud")

                    if isSelectedHouseOwner {
                        Button {
                            inviting = store.selectedHousehold
                        } label: {
                            Label("Invite", systemImage: "person.badge.plus")
                        }
                        .help("Invite people to this house")
                    }

                    Menu {
                        if let selected = store.selectedHousehold {
                            if isSelectedHouseOwner {
                                Button("Invite\u{2026}") { inviting = selected }
                            }
                            Button("Manage Members\u{2026}") { managingMembers = selected }
                            Button("Edit House\u{2026}") { editing = selected }
                            Divider()
                            Button(isSelectedHouseOwner ? "Delete House\u{2026}" : "Leave House\u{2026}",
                                   role: .destructive) {
                                deleting = selected
                            }
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .disabled(store.selectedHousehold == nil)
                }
            }
    }

    @ViewBuilder
    private var detailContent: some View {
        if store.selectedHousehold == nil {
            ContentUnavailableView(
                "No house selected",
                systemImage: "house",
                description: Text("Pick a house from the sidebar, or create one.")
            )
        } else {
            switch coordinator.detailTab {
            case .today: TodayView(store: store)
            case .stats: StatsView(store: store)
            case .history: HistoryView(store: store)
            }
        }
    }

    // MARK: Joining overlay

    private var joiningOverlay: some View {
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

    // MARK: Helpers

    private var isSelectedHouseOwner: Bool {
        guard let selected = store.selectedHousehold else { return false }
        return selected.createdByUserID == store.currentUserID
    }

    private var sidebarSelection: Binding<String?> {
        Binding(
            get: { store.selectedHouseholdID },
            set: { newID in
                if let newID, newID != store.selectedHouseholdID {
                    Task { await store.switchHousehold(newID) }
                }
            }
        )
    }

    private func deleteButtonTitle(_ household: Household) -> String {
        household.createdByUserID == store.currentUserID ? "Delete" : "Leave"
    }

    private func delete(_ household: Household) async {
        do {
            try await store.deleteHousehold(household)
            deleting = nil
        } catch {
            errorMessage = String(describing: error)
            deleting = nil
        }
    }

    private struct ErrorMessage: Identifiable {
        let id = UUID()
        let text: String
    }

    private var errorBinding: Binding<ErrorMessage?> {
        Binding(
            get: { errorMessage.map { ErrorMessage(text: $0) } },
            set: { errorMessage = $0?.text }
        )
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }
}
#endif

#if os(macOS)
import SwiftUI
import PuzzleUI

/// Native macOS Settings window: a `TabView` of grouped `Form`s, the idiomatic
/// Mac preferences layout. Maps every field from the iOS `SettingsView` (which
/// is a stacked iOS Form and looks wrong inside a macOS Settings scene) onto
/// proper tabs, reusing the shared store bindings and `EditMyMembershipSheet`.
public struct MacSettingsView: View {
    @Bindable var store: HouseholdStore

    @State private var editingProfile = false
    @State private var requestingPermission = false
    @State private var draining = false
    @State private var showClearedAlert = false
    @State private var droppedCount = 0

    public init(store: HouseholdStore) {
        self.store = store
    }

    public var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            profileTab
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
            notificationsTab
                .tabItem { Label("Notifications", systemImage: "bell") }
            houseTab
                .tabItem { Label("House", systemImage: "house") }
            advancedTab
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 500, height: 420)
    }

    // MARK: General

    private var generalTab: some View {
        Form {
            Section("Spoilers") {
                Toggle("Hide grids until you've played", isOn: $store.preferences.hideSpoilersUntilSolved)
            }
            Section("About") {
                LabeledContent("Version", value: Self.appVersion)
                LabeledContent("Build", value: Self.appBuild)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Profile

    private var profileTab: some View {
        Form {
            Section("You") {
                if let me = store.members.first(where: { $0.userID == store.currentUserID }) {
                    HStack(spacing: 12) {
                        Avatar(emoji: me.avatarEmoji, displayName: me.displayName, size: 56, photoData: me.avatarPhotoData)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(me.displayName).font(.headline)
                            Text("in \(store.selectedHousehold?.name ?? "this house")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    Button("Edit Profile\u{2026}") { editingProfile = true }
                } else {
                    Text("Join or create a house to set up your profile.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $editingProfile) {
            EditMyMembershipSheet(store: store)
        }
    }

    // MARK: Notifications

    @ViewBuilder
    private var notificationsTab: some View {
        Form {
            Section("Notifications") {
                switch store.notificationStatus {
                case .notDetermined:
                    Button {
                        Task {
                            requestingPermission = true
                            defer { requestingPermission = false }
                            await store.requestNotificationPermission()
                        }
                    } label: {
                        if requestingPermission {
                            HStack { ProgressView().controlSize(.small); Text("Asking\u{2026}") }
                        } else {
                            Label("Turn on notifications", systemImage: "bell")
                        }
                    }
                case .denied:
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notifications are turned off").font(.callout)
                        Text("Enable them in System Settings \u{203A} Notifications \u{203A} Puzzle House.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                default:
                    Toggle("Daily reminder if you haven't played", isOn: $store.preferences.notifyDailyReminder)
                        .onChange(of: store.preferences.notifyDailyReminder) { _, _ in
                            Task { await store.rescheduleNotifications() }
                        }
                    Toggle("Today's household champion", isOn: $store.preferences.notifyHouseholdChampion)
                    Toggle("Weekly recap", isOn: $store.preferences.notifyWeeklyRecap)
                        .onChange(of: store.preferences.notifyWeeklyRecap) { _, _ in
                            Task { await store.rescheduleNotifications() }
                        }
                    Toggle("\u{201C}Mom solved before you\u{201D}", isOn: $store.preferences.notifySolvedBeforeYou)
                }
            }
            Section {
                Text("Household champion and \u{201C}before you\u{201D} alerts come via iCloud and may take a moment to arrive.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: House

    private var houseTab: some View {
        Form {
            Section("Current house") {
                if let house = store.selectedHousehold {
                    LabeledContent("Name") {
                        HStack(spacing: 6) { Text(house.iconEmoji); Text(house.name) }
                    }
                    LabeledContent("Time zone", value: house.timeZoneIdentifier)
                    LabeledContent("Members", value: "\(store.members.count)")
                } else {
                    Text("No active house").foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Advanced

    private var advancedTab: some View {
        Form {
            Section("Diagnostics") {
                LabeledContent("Pending submissions", value: "\(store.pendingQueueCount())")
                Button {
                    Task {
                        draining = true
                        await store.drainPendingResults()
                        draining = false
                    }
                } label: {
                    if draining {
                        HStack { ProgressView().controlSize(.small); Text("Draining\u{2026}") }
                    } else {
                        Label("Drain now", systemImage: "arrow.down.circle")
                    }
                }
                .disabled(draining)

                if store.lastDrainCount > 0 {
                    Text("Last drain: synced \(store.lastDrainCount).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = store.lastDrainError {
                    Text("Last error: \(error)")
                        .font(.caption).foregroundStyle(.red)
                }

                Button(role: .destructive) {
                    droppedCount = store.clearLocalData()
                    showClearedAlert = true
                } label: {
                    Label("Clear pending submissions", systemImage: "trash")
                }
            }
            Section {
                Text("Pending submissions are queued by the Share extension when it can't reach iCloud directly. The app drains them on launch and when it returns to the foreground.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert("Local data cleared", isPresented: $showClearedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Removed \(droppedCount) pending submission\(droppedCount == 1 ? "" : "s") from this device. Records already in iCloud are unchanged.")
        }
    }

    // MARK: Version helpers

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }
    private static var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
#endif

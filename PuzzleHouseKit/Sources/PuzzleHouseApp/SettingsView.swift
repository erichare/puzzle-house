import SwiftUI
import PuzzleCore

public struct SettingsView: View {
    @Bindable var store: HouseholdStore
    @State private var requestingPermission = false

    public init(store: HouseholdStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Form {
                spoilerSection
                notificationsSection
                houseSection
                diagnosticsSection
                aboutSection
            }
            .navigationTitle("Settings")
            .alert("Local data cleared", isPresented: $showClearedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Removed \(droppedCount) pending submission\(droppedCount == 1 ? "" : "s") from this device. Records already in iCloud are unchanged.")
            }
        }
    }

    @State private var showClearedAlert = false
    @State private var droppedCount = 0

    private var spoilerSection: some View {
        Section("Spoilers") {
            Toggle("Hide grids until you've played", isOn: $store.preferences.hideSpoilersUntilSolved)
        }
    }

    private var notificationsSection: some View {
        Section {
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
                        HStack { ProgressView(); Text("Asking…") }
                    } else {
                        Label("Turn on notifications", systemImage: "bell")
                    }
                }
            case .denied:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notifications are turned off")
                        .font(.callout)
                    Text("Enable in Settings → Notifications → Puzzle House.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .authorized, .provisional, .ephemeral:
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
                Text("Household champion and \u{201C}before you\u{201D} alerts come via iCloud and may take a moment to arrive.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Notifications")
        }
    }

    private var houseSection: some View {
        Section {
            if let h = store.selectedHousehold {
                LabeledContent("Name", value: h.name)
                LabeledContent("Time zone", value: h.timeZoneIdentifier)
                LabeledContent("Members", value: "\(store.members.count)")
            } else {
                Text("No active house").foregroundStyle(.secondary)
            }
        } header: {
            Text("Current house")
        }
    }

    private var diagnosticsSection: some View {
        Section {
            Button(role: .destructive) {
                droppedCount = store.clearLocalData()
                showClearedAlert = true
            } label: {
                Label("Clear pending submissions", systemImage: "trash")
            }
            Text("Wipes the offline queue used by the Share Extension. Use if the app crashes on launch or you see stuck submissions.")
                .font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("Diagnostics")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Bundle.main.shortVersion)
            LabeledContent("Build", value: Bundle.main.buildNumber)
        }
    }
}

private extension Bundle {
    var shortVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0" }
    var buildNumber: String { infoDictionary?["CFBundleVersion"] as? String ?? "1" }
}

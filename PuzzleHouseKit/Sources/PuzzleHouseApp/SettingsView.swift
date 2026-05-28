import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif
import PuzzleCore
import PuzzleUI
import PuzzleVision

public struct SettingsView: View {
    @Bindable var store: HouseholdStore
    @State private var requestingPermission = false

    public init(store: HouseholdStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Form {
                meSection
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

    @State private var editingMyName = false

    private var meSection: some View {
        Section {
            if let me = store.members.first(where: { $0.userID == store.currentUserID }) {
                Button {
                    editingMyName = true
                } label: {
                    HStack {
                        Avatar(emoji: me.avatarEmoji, displayName: me.displayName)
                        VStack(alignment: .leading) {
                            Text(me.displayName).foregroundStyle(.primary)
                            Text("in \(store.selectedHousehold?.name ?? "this house")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "pencil").foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("You")
        }
        .sheet(isPresented: $editingMyName) {
            EditMyMembershipSheet(store: store)
        }
    }

    @State private var draining = false

    private var diagnosticsSection: some View {
        Section {
            HStack {
                Label("Pending submissions", systemImage: "tray.full")
                Spacer()
                Text("\(store.pendingQueueCount())")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            Button {
                Task {
                    draining = true
                    await store.drainPendingResults()
                    draining = false
                }
            } label: {
                if draining {
                    HStack { ProgressView(); Text("Draining\u{2026}") }
                } else {
                    Label("Drain now", systemImage: "arrow.down.circle")
                }
            }
            .disabled(draining)
            if store.lastDrainCount > 0 || store.lastDrainError != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if store.lastDrainCount > 0 {
                        Text("Last drain: synced \(store.lastDrainCount).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let err = store.lastDrainError {
                        Text("Last error: \(err)")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
            }
            Button(role: .destructive) {
                droppedCount = store.clearLocalData()
                showClearedAlert = true
            } label: {
                Label("Clear pending submissions", systemImage: "trash")
            }
            Text("Pending submissions are queued by the Share Extension when it can't reach iCloud directly. The main app drains them on launch and when it returns to the foreground.")
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

struct EditMyMembershipSheet: View {
    let store: HouseholdStore
    @State private var name: String = ""
    @State private var emoji: String = "🧩"
    @State private var photoData: Data?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showingEmojiPicker = false
    @State private var loadingPhoto = false
    @State private var saving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        Avatar(emoji: emoji, displayName: name, size: 100, photoData: photoData)
                            .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 4)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                }
                Section("Your name in this house") {
                    TextField("Name", text: $name).disabled(saving)
                }
                Section {
                    PhotosPicker(
                        selection: $pickerItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        if loadingPhoto {
                            HStack { ProgressView(); Text("Loading photo…").foregroundStyle(.secondary) }
                        } else if photoData != nil {
                            Label("Change photo", systemImage: "photo")
                        } else {
                            Label("Use a photo from your library", systemImage: "photo.on.rectangle.angled")
                        }
                    }
                    .disabled(saving)
                    if photoData != nil {
                        Button(role: .destructive) {
                            photoData = nil
                        } label: {
                            Label("Remove photo", systemImage: "trash")
                        }
                        .disabled(saving)
                    }
                } header: {
                    Text("Photo")
                } footer: {
                    Text("Stored privately in your household — only members see it.")
                        .font(.caption)
                }
                Section {
                    Button {
                        showingEmojiPicker = true
                    } label: {
                        HStack {
                            Label("Choose emoji", systemImage: "face.smiling")
                            Spacer()
                            Text(emoji).font(.title)
                        }
                    }
                    .disabled(saving)
                } header: {
                    Text("Fallback emoji")
                } footer: {
                    Text("Shown when you haven't set a photo.")
                        .font(.caption)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .interactiveDismissDisabled(saving)
            .navigationTitle("Edit my profile")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showingEmojiPicker) {
                EmojiPicker(selection: $emoji, title: "Pick your avatar emoji")
            }
            .onChange(of: pickerItem) { _, new in
                guard let new else { return }
                Task { await loadPhoto(new) }
            }
            .onAppear {
                if let me = store.members.first(where: { $0.userID == store.currentUserID }) {
                    // Start blank for a first-run placeholder so the user types
                    // a fresh name instead of clearing "Me" / "New member".
                    name = me.hasPlaceholderName ? "" : me.displayName
                    emoji = me.avatarEmoji
                    photoData = me.avatarPhotoData
                }
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        loadingPhoto = true
        defer { loadingPhoto = false }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else { return }
            #if canImport(UIKit)
            if let downsampled = AvatarPhotoEncoder.encode(raw) {
                photoData = downsampled
            } else {
                error = "Couldn't process that image. Try a different one."
            }
            #endif
        } catch {
            self.error = String(describing: error)
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await store.updateMyMembership(
                displayName: name,
                avatarEmoji: emoji,
                avatarPhotoData: photoData
            )
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }
}

private extension Bundle {
    var shortVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0" }
    var buildNumber: String { infoDictionary?["CFBundleVersion"] as? String ?? "1" }
}

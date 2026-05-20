import SwiftUI
import PuzzleCore

public struct HouseSwitcherView: View {
    @Bindable var store: HouseholdStore
    @State private var showingCreate = false
    @State private var editing: Household?
    @State private var inviting: Household?
    @State private var deleting: Household?
    @State private var errorMessage: String?

    public init(store: HouseholdStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Your houses") {
                    ForEach(store.households) { household in
                        row(household)
                    }
                }
                Section {
                    Button {
                        showingCreate = true
                    } label: {
                        Label("Create a house", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle("Houses")
            .sheet(isPresented: $showingCreate) {
                CreateHouseholdView(store: store)
            }
            .sheet(item: $editing) { household in
                HouseEditSheet(store: store, household: household)
            }
            .sheet(item: $inviting) { household in
                InviteSheet(store: store, household: household)
            }
            .alert(item: errorBinding) { msg in
                Alert(title: Text("Something went wrong"), message: Text(msg.text))
            }
            .confirmationDialog(
                deleting.map { "Leave \($0.name)?" } ?? "",
                isPresented: deleteConfirmationBinding,
                presenting: deleting
            ) { household in
                Button("Delete", role: .destructive) {
                    Task { await delete(household) }
                }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: { household in
                let isOwner = household.createdByUserID == store.currentUserID
                Text(isOwner
                     ? "This permanently deletes \(household.name) and every result inside it for all members."
                     : "You'll stop seeing results for \(household.name). The owner keeps the house and its history.")
            }
        }
    }

    @ViewBuilder
    private func row(_ household: Household) -> some View {
        let isSelected = household.id == store.selectedHouseholdID
        let isOwner = household.createdByUserID == store.currentUserID
        Button {
            Task { await store.switchHousehold(household.id) }
        } label: {
            HStack {
                Text(household.iconEmoji).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(household.name)
                    Text(isOwner ? "Owner" : "Member")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleting = household
            } label: {
                Label(isOwner ? "Delete" : "Leave", systemImage: "trash")
            }
            Button {
                editing = household
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
            if isOwner {
                Button {
                    inviting = household
                } label: {
                    Label("Invite", systemImage: "person.badge.plus")
                }
                .tint(.green)
            }
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

    private func delete(_ household: Household) async {
        do {
            try await store.deleteHousehold(household)
            deleting = nil
        } catch {
            errorMessage = String(describing: error)
            deleting = nil
        }
    }
}

struct CreateHouseholdView: View {
    let store: HouseholdStore
    @State private var name = ""
    @State private var icon = "🏠"
    @State private var error: String?
    @State private var isCreating = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("House details") {
                    TextField("Name", text: $name)
                        .disabled(isCreating)
                    TextField("Emoji", text: $icon)
                        .disabled(isCreating)
                }
                if isCreating {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Setting up your house in iCloud\u{2026}")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .interactiveDismissDisabled(isCreating)
            .navigationTitle("New House")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await create() }
                    }
                    .disabled(isCreating || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        do {
            try await store.createHousehold(name: name, iconEmoji: icon)
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }
}

struct HouseEditSheet: View {
    let store: HouseholdStore
    let household: Household
    @State private var name: String
    @State private var icon: String
    @State private var saving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(store: HouseholdStore, household: Household) {
        self.store = store
        self.household = household
        _name = State(initialValue: household.name)
        _icon = State(initialValue: household.iconEmoji)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("House details") {
                    TextField("Name", text: $name).disabled(saving)
                    TextField("Emoji", text: $icon).disabled(saving)
                }
                if saving {
                    Section {
                        HStack { ProgressView(); Text("Saving\u{2026}").foregroundStyle(.secondary) }
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .interactiveDismissDisabled(saving)
            .navigationTitle("Edit House")
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
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await store.renameHousehold(household, name: name, iconEmoji: icon)
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }
}

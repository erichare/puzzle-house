import SwiftUI
import PuzzleCore
import PuzzleUI

/// Roster management for a household. Everyone can see who's in the house; the
/// owner can remove members, and members can leave. Sending new invites lives
/// in `InviteSheet`'s system share sheet.
public struct ManageMembersSheet: View {
    let store: HouseholdStore
    let household: Household
    @State private var pendingRemoval: Membership?
    @State private var working = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    public init(store: HouseholdStore, household: Household) {
        self.store = store
        self.household = household
    }

    private var isOwner: Bool { store.isOwner(of: household) }

    /// Owner first, then alphabetical — stable ordering for the roster.
    private var members: [Membership] {
        store.members.sorted { lhs, rhs in
            if (lhs.role == .owner) != (rhs.role == .owner) { return lhs.role == .owner }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(members) { member in
                        row(member)
                    }
                } header: {
                    Text("\(members.count) \(members.count == 1 ? "member" : "members")")
                } footer: {
                    if isOwner {
                        Text("Anyone with the invite link can join. Removing someone takes them off the roster; to fully cut off access, send a fresh invite link.")
                    }
                }

                if !isOwner {
                    Section {
                        Button(role: .destructive) {
                            Task { await leave() }
                        } label: {
                            Label("Leave this house", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .disabled(working)
                    } footer: {
                        Text("You'll stop seeing results for \(household.name). The owner keeps the house and its history.")
                    }
                }
            }
            .navigationTitle("Members")
            // Pull the latest roster when the sheet opens — a member who just
            // joined won't be in our cached list yet.
            .task { await store.refresh() }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                pendingRemoval.map { "Remove \($0.displayName)?" } ?? "",
                isPresented: removalBinding,
                presenting: pendingRemoval
            ) { member in
                Button("Remove", role: .destructive) {
                    Task { await remove(member) }
                }
                Button("Cancel", role: .cancel) { pendingRemoval = nil }
            } message: { member in
                Text("\(member.displayName) will be removed from \(household.name).")
            }
            .alert("Couldn't update members", isPresented: errorBinding) {
                Button("OK", role: .cancel) { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    @ViewBuilder
    private func row(_ member: Membership) -> some View {
        let isMe = member.userID == store.currentUserID
        HStack {
            Avatar(
                emoji: member.avatarEmoji,
                displayName: member.displayName,
                photoData: member.avatarPhotoData
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName + (isMe ? " (you)" : ""))
                Text(member.role == .owner ? "Owner" : "Member")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .swipeActions(edge: .trailing) {
            // The owner can remove other members. The owner can't remove
            // themselves here — they delete the house from the Houses tab.
            if isOwner, !isMe, member.role != .owner {
                Button(role: .destructive) {
                    pendingRemoval = member
                } label: {
                    Label("Remove", systemImage: "person.badge.minus")
                }
            }
        }
    }

    private func remove(_ member: Membership) async {
        working = true
        defer { working = false }
        do {
            try await store.removeMember(member)
            pendingRemoval = nil
        } catch {
            self.error = String(describing: error)
            pendingRemoval = nil
        }
    }

    private func leave() async {
        working = true
        defer { working = false }
        do {
            try await store.leaveHousehold(household)
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }

    private var removalBinding: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }
}

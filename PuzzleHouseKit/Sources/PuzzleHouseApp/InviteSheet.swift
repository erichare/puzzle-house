import SwiftUI
import CloudKit
#if canImport(UIKit)
import UIKit
#endif
import PuzzleCore
import PuzzleUI
import PuzzleCloudKit

/// A household wrapped so SwiftUI's `ShareLink` can present Apple's native
/// CloudKit sharing UI for it. `CKShareTransferRepresentation` calls back into
/// `ShareManager` to fetch-or-create the underlying `CKShare` on demand, so the
/// share is only created/touched when the user actually taps Invite — and all
/// the share lifecycle logic stays in one place (`ShareManager`).
public struct HouseholdShareItem: Transferable {
    let household: Household

    public static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { item in
            // The exporting closure is synchronous; the async fetch-or-create
            // happens in `prepareShare`'s preparation handler, which is only
            // run when the user actually invokes sharing.
            .prepareShare(container: CKContainer.default()) {
                let (share, _) = try await ShareManager().shareForSharing(item.household)
                return share
            }
        }
    }
}

/// Invite UI for a household.
///
/// The single call to action is a `ShareLink` that hands a `CKShare` to the
/// system share sheet. That sheet handles *sending* the invite (Messages,
/// Mail, copy link) and Apple's own participant management. In-app roster
/// management — see who's in, remove someone, leave — is one tap away in
/// `ManageMembersSheet`.
public struct InviteSheet: View {
    let store: HouseholdStore
    let household: Household
    @State private var managingMembers = false
    @Environment(\.dismiss) private var dismiss

    public init(store: HouseholdStore, household: Household) {
        self.store = store
        self.household = household
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    hero
                    intro
                    ShareLink(
                        item: HouseholdShareItem(household: household),
                        preview: SharePreview(household.name)
                    ) {
                        Label("Invite people", systemImage: "person.badge.plus")
                            .font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 24)

                    Button {
                        managingMembers = true
                    } label: {
                        Label("Manage members", systemImage: "person.2")
                            .font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .padding(.horizontal, 24)

                    Spacer(minLength: 20)
                }
                .padding(.top)
            }
            .navigationTitle("Invite")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $managingMembers) {
                ManageMembersSheet(store: store, household: household)
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.91, blue: 0.83),
                        Color(red: 1.00, green: 0.69, blue: 0.53),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .frame(width: 110, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 26))
                Text(household.iconEmoji).font(.system(size: 64))
            }
            .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 6)
            Text(household.name).font(.title2).bold()
        }
    }

    private var intro: some View {
        Text("Send this invite to anyone you want in the house. They tap the link and they're in — their results show up here automatically.")
            .font(.callout).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
    }
}

import SwiftUI
import PuzzleCore

/// Generates a CloudKit share URL for the household and lets the user send it
/// via the standard share sheet (Messages, Mail, AirDrop, etc.). The
/// recipient taps the URL on their device → iCloud accepts the share and the
/// household zone appears in their shared DB.
public struct InviteSheet: View {
    let store: HouseholdStore
    let household: Household
    @State private var url: URL?
    @State private var error: String?
    @State private var isGenerating = true
    @Environment(\.dismiss) private var dismiss

    public init(store: HouseholdStore, household: Household) {
        self.store = store
        self.household = household
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Text(household.iconEmoji).font(.system(size: 64))
                Text("Invite to \(household.name)")
                    .font(.title2).bold()
                    .multilineTextAlignment(.center)
                if isGenerating {
                    ProgressView("Generating invite link\u{2026}")
                } else if let url {
                    Text("Send this link to anyone you want in this house. They tap it on their iPhone or Mac to join.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    ShareLink(item: url) {
                        Label("Send invite", systemImage: "paperplane.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 24)
                    Text(url.absoluteString)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .contextMenu {
                            Button {
                                #if canImport(UIKit)
                                UIPasteboard.general.string = url.absoluteString
                                #endif
                            } label: {
                                Label("Copy link", systemImage: "doc.on.doc")
                            }
                        }
                } else if let error {
                    Text(error)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Invite")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadURL() }
        }
    }

    private func loadURL() async {
        defer { isGenerating = false }
        do {
            url = try await store.inviteURL(for: household)
        } catch {
            self.error = String(describing: error)
        }
    }
}

#if canImport(UIKit)
import UIKit
#endif

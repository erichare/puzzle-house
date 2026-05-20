import SwiftUI
import PuzzleCore
import PuzzleUI
import PuzzleCloudKit
#if canImport(UIKit)
import UIKit
#endif

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
    @State private var copied = false
    @Environment(\.dismiss) private var dismiss

    public init(store: HouseholdStore, household: Household) {
        self.store = store
        self.household = household
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    hero
                    if isGenerating {
                        ProgressView("Generating invite link\u{2026}")
                            .padding(.top, 16)
                    } else if let url {
                        memberStrip
                        invitationCopy
                        actionButtons(for: url)
                        linkPreview(url)
                    } else if let error {
                        Text(error)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("Invite to House")
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

    private var hero: some View {
        VStack(spacing: 12) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.91, blue: 0.83),
                        Color(red: 1.00, green: 0.69, blue: 0.53),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 28))
                Text(household.iconEmoji).font(.system(size: 70))
            }
            .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 6)
            Text(household.name).font(.title2).bold().multilineTextAlignment(.center)
        }
    }

    private var memberStrip: some View {
        VStack(spacing: 8) {
            HStack(spacing: -6) {
                ForEach(store.members.prefix(5), id: \.id) { m in
                    Avatar(emoji: m.avatarEmoji, displayName: m.displayName, size: 36, photoData: m.avatarPhotoData)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                }
                if store.members.count > 5 {
                    Text("+\(store.members.count - 5)")
                        .font(.caption.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(PuzzleTheme.secondaryFill))
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                }
            }
            Text(memberCountLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private var memberCountLabel: String {
        let count = store.members.count
        switch count {
        case 0: return "You'll be the first in this house."
        case 1: return "Just you for now."
        case 2: return "Already 2 people in this house."
        default: return "Already \(count) people in this house."
        }
    }

    private var invitationCopy: some View {
        Text("Send this link to whoever you want to join. They tap it on their iPhone, iPad, or Mac — it'll prompt them to accept and the house shows up in their Houses tab automatically.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func actionButtons(for url: URL) -> some View {
        VStack(spacing: 10) {
            ShareLink(
                item: url,
                subject: Text("Join \(household.name) on Puzzle House"),
                message: Text(inviteMessage),
                preview: SharePreview(
                    "Join \(household.name) on Puzzle House",
                    image: thumbnailImage
                )
            ) {
                Label("Send invite", systemImage: "paperplane.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            Button {
                #if canImport(UIKit)
                UIPasteboard.general.string = url.absoluteString
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                #endif
                withAnimation(.snappy) { copied = true }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { copied = false }
                }
            } label: {
                Label(copied ? "Copied!" : "Copy link",
                      systemImage: copied ? "checkmark.circle.fill" : "link")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private func linkPreview(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LINK")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(url.absoluteString)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }

    private func loadURL() async {
        defer { isGenerating = false }
        do {
            url = try await store.inviteURL(for: household)
        } catch {
            self.error = String(describing: error)
        }
    }

    private var inviteMessage: String {
        "Tap the link to join \(household.iconEmoji) \(household.name) on Puzzle House — we share daily Wordle, Connections, Strands, and Emoji Game scores."
    }

    /// A SwiftUI `Image` of the same gradient-emoji thumbnail we attach to
    /// the CKShare itself, so the iMessage / Mail / AirDrop preview shows
    /// the house glyph instead of the generic iCloud Sharing artwork.
    private var thumbnailImage: Image {
        #if canImport(UIKit)
        if let data = ShareManager.renderThumbnail(emoji: household.iconEmoji),
           let uiImage = UIImage(data: data) {
            return Image(uiImage: uiImage)
        }
        #endif
        return Image(systemName: "house.fill")
    }
}

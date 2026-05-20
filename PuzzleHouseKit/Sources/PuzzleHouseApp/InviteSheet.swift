import SwiftUI
import CloudKit
#if canImport(UIKit)
import UIKit
#endif
import PuzzleCore
import PuzzleUI
import PuzzleCloudKit

/// Invite UI for a household.
///
/// We use the proven `ShareLink(item: URL)` path — `ShareLink` doesn't
/// support `CKShare` directly, and `UICloudSharingController` has been
/// flaky. The trick is making sure the underlying CKShare is in the right
/// state on the server: `publicPermission == .readWrite` is what lets any
/// recipient accept by URL. The diagnostic block in this view shows the
/// loaded share's actual permission so we can finally see what iCloud has,
/// without needing CloudKit Dashboard access.
public struct InviteSheet: View {
    let store: HouseholdStore
    let household: Household
    @State private var share: CKShare?
    @State private var error: String?
    @State private var preparing = true
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
                    if preparing {
                        ProgressView("Preparing share\u{2026}").padding(.top, 20)
                    } else if let share {
                        diagnosticBlock(share)
                        intro
                        if let url = share.url {
                            sendBlock(url: url)
                            linkBlock(url: url)
                        }
                    } else if let error {
                        errorBlock(error)
                    }
                    Spacer(minLength: 30)
                }
                .padding()
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
            .task { await prepare() }
        }
    }

    // MARK: - Sections

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

    @ViewBuilder
    private func diagnosticBlock(_ share: CKShare) -> some View {
        let permissionOK = share.publicPermission == .readWrite
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: permissionOK ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(permissionOK ? .green : .orange)
                Text(permissionOK ? "Share is ready" : "Share isn't fully open")
                    .font(.subheadline.weight(.semibold))
            }
            HStack {
                Text("Permission:")
                Text(permissionLabel(share.publicPermission))
                    .foregroundStyle(permissionOK ? .green : .orange)
                    .fontWeight(.medium)
            }
            .font(.caption)
            HStack {
                Text("Participants:")
                Text("\(share.participants.count)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !permissionOK {
                Text("Recipients won't be able to accept this share until the permission is `readWrite`. Tap Reset below to try fixing it.")
                    .font(.caption2).foregroundStyle(.secondary)
                Button {
                    Task { await forceUpgrade() }
                } label: {
                    Label("Reset share permission", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var intro: some View {
        Text("Send this link to whoever you want in the house. Anyone who taps it can accept and join.")
            .font(.callout).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
    }

    private func sendBlock(url: URL) -> some View {
        VStack(spacing: 10) {
            ShareLink(item: url) {
                Label("Send invite", systemImage: "paperplane.fill")
                    .font(.headline).frame(maxWidth: .infinity)
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
                    .font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
    }

    private func linkBlock(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LINK").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            Text(url.absoluteString)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(3).truncationMode(.middle)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
    }

    private func errorBlock(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).font(.title)
            Text("Couldn't prepare share").font(.headline)
            Text(message).font(.caption).multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 24)
    }

    // MARK: - Share prep / repair

    private func prepare() async {
        preparing = true
        defer { preparing = false }
        do {
            self.share = try await fetchOrCreateShare(forceUpgrade: false)
        } catch {
            self.error = String(describing: error)
        }
    }

    private func forceUpgrade() async {
        preparing = true
        defer { preparing = false }
        do {
            self.share = try await fetchOrCreateShare(forceUpgrade: true)
            self.error = nil
        } catch {
            self.error = String(describing: error)
        }
    }

    private func fetchOrCreateShare(forceUpgrade: Bool) async throws -> CKShare {
        let container = CKContainer.default()
        let zoneID = CKRecordZone.ID(
            zoneName: household.id, ownerName: CKCurrentUserDefaultName
        )
        let recordID = CKRecord.ID(recordName: household.id, zoneID: zoneID)
        let db = container.privateCloudDatabase
        let root = try await db.record(for: recordID)

        if let shareReference = root.share,
           let existing = try await db.record(for: shareReference.recordID) as? CKShare {
            if forceUpgrade || existing.publicPermission != .readWrite {
                existing.publicPermission = .readWrite
                existing[CKShare.SystemFieldKey.title] = household.name as CKRecordValue
                if let thumb = ShareManager.renderThumbnail(emoji: household.iconEmoji) {
                    existing[CKShare.SystemFieldKey.thumbnailImageData] = thumb as CKRecordValue
                }
                let result = try await db.modifyRecords(
                    saving: [existing], deleting: [], savePolicy: .changedKeys
                )
                if case .failure(let saveError)? = result.saveResults[existing.recordID] {
                    throw saveError
                }
            }
            return existing
        }

        // No share yet — create + save with root.
        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = household.name as CKRecordValue
        share[CKShare.SystemFieldKey.shareType] = "house.puzzle.household" as CKRecordValue
        if let thumb = ShareManager.renderThumbnail(emoji: household.iconEmoji) {
            share[CKShare.SystemFieldKey.thumbnailImageData] = thumb as CKRecordValue
        }
        share.publicPermission = .readWrite

        let result = try await db.modifyRecords(
            saving: [root, share], deleting: [], savePolicy: .ifServerRecordUnchanged
        )
        if case .failure(let saveError)? = result.saveResults[share.recordID] {
            throw saveError
        }
        if case .failure(let saveError)? = result.saveResults[root.recordID] {
            throw saveError
        }
        return share
    }

    private func permissionLabel(_ permission: CKShare.ParticipantPermission) -> String {
        switch permission {
        case .none: return "none (private — invite-only)"
        case .readOnly: return "readOnly"
        case .readWrite: return "readWrite"
        case .unknown: return "unknown"
        @unknown default: return "?"
        }
    }
}

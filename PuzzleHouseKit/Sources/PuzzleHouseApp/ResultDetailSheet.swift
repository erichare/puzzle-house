import SwiftUI
import PuzzleCore
import PuzzleParsers
import PuzzleScoring
import PuzzleUI
#if canImport(UIKit)
import UIKit
#endif

public struct ResultDetailSheet: View {
    @Bindable var store: HouseholdStore
    let result: PuzzleResult
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var deleting = false
    @State private var deleteError: String?

    public init(store: HouseholdStore, result: PuzzleResult) {
        self.store = store
        self.result = result
    }

    private var canDelete: Bool {
        result.authorUserID == store.currentUserID
    }

    public var body: some View {
        let game = Game.known(by: result.gameID)
        let visibility = store.spoilerMap[result.id] ?? .full
        let streak = store.gameStreak(userID: result.authorUserID, gameID: result.gameID)

        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header(game: game)
                    if visibility == .hidden {
                        hiddenPlaceholder
                    } else {
                        gridBlock
                        scoreBlock(streak: streak)
                        reactionsBlock
                        rawPayloadBlock
                        if canDelete { deleteButton }
                    }
                }
                .padding()
            }
            .navigationTitle(game?.displayName ?? result.gameID)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete this result?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    Task { await delete() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes it from iCloud for everyone in the household. Can't be undone.")
            }
            .alert(
                "Couldn't delete",
                isPresented: Binding(
                    get: { deleteError != nil },
                    set: { if !$0 { deleteError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
        }
    }

    @ViewBuilder
    private var deleteButton: some View {
        Button(role: .destructive) {
            confirmingDelete = true
        } label: {
            if deleting {
                HStack { ProgressView(); Text("Deleting\u{2026}") }
                    .frame(maxWidth: .infinity)
            } else {
                Label("Delete this result", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .tint(.red)
        .disabled(deleting)
    }

    private func delete() async {
        deleting = true
        defer { deleting = false }
        do {
            try await store.deleteResult(result)
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            dismiss()
        } catch {
            deleteError = String(describing: error)
        }
    }

    @ViewBuilder
    private func header(game: Game?) -> some View {
        HStack(spacing: 16) {
            Avatar(
                emoji: store.avatarEmoji(for: result.authorUserID),
                displayName: store.displayName(for: result.authorUserID),
                size: 56,
                photoData: store.avatarPhotoData(for: result.authorUserID)
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(store.displayName(for: result.authorUserID))
                    .font(.title3).bold()
                Text("\(game?.emoji ?? "🧩")  \(game?.displayName ?? result.gameID) #\(result.puzzleNumber)")
                    .foregroundStyle(.secondary)
                Text(result.submittedAt, style: .time)
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var hiddenPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "eye.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Play this puzzle yourself to reveal the grid.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private var gridBlock: some View {
        if let grid = result.gridData, !grid.isEmpty {
            Text(grid)
                .font(.system(.title2, design: .monospaced))
                .lineSpacing(2)
                .padding(20)
                .frame(maxWidth: .infinity)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    @ViewBuilder
    private func scoreBlock(streak: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Score", value: scoreSummary)
            LabeledContent("Status", value: result.rawScore.solved ? "Solved" : "Not solved")
            if streak > 0 {
                LabeledContent("Streak", value: "🔥 \(streak)")
            }
            ForEach(result.gridData == nil ? [] : Array(metadataKeyValues), id: \.0) { pair in
                LabeledContent(pair.0.capitalized, value: pair.1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var reactionsBlock: some View {
        let summary = store.reactionSummary(for: result.id)
        let myEmoji = store.myReaction(for: result.id)
        let isOwn = result.authorUserID == store.currentUserID
        VStack(alignment: .leading, spacing: 12) {
            Text("Reactions")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if summary.isEmpty && isOwn {
                Text("Others' reactions will show up here.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            ReactionPicker(
                summary: summary,
                myEmoji: myEmoji,
                canReact: !isOwn,
                onReact: { emoji in Task { try? await store.react(to: result.id, emoji: emoji) } },
                onClear: { Task { try? await store.clearMyReaction(on: result.id) } }
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var rawPayloadBlock: some View {
        DisclosureGroup("Original share text") {
            VStack(alignment: .leading, spacing: 12) {
                Text(result.rawPayload)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                #if canImport(UIKit)
                Button {
                    UIPasteboard.general.string = result.rawPayload
                } label: {
                    Label("Copy to clipboard", systemImage: "doc.on.doc")
                }
                #endif
            }
            .padding(.top, 8)
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
    }

    private var scoreSummary: String {
        switch result.rawScore {
        case .guesses(let used, let outOf, let solved):
            return solved ? "\(used)/\(outOf)" : "X/\(outOf)"
        case .mistakes(let count, let max, let solved):
            return solved ? "\(count) of \(max) mistakes" : "Failed (\(count)/\(max))"
        case .hints(let count, _):
            return "\(count) hint\(count == 1 ? "" : "s")"
        case .custom(let value, let solved):
            return solved ? "Solved (\(Int(value)))" : "\(Int(value)) correct"
        }
    }

    private var metadataKeyValues: [(String, String)] {
        // Best-effort: PuzzleResult doesn't carry metadata after the parser
        // converts it; nothing to show today. Hook left for future fields.
        []
    }
}

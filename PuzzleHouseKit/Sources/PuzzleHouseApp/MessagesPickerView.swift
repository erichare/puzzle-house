import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import PuzzleCore
import PuzzleParsers

/// Used by the iMessage app extension: lists today's results so the user can
/// tap one to insert into the active conversation.
public struct MessagesPickerView: View {
    @Bindable public var store: HouseholdStore
    public let onSend: @MainActor (PuzzleResult) -> Void

    public init(store: HouseholdStore, onSend: @escaping @MainActor (PuzzleResult) -> Void) {
        self.store = store
        self.onSend = onSend
    }

    public var body: some View {
        Group {
            switch store.state {
            case .idle, .loading:
                ProgressView()
            case .error(let message):
                ContentUnavailableView(
                    "iCloud isn't ready",
                    systemImage: "icloud.slash",
                    description: Text(message)
                )
            case .ready:
                if store.todayResults.isEmpty {
                    ContentUnavailableView(
                        "Nothing to send yet",
                        systemImage: "tray",
                        description: Text("Submit a result in the main app, then come back here.")
                    )
                } else {
                    list
                }
            }
        }
        .task { if store.state == .idle { await store.bootstrap() } }
    }

    static let quickReactions = ["🔥", "🎉", "👏", "🤯", "😂", "❤️"]

    private var list: some View {
        List {
            Section {
                ForEach(store.todayResults) { result in
                    Button {
                        onSend(result)
                    } label: {
                        row(result)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if result.authorUserID != store.currentUserID {
                            reactionMenu(for: result)
                        } else {
                            Text("Your own result")
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                        Button {
                            onSend(result)
                        } label: {
                            Label("Send to chat", systemImage: "paperplane")
                        }
                    }
                }
            } header: {
                Text(headerText)
            } footer: {
                Text("Long-press a result to react with an emoji.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func reactionMenu(for result: PuzzleResult) -> some View {
        Menu {
            ForEach(Self.quickReactions, id: \.self) { emoji in
                Button {
                    Task {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        try? await store.react(to: result.id, emoji: emoji)
                    }
                } label: {
                    Text("\(emoji)  React")
                }
            }
            if store.myReaction(for: result.id) != nil {
                Divider()
                Button(role: .destructive) {
                    Task { try? await store.clearMyReaction(on: result.id) }
                } label: {
                    Label("Clear my reaction", systemImage: "xmark.circle")
                }
            }
        } label: {
            Label("React", systemImage: "face.smiling")
        }
    }

    private var headerText: String {
        if let h = store.selectedHousehold {
            return "Today — \(h.iconEmoji) \(h.name)"
        }
        return "Today"
    }

    @ViewBuilder
    private func row(_ result: PuzzleResult) -> some View {
        let game = Game.known(by: result.gameID)
        HStack(spacing: 12) {
            Text(game?.emoji ?? "🧩").font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(game?.displayName ?? result.gameID) #\(result.puzzleNumber)")
                    .font(.headline)
                Text(MessagesPickerView.summary(for: result))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "paperplane.fill").foregroundStyle(.tint)
        }
        .padding(.vertical, 4)
    }

    /// Shared with the iMessage `MSMessage` builder so the bubble text matches
    /// what the user sees in the picker row.
    public static func summary(for result: PuzzleResult) -> String {
        switch result.rawScore {
        case .guesses(let used, let outOf, let solved):
            return solved ? "\(used)/\(outOf)" : "X/\(outOf)"
        case .mistakes(let count, _, let solved):
            return solved ? "\(count) mistake\(count == 1 ? "" : "s")" : "Failed"
        case .hints(let count, _):
            return "\(count) hint\(count == 1 ? "" : "s")"
        case .custom(let value, let solved):
            return solved ? "Solved (\(Int(value)))" : "\(Int(value)) correct"
        }
    }
}

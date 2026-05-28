import SwiftUI
import PuzzleCore
import PuzzleScoring
import PuzzleUI

/// Per-game completion grid for today: rows = games, columns = members,
/// cells = ✓ (solved), ✗ (failed), — (not played). Renders above the
/// per-result cards so you can see at a glance what's still outstanding.
public struct ChecklistSection: View {
    @Bindable var store: HouseholdStore

    public init(store: HouseholdStore) {
        self.store = store
    }

    private var rows: [ChecklistRow] {
        ChecklistMatrix.build(
            results: store.todayResults,
            memberUserIDs: store.members.map(\.userID),
            tracked: Game.known.map(\.id),
            day: store.today
        )
    }

    public var body: some View {
        let rows = self.rows
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today's puzzles").font(.headline)
                Spacer()
                progressLabel(for: rows)
            }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.gameID) { idx, row in
                    if idx > 0 { Divider() }
                    rowView(row)
                }
            }
        }
        .padding(PuzzleTheme.cardPadding)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: PuzzleTheme.cardCornerRadius))
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    @ViewBuilder
    private func rowView(_ row: ChecklistRow) -> some View {
        let game = Game.known(by: row.gameID)
        let launchURL = game?.launchURL
        let uid = store.currentUserID
        // Current user's cell first, so you can scan your own column.
        let ordered = row.perMember.filter { $0.userID == uid } + row.perMember.filter { $0.userID != uid }
        HStack(spacing: 12) {
            Text(game?.emoji ?? "🧩")
                .frame(width: 22)
            if let launchURL {
                Link(destination: launchURL) {
                    HStack(spacing: 4) {
                        Text(game?.displayName ?? row.gameID)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 110, alignment: .leading)
            } else {
                Text(game?.displayName ?? row.gameID)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(minWidth: 110, alignment: .leading)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(ordered, id: \.userID) { entry in
                    cell(userID: entry.userID, state: entry.state, isMe: entry.userID == uid)
                }
            }
            Text("\(row.solvedCount)/\(row.totalCount)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func cell(userID: String, state: CompletionState, isMe: Bool) -> some View {
        let emoji = store.avatarEmoji(for: userID)
        ZStack {
            Circle()
                .strokeBorder(borderColor(for: state), lineWidth: 1.5)
                .background(Circle().fill(fillColor(for: state)))
                .frame(width: 28, height: 28)
            Text(stateGlyph(for: state, fallback: emoji))
                .font(.caption)
        }
        // Uniform footprint for every cell so columns line up; the accent ring
        // marks your own cell (always the first in each row).
        .frame(width: 34, height: 34)
        .overlay {
            if isMe {
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: 33, height: 33)
            }
        }
        .accessibilityLabel(Text("\(store.displayName(for: userID))\(isMe ? " (you)" : "") \(accessibilityState(for: state))"))
    }

    private func stateGlyph(for state: CompletionState, fallback emoji: String) -> String {
        switch state {
        case .solved: return "✓"
        case .failed: return "✗"
        case .notPlayed: return "–"
        }
    }

    private func fillColor(for state: CompletionState) -> Color {
        switch state {
        case .solved: return .green.opacity(0.18)
        case .failed: return .red.opacity(0.15)
        case .notPlayed: return Color.secondary.opacity(0.08)
        }
    }

    private func borderColor(for state: CompletionState) -> Color {
        switch state {
        case .solved: return .green.opacity(0.55)
        case .failed: return .red.opacity(0.45)
        case .notPlayed: return Color.secondary.opacity(0.35)
        }
    }

    private func accessibilityState(for state: CompletionState) -> String {
        switch state {
        case .solved: return "solved"
        case .failed: return "failed"
        case .notPlayed: return "not played"
        }
    }

    @ViewBuilder
    private func progressLabel(for rows: [ChecklistRow]) -> some View {
        let total = rows.reduce(0) { $0 + $1.totalCount }
        let houseDone = rows.reduce(0) { $0 + $1.solvedCount }
        if total > 0 {
            let myTotal = rows.count
            let myDone = store.currentUserID.map { uid in
                rows.filter { $0.perMember.first(where: { $0.userID == uid })?.state == .solved }.count
            }
            HStack(spacing: 6) {
                if let myDone {
                    Text("You \(myDone)/\(myTotal)")
                        .fontWeight(.semibold)
                        .foregroundStyle(myDone == myTotal ? Color.green : Color.primary)
                    Text("·").foregroundStyle(.tertiary)
                }
                Text("House \(houseDone)/\(total)")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }
}

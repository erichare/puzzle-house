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
                Text(progressLabel(for: rows))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
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
                ForEach(row.perMember, id: \.userID) { entry in
                    cell(userID: entry.userID, state: entry.state)
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
    private func cell(userID: String, state: CompletionState) -> some View {
        let emoji = store.avatarEmoji(for: userID)
        ZStack {
            Circle()
                .strokeBorder(borderColor(for: state), lineWidth: 1.5)
                .background(Circle().fill(fillColor(for: state)))
                .frame(width: 28, height: 28)
            Text(stateGlyph(for: state, fallback: emoji))
                .font(.caption)
        }
        .accessibilityLabel(Text("\(store.displayName(for: userID)) \(accessibilityState(for: state))"))
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

    private func progressLabel(for rows: [ChecklistRow]) -> String {
        let total = rows.reduce(0) { $0 + $1.totalCount }
        let done = rows.reduce(0) { $0 + $1.solvedCount }
        guard total > 0 else { return "" }
        return "\(done) of \(total) done"
    }
}

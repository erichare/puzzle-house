import SwiftUI
import PuzzleCore
import PuzzleScoring
import PuzzleUI

/// Per-game completion grid for today: rows = games, columns = members,
/// cells = ✓ (solved), ✗ (failed), — (not played). Renders above the
/// per-result cards so you can see at a glance what's still outstanding.
public struct ChecklistSection: View {
    @Bindable var store: HouseholdStore
    /// Optional tap handler so matrix cells open a member's detail. Nil = inert.
    var onSelectMember: ((String) -> Void)?

    public init(store: HouseholdStore, onSelectMember: ((String) -> Void)? = nil) {
        self.store = store
        self.onSelectMember = onSelectMember
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
        .puzzleCard()
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
        let base = MatrixCell(
            state: state,
            isMe: isMe,
            accessibilityName: store.displayName(for: userID)
        )
        if let onSelectMember {
            Button { onSelectMember(userID) } label: { base }
                .buttonStyle(.plain)
        } else {
            base
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

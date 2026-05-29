import SwiftUI
import PuzzleCore
import PuzzleParsers
import PuzzleScoring
import PuzzleUI

/// Groups the rolling 14-day history by day and lets the user expand each
/// day to see who played what. Pulled straight from `recentResults` so
/// there's no extra fetch.
public struct HistoryView: View {
    @Bindable var store: HouseholdStore

    public init(store: HouseholdStore) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.recentResults.isEmpty {
                ContentUnavailableView(
                    "No history yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Submit a few results — they'll show up here grouped by day.")
                )
            } else {
                list
            }
        }
        .refreshable { await store.refresh() }
        .paneNavigation(title: "History")
    }

    private var list: some View {
        List {
            ForEach(groupedDays, id: \.day) { group in
                Section(header: Text(group.label)) {
                    let board = CombinedScore.leaderboard(group.results, day: group.day)
                    if board.isEmpty {
                        Text("No play").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(board.enumerated()), id: \.element.userID) { idx, score in
                            HStack(spacing: 12) {
                                Text("\(idx + 1)")
                                    .font(.caption).foregroundStyle(.secondary).frame(width: 16)
                                Avatar(
                                    emoji: store.avatarEmoji(for: score.userID),
                                    displayName: store.displayName(for: score.userID),
                                    size: 24,
                                    photoData: store.avatarPhotoData(for: score.userID)
                                )
                                Text(store.displayName(for: score.userID))
                                Spacer()
                                Text(String(format: "%+.2f", score.combined))
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(idx == 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            }
                        }
                        ForEach(group.results) { result in
                            DisclosureGroup {
                                Text(result.gridData ?? "(no grid)")
                                    .font(.system(.caption, design: .monospaced))
                            } label: {
                                HStack {
                                    let game = Game.known(by: result.gameID)
                                    Text(game?.emoji ?? "🧩")
                                    Text("\(game?.displayName ?? result.gameID) #\(result.puzzleNumber)")
                                    Spacer()
                                    Text(store.displayName(for: result.authorUserID))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if result.authorUserID == store.currentUserID {
                                    Button(role: .destructive) {
                                        Task { try? await store.deleteResult(result) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    private struct DayGroup {
        let day: PuzzleDay
        let label: String
        let results: [PuzzleResult]
    }

    private var groupedDays: [DayGroup] {
        let byDay = Dictionary(grouping: store.recentResults, by: \.puzzleDay)
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        let tz = store.selectedHousehold?.timeZone ?? .current
        return byDay.keys.sorted(by: >).map { day in
            let date = day.startOfDay(in: tz)
            let label = day == store.today ? "Today" : formatter.string(from: date)
            return DayGroup(
                day: day,
                label: label,
                results: (byDay[day] ?? []).sorted { $0.submittedAt < $1.submittedAt }
            )
        }
    }
}

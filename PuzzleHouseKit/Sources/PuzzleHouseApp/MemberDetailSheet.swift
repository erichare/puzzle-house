import SwiftUI
import PuzzleCore
import PuzzleParsers
import PuzzleScoring
import PuzzleUI

/// Tap a member's row in the leaderboard or stats to see their results today
/// + per-game streaks + championships this week.
public struct MemberDetailSheet: View {
    @Bindable var store: HouseholdStore
    let userID: String
    @State private var openResult: PuzzleResult?
    @Environment(\.dismiss) private var dismiss

    public init(store: HouseholdStore, userID: String) {
        self.store = store
        self.userID = userID
    }

    public var body: some View {
        let mine = store.todayResults.filter { $0.authorUserID == userID }
        let weekly = WeeklyStatsCalculator.compute(
            results: store.recentResults,
            memberUserIDs: [userID],
            today: store.today,
            windowDays: 7
        ).perMember.first
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let weekly {
                        weeklyCard(weekly)
                    }
                    recordsCard
                    if userID != store.currentUserID, let me = store.currentUserID {
                        headToHeadCard(viewer: me)
                    }
                    activityStrip
                    streakRows
                    GameBreakdownSection(store: store, userID: userID)
                    TrophyShelfView(items: store.achievements(for: userID))
                        .puzzleCard()
                    todaySection(mine)
                }
                .padding()
            }
            .navigationTitle(store.displayName(for: userID))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $openResult) { r in
                ResultDetailSheet(store: store, result: r)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Avatar(
                emoji: store.avatarEmoji(for: userID),
                displayName: store.displayName(for: userID),
                size: 64,
                photoData: store.avatarPhotoData(for: userID)
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(store.displayName(for: userID)).font(.title3).bold()
                if let h = store.selectedHousehold {
                    Text("in \(h.iconEmoji) \(h.name)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var recordsCard: some View {
        let r = MemberProfileStats.records(results: store.allResults, userID: userID)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Records").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                stat("Solved", String(r.totalSolved))
                stat("Played", String(r.totalPlayed))
                stat("Rate", "\(Int((r.solveRate * 100).rounded()))%")
                stat("Days", String(r.activeDays))
            }
            if r.bestWordleGuesses != nil || r.bestConnectionsMistakes != nil {
                HStack(spacing: 12) {
                    if let w = r.bestWordleGuesses { stat("Best Wordle", "\(w)/6") }
                    if let c = r.bestConnectionsMistakes { stat("Best Conn.", "\(c) off") }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    private func headToHeadCard(viewer: String) -> some View {
        let h = MemberProfileStats.headToHead(results: store.allResults, viewer: viewer, opponent: userID)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Head-to-head").font(.subheadline).foregroundStyle(.secondary)
            if h.total == 0 {
                Text("No shared puzzles yet.").font(.caption).foregroundStyle(.tertiary)
            } else {
                HStack {
                    Text("You").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(h.wins)–\(h.losses)\(h.ties > 0 ? "–\(h.ties)" : "")")
                        .font(.title3.bold().monospacedDigit())
                    Spacer()
                    Text(store.displayName(for: userID)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    private var activityStrip: some View {
        let timeline = MemberProfileStats.activityTimeline(
            results: store.allResults, userID: userID, today: store.today, days: 28
        )
        return VStack(alignment: .leading, spacing: 6) {
            Text("Last 4 weeks").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                ForEach(timeline) { day in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(activityColor(day.gamesPlayed))
                        .frame(width: 8, height: 8)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Activity over the last 4 weeks")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    private func activityColor(_ count: Int) -> Color {
        switch count {
        case 0: return Color.secondary.opacity(0.12)
        case 1: return Color.accentColor.opacity(0.35)
        case 2: return Color.accentColor.opacity(0.6)
        default: return Color.accentColor
        }
    }

    private func weeklyCard(_ m: WeeklyStats.PerMember) -> some View {
        HStack(spacing: 12) {
            stat("Days", String(m.daysPlayed))
            stat("🏆", String(m.championships))
            stat("✓", String(m.totalSolved))
            stat("🔥 best", String(m.longestStreak))
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var streakRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current streaks")
                .font(.subheadline).foregroundStyle(.secondary)
            ForEach(Game.known, id: \.id) { game in
                let s = store.gameStreak(userID: userID, gameID: game.id)
                HStack {
                    Text("\(game.emoji) \(game.displayName)")
                    Spacer()
                    if s > 0 {
                        Text("🔥 \(s)").monospacedDigit()
                    } else {
                        Text("—").foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func todaySection(_ mine: [PuzzleResult]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's results")
                .font(.subheadline).foregroundStyle(.secondary)
            if mine.isEmpty {
                Text("No results today yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
            } else {
                let visibility = store.spoilerMap
                ForEach(mine) { result in
                    let g = Game.known(by: result.gameID)
                    Button {
                        openResult = result
                    } label: {
                        ResultCard(
                            result: result,
                            authorName: store.displayName(for: result.authorUserID),
                            authorEmoji: store.avatarEmoji(for: result.authorUserID),
                            gameDisplayName: g?.displayName ?? result.gameID,
                            gameEmoji: g?.emoji ?? "🧩",
                            accentColor: g?.color ?? .accentColor,
                            hideGrid: (visibility[result.id] ?? .full) == .hidden,
                            reactionSummary: store.reactionSummary(for: result.id)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

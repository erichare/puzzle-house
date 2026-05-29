import SwiftUI
import PuzzleCore
import PuzzleScoring
import PuzzleUI

public struct StatsView: View {
    @Bindable var store: HouseholdStore
    @State private var openMember: String?

    public init(store: HouseholdStore) {
        self.store = store
    }

    private struct MemberID: Identifiable { let id: String }

    public var body: some View {
        ScrollView {
            let stats = WeeklyStatsCalculator.compute(
                results: store.recentResults,
                memberUserIDs: store.members.map(\.userID),
                today: store.today,
                windowDays: 7
            )
            VStack(alignment: .leading, spacing: 16) {
                summaryCards(stats: stats)
                highlightsSection
                memberTable(stats: stats)
            }
            .padding()
            .macReadableWidth()
        }
        .refreshable { await store.refresh() }
        .sheet(item: Binding(
            get: { openMember.map(MemberID.init) },
            set: { openMember = $0?.id }
        )) { picked in
            MemberDetailSheet(store: store, userID: picked.id)
        }
        .paneNavigation(title: "This week")
    }

    @ViewBuilder
    private var highlightsSection: some View {
        let highlights = StatsHighlights.compute(
            results: store.recentResults,
            memberDisplayName: { store.displayName(for: $0) },
            memberAvatar: { store.avatarEmoji(for: $0) },
            today: store.today,
            windowDays: 14
        )
        if !highlights.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Highlights")
                    .font(.headline)
                ForEach(highlights) { h in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: h.glyph)
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.title).font(.subheadline).bold()
                            Text(h.detail).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    @ViewBuilder
    private func summaryCards(stats: WeeklyStats) -> some View {
        HStack(spacing: 12) {
            summaryCard("Days", value: "\(stats.totalDaysPlayed)/\(stats.windowDays)")
            summaryCard("Puzzles", value: "\(stats.totalResults)")
            summaryCard("🔥 house", value: "\(store.houseStreak)")
        }
    }

    private func summaryCard(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2).fontWeight(.bold).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PuzzleTheme.cardPadding)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: PuzzleTheme.cardCornerRadius))
    }

    @ViewBuilder
    private func memberTable(stats: WeeklyStats) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Member").bold().frame(maxWidth: .infinity, alignment: .leading)
                Text("🏆").frame(width: 36, alignment: .trailing)
                Text("Days").frame(width: 48, alignment: .trailing)
                Text("✓").frame(width: 40, alignment: .trailing)
                Text("🔥").frame(width: 40, alignment: .trailing)
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 8)
            ForEach(stats.perMember, id: \.userID) { m in
                Divider()
                Button {
                    openMember = m.userID
                } label: {
                    HStack {
                        HStack(spacing: 10) {
                            Avatar(
                                emoji: store.avatarEmoji(for: m.userID),
                                displayName: store.displayName(for: m.userID),
                                size: 28
                            )
                            Text(store.displayName(for: m.userID))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(m.championships)").monospacedDigit().frame(width: 36, alignment: .trailing)
                        Text("\(m.daysPlayed)").monospacedDigit().frame(width: 48, alignment: .trailing)
                        Text("\(m.totalSolved)").monospacedDigit().frame(width: 40, alignment: .trailing)
                        Text("\(m.longestStreak)").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: PuzzleTheme.cardCornerRadius))
    }
}

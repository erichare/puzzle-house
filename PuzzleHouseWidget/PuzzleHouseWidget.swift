import WidgetKit
import SwiftUI
import PuzzleCloudKit

@main
struct PuzzleHouseWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayLeaderboardWidget()
    }
}

struct TodayLeaderboardWidget: Widget {
    let kind = "TodayLeaderboardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            TodayLeaderboardWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's House")
        .description("Today's leaderboard from your Puzzle House.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Timeline

struct LeaderboardEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    private var snapshotStore: WidgetSnapshotStore? {
        AppGroupContainer(appGroupIdentifier: PuzzleHouseIdentifiers.appGroup)
            .map { WidgetSnapshotStore(container: $0) }
    }

    func placeholder(in context: Context) -> LeaderboardEntry {
        LeaderboardEntry(date: Date(), snapshot: Self.demoSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (LeaderboardEntry) -> Void) {
        let snap = snapshotStore?.read() ?? Self.demoSnapshot
        completion(LeaderboardEntry(date: Date(), snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LeaderboardEntry>) -> Void) {
        let snap = snapshotStore?.read()
        let entry = LeaderboardEntry(date: Date(), snapshot: snap)
        // Refresh hourly — the main app calls WidgetCenter.reloadAllTimelines()
        // on every CloudKit sync so this is just a backstop.
        let next = Date().addingTimeInterval(60 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    static let demoSnapshot = WidgetSnapshot(
        updatedAt: Date(),
        householdName: "Family",
        householdIcon: "🏠",
        dayISO: "—",
        houseStreak: 0,
        entries: [
            .init(userID: "demo1", displayName: "Mom", avatarEmoji: "👩", combinedScore: 1.2, gamesPlayed: 3),
            .init(userID: "demo2", displayName: "Dad", avatarEmoji: "👨", combinedScore: 0.4, gamesPlayed: 2),
            .init(userID: "demo3", displayName: "Eric", avatarEmoji: "🧑", combinedScore: -0.3, gamesPlayed: 2),
        ]
    )
}

// MARK: - Views

struct TodayLeaderboardWidgetView: View {
    let entry: LeaderboardEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let snap = entry.snapshot {
            switch family {
            case .systemSmall: small(snap)
            default: medium(snap)
            }
        } else {
            ContentUnavailableView(
                "Open Puzzle House",
                systemImage: "puzzlepiece",
                description: Text("Sign in to see today's leaderboard.")
            )
        }
    }

    @ViewBuilder
    private func small(_ snap: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(snap)
            ForEach(Array(snap.entries.prefix(3).enumerated()), id: \.element.userID) { idx, e in
                HStack(spacing: 6) {
                    Text("\(idx + 1).").font(.caption.weight(.bold))
                        .foregroundStyle(idx == 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    Text(e.avatarEmoji)
                    Text(e.displayName).font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "%+.1f", e.combinedScore))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func medium(_ snap: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(snap)
            ForEach(Array(snap.entries.prefix(4).enumerated()), id: \.element.userID) { idx, e in
                HStack(spacing: 8) {
                    Text("\(idx + 1)").font(.callout.weight(.bold))
                        .foregroundStyle(idx == 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .frame(width: 18)
                    Text(e.avatarEmoji).font(.title3)
                    Text(e.displayName).font(.subheadline)
                    Spacer()
                    Text("\(e.gamesPlayed)×")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Text(String(format: "%+.2f", e.combinedScore))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func header(_ snap: WidgetSnapshot) -> some View {
        HStack {
            Text("\(snap.householdIcon) \(snap.householdName)")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer()
            if snap.houseStreak > 0 {
                Text("🔥\(snap.houseStreak)")
                    .font(.caption.weight(.semibold))
            }
        }
    }
}

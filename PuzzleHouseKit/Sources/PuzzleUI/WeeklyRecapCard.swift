import SwiftUI

/// A fixed-size shareable poster of the household's week, rendered to an image
/// via `ImageRenderer`. Uses solid/gradient fills (NOT `.glassEffect`, which
/// doesn't rasterize reliably) and takes plain values so it can be snapshotted
/// detached from the store.
public struct WeeklyRecapCard: View {
    public struct Row: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let emoji: String
        public let championships: Int
        public let totalSolved: Int

        public init(id: String, name: String, emoji: String, championships: Int, totalSolved: Int) {
            self.id = id
            self.name = name
            self.emoji = emoji
            self.championships = championships
            self.totalSolved = totalSolved
        }
    }

    public let householdName: String
    public let householdIcon: String
    public let weekRange: String
    public let houseStreak: Int
    public let totalPuzzles: Int
    public let rows: [Row]

    public init(
        householdName: String,
        householdIcon: String,
        weekRange: String,
        houseStreak: Int,
        totalPuzzles: Int,
        rows: [Row]
    ) {
        self.householdName = householdName
        self.householdIcon = householdIcon
        self.weekRange = weekRange
        self.houseStreak = houseStreak
        self.totalPuzzles = totalPuzzles
        self.rows = rows
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 36) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(householdIcon) \(householdName)")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(.white)
                Text(weekRange)
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.85))
            }

            HStack(spacing: 18) {
                bigStat("\(houseStreak)", "🔥 streak")
                bigStat("\(totalPuzzles)", "puzzles")
                bigStat("\(rows.count)", "players")
            }

            VStack(spacing: 14) {
                ForEach(Array(rows.prefix(5).enumerated()), id: \.element.id) { idx, row in
                    HStack(spacing: 18) {
                        Text(medal(idx)).font(.system(size: 40))
                        Text(row.emoji).font(.system(size: 40))
                        Text(row.name)
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("🏆 \(row.championships)   ✓ \(row.totalSolved)")
                            .font(.system(size: 32, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.vertical, 6)
                }
            }

            Spacer()
            Text("Puzzle House")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(64)
        .frame(width: 1080, height: 1350, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [Color(red: 0.36, green: 0.20, blue: 0.62), Color(red: 0.85, green: 0.35, blue: 0.40)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func bigStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 60, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
    }

    private func medal(_ idx: Int) -> String {
        switch idx {
        case 0: return "🥇"
        case 1: return "🥈"
        case 2: return "🥉"
        default: return "  "
        }
    }
}

import SwiftUI
import PuzzleScoring
import PuzzleUI

/// "Share this week" — renders a `WeeklyRecapCard` to an image via
/// `ImageRenderer` and offers it through a `ShareLink`. Works on iOS and macOS
/// (the only platform fork is `uiImage` vs `nsImage`).
struct RecapShareButton: View {
    let store: HouseholdStore
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                ShareLink(
                    item: image,
                    preview: SharePreview("Our Puzzle House week", image: image)
                ) {
                    Label("Share this week", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
            } else {
                Label("Preparing recap…", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .buttonStyle(.glass)
        .task(id: store.today) { image = renderRecap() }
    }

    @MainActor
    private func renderRecap() -> Image? {
        guard let household = store.selectedHousehold else { return nil }
        let stats = WeeklyStatsCalculator.compute(
            results: store.recentResults,
            memberUserIDs: store.members.map(\.userID),
            today: store.today,
            windowDays: 7
        )
        let rows = stats.perMember
            .sorted { ($0.championships, $0.totalSolved) > ($1.championships, $1.totalSolved) }
            .map { member in
                WeeklyRecapCard.Row(
                    id: member.userID,
                    name: store.displayName(for: member.userID),
                    emoji: store.avatarEmoji(for: member.userID),
                    championships: member.championships,
                    totalSolved: member.totalSolved
                )
            }
        let card = WeeklyRecapCard(
            householdName: household.name,
            householdIcon: household.iconEmoji,
            weekRange: "Week ending \(store.today.isoString)",
            houseStreak: store.houseStreak,
            totalPuzzles: stats.totalResults,
            rows: rows
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        #if os(iOS)
        if let ui = renderer.uiImage { return Image(uiImage: ui) }
        #elseif os(macOS)
        if let ns = renderer.nsImage { return Image(nsImage: ns) }
        #endif
        return nil
    }
}

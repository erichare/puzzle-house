import SwiftUI
import PuzzleCore
import PuzzleScoring
import PuzzleUI

/// Stats section: a cross-game win-rate overview plus a per-game guess
/// distribution card. Computes from the all-time `allResults` archive, so it
/// reflects full history rather than just the recent window.
struct GameBreakdownSection: View {
    let store: HouseholdStore
    /// When set, scope to one member (used by the member profile). Nil = household-wide.
    var userID: String? = nil

    var body: some View {
        let breakdowns = GameBreakdownStats.compute(results: store.allResults, userID: userID)
        if !breakdowns.isEmpty {
            VStack(alignment: .leading, spacing: PuzzleSpacing.m) {
                Text("By game")
                    .font(PuzzleFont.sectionHeader)

                VStack(alignment: .leading, spacing: PuzzleSpacing.s) {
                    Text("Win rate")
                        .font(PuzzleFont.caption)
                        .foregroundStyle(.secondary)
                    WinRateChart(rates: breakdowns.map(\.winRate))
                }
                .puzzleCard()

                ForEach(breakdowns) { breakdown in
                    let game = Game.known(by: breakdown.gameID)
                    VStack(alignment: .leading, spacing: PuzzleSpacing.s) {
                        HStack(spacing: PuzzleSpacing.s) {
                            Text(game?.emoji ?? "🧩")
                            Text(game?.displayName ?? breakdown.gameID)
                                .font(PuzzleFont.cardTitle)
                            Spacer()
                            Text("\(breakdown.winRate.solved)/\(breakdown.winRate.played)")
                                .font(PuzzleFont.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        GuessDistributionChart(
                            distribution: breakdown.distribution,
                            color: game?.color ?? .accentColor
                        )
                    }
                    .puzzleCard()
                }
            }
        }
    }
}

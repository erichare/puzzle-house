import SwiftUI
import Charts
import PuzzleCore
import PuzzleScoring
import PuzzleUI

/// Horizontal bars comparing win rate across games, each tinted by the game's
/// accent color with a trailing percentage label.
struct WinRateChart: View {
    let rates: [WinRate]

    var body: some View {
        Chart(rates) { wr in
            BarMark(
                x: .value("Win rate", wr.rate),
                y: .value("Game", Game.known(by: wr.gameID)?.displayName ?? wr.gameID)
            )
            .foregroundStyle((Game.known(by: wr.gameID)?.color ?? .accentColor).gradient)
            .cornerRadius(5)
            .annotation(position: .trailing) {
                Text("\(percent(wr.rate))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(Game.known(by: wr.gameID)?.displayName ?? wr.gameID)
            .accessibilityValue("\(percent(wr.rate)) percent, \(wr.solved) of \(wr.played)")
        }
        .chartXScale(domain: 0...1)
        .chartXAxis(.hidden)
        .frame(height: CGFloat(max(rates.count, 1)) * 38 + 12)
    }

    private func percent(_ rate: Double) -> Int { Int((rate * 100).rounded()) }
}

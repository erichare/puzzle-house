import SwiftUI
import Charts
import PuzzleScoring

/// Bar chart of how a single game was solved — one bar per guess/mistake count,
/// with the fail ("X") bucket in red at the far right.
struct GuessDistributionChart: View {
    let distribution: GuessDistribution
    let color: Color

    private var ordered: [DistributionBucket] {
        distribution.buckets.sorted { $0.order < $1.order }
    }

    var body: some View {
        Chart(ordered) { bucket in
            BarMark(
                x: .value("Result", bucket.label),
                y: .value("Count", bucket.count)
            )
            .foregroundStyle(bucket.label == "X" ? AnyShapeStyle(Color.red.opacity(0.7)) : AnyShapeStyle(color.gradient))
            .cornerRadius(4)
            .annotation(position: .top) {
                if bucket.count > 0 {
                    Text("\(bucket.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel(bucket.label == "X" ? "Did not solve" : "\(bucket.label) tries")
            .accessibilityValue("\(bucket.count)")
        }
        .chartXScale(domain: ordered.map(\.label))
        .chartYAxis(.hidden)
        .frame(height: 120)
    }
}

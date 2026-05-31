import SwiftUI
import PuzzleScoring

/// One badge tile: a tier-tinted glyph, earned in full color or greyed-and-dim
/// when locked, with a progress ring for multi-step locked badges.
public struct TrophyBadge: View {
    public let definition: AchievementDefinition
    public let earned: Bool
    public let progress: AchievementProgress?

    public init(definition: AchievementDefinition, earned: Bool, progress: AchievementProgress? = nil) {
        self.definition = definition
        self.earned = earned
        self.progress = progress
    }

    public var body: some View {
        VStack(spacing: PuzzleSpacing.s) {
            ZStack {
                Circle()
                    .fill(earned ? tint.opacity(0.18) : Color.secondary.opacity(0.08))
                    .frame(width: 56, height: 56)
                if let progress, !earned, progress.target > 1 {
                    Circle()
                        .trim(from: 0, to: progress.fraction)
                        .stroke(tint.opacity(0.5), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 56, height: 56)
                }
                Image(systemName: definition.glyph)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(earned ? AnyShapeStyle(tint) : AnyShapeStyle(Color.secondary))
            }
            Text(definition.title)
                .font(.caption2.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(earned ? .primary : .secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .opacity(earned ? 1 : 0.65)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var tint: Color {
        switch definition.tier {
        case .bronze: return Color(red: 0.80, green: 0.50, blue: 0.20)
        case .silver: return Color(red: 0.62, green: 0.64, blue: 0.67)
        case .gold: return Color(red: 0.95, green: 0.76, blue: 0.20)
        }
    }

    private var accessibilityLabel: String {
        if earned { return "\(definition.title), earned. \(definition.blurb)" }
        if let progress, progress.target > 1 {
            return "\(definition.title), locked, \(progress.current) of \(progress.target). \(definition.blurb)"
        }
        return "\(definition.title), locked. \(definition.blurb)"
    }
}

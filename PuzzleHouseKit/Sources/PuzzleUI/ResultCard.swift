import SwiftUI
import PuzzleCore

public struct ResultCard: View {
    public let result: PuzzleResult
    public let authorName: String
    public let authorEmoji: String
    public let gameDisplayName: String
    public let gameEmoji: String
    public let accentColor: Color
    public let hideGrid: Bool
    public let reactionSummary: [(emoji: String, count: Int)]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var totalReactions: Int { reactionSummary.reduce(0) { $0 + $1.count } }

    public init(
        result: PuzzleResult,
        authorName: String,
        authorEmoji: String,
        gameDisplayName: String,
        gameEmoji: String,
        accentColor: Color = .accentColor,
        hideGrid: Bool,
        reactionSummary: [(emoji: String, count: Int)] = []
    ) {
        self.result = result
        self.authorName = authorName
        self.authorEmoji = authorEmoji
        self.gameDisplayName = gameDisplayName
        self.gameEmoji = gameEmoji
        self.accentColor = accentColor
        self.hideGrid = hideGrid
        self.reactionSummary = reactionSummary
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Game-colored accent stripe on the leading edge.
            Rectangle()
                .fill(accentColor)
                .frame(width: 6)
            VStack(alignment: .leading, spacing: 12) {
                header
                GridReveal(gridData: result.gridData, isHidden: hideGrid)
                if !hideGrid {
                    footer
                }
            }
            .padding(PuzzleTheme.cardPadding)
        }
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: PuzzleTheme.cardCornerRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PuzzleTheme.cardCornerRadius)
                .strokeBorder(accentColor.opacity(0.22), lineWidth: 0.5)
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            Avatar(emoji: authorEmoji, displayName: authorName)
            VStack(alignment: .leading, spacing: 2) {
                Text(authorName).font(.headline)
                HStack(spacing: 4) {
                    Text(gameEmoji)
                    Text(gameDisplayName)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text("#\(result.puzzleNumber)")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
            Spacer()
            if hideGrid {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(scoreSummary)
                .font(.callout).fontWeight(.semibold)
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(accentColor.opacity(0.22), in: Capsule())
                .overlay(
                    Capsule().strokeBorder(accentColor.opacity(0.55), lineWidth: 0.5)
                )
            if !reactionSummary.isEmpty {
                HStack(spacing: 2) {
                    ForEach(reactionSummary.prefix(3), id: \.emoji) { pair in
                        Text(pair.emoji)
                    }
                    Text("\(totalReactions)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.10), in: Capsule())
                .animation(reduceMotion ? nil : .snappy, value: totalReactions)
            }
            Spacer()
            Text(result.submittedAt, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var scoreSummary: String {
        switch result.rawScore {
        case .guesses(let used, let outOf, let solved):
            return solved ? "\(used)/\(outOf)" : "X/\(outOf)"
        case .mistakes(let count, let maxAllowed, let solved):
            return solved ? "\(count) mistake\(count == 1 ? "" : "s")" : "Failed (\(maxAllowed) mistakes)"
        case .hints(let count, _):
            return "\(count) hint\(count == 1 ? "" : "s")"
        case .custom(let value, let solved):
            return solved ? "Solved (\(Int(value)))" : "Not solved (\(Int(value)))"
        }
    }
}

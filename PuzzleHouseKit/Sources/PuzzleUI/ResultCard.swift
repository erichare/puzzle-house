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

    public init(
        result: PuzzleResult,
        authorName: String,
        authorEmoji: String,
        gameDisplayName: String,
        gameEmoji: String,
        accentColor: Color = .accentColor,
        hideGrid: Bool
    ) {
        self.result = result
        self.authorName = authorName
        self.authorEmoji = authorEmoji
        self.gameDisplayName = gameDisplayName
        self.gameEmoji = gameEmoji
        self.accentColor = accentColor
        self.hideGrid = hideGrid
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
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: PuzzleTheme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: PuzzleTheme.cardCornerRadius)
                .strokeBorder(accentColor.opacity(0.18), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Avatar(emoji: authorEmoji, displayName: authorName)
            VStack(alignment: .leading, spacing: 2) {
                Text(authorName).font(.headline)
                HStack(spacing: 4) {
                    Text(gameEmoji)
                    Text(gameDisplayName)
                        .foregroundStyle(accentColor.opacity(0.85))
                        .fontWeight(.medium)
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
        HStack {
            Text(scoreSummary)
                .font(.callout).fontWeight(.semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(accentColor.opacity(0.18), in: Capsule())
                .foregroundStyle(accentColor)
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

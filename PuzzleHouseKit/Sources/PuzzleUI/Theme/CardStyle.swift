import SwiftUI

public extension View {
    /// The standard content card: padding + Liquid Glass material + a soft
    /// shadow. Bundles the `padding → glassEffect → shadow` trio that was
    /// repeated verbatim across the leaderboard, checklist, and stats cards.
    func puzzleCard(cornerRadius: CGFloat = PuzzleTheme.cardCornerRadius) -> some View {
        self
            .padding(PuzzleTheme.cardPadding)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

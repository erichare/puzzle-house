import SwiftUI
import PuzzleCore

public enum PuzzleTheme {
    public static let cardCornerRadius: CGFloat = 22
    public static let cardPadding: CGFloat = 16
    public static let streakRingLineWidth: CGFloat = 8

    public static let accent: Color = .accentColor
    public static let secondaryFill: Color = Color.secondary.opacity(0.15)
}

public extension Game {
    /// SwiftUI Color for the game's accent stripe.
    var color: Color {
        Color(red: red, green: green, blue: blue)
    }
}

/// Convenience modifiers so every card uses the same Liquid Glass shape.
public extension View {
    /// Apply the standard glass-card material with our default corner radius.
    func puzzleGlassCard() -> some View {
        self.glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: PuzzleTheme.cardCornerRadius)
        )
    }

    /// Glass-tinted pill for badges (e.g. the streak chip).
    func puzzleGlassPill(tint: Color = .accentColor) -> some View {
        self.glassEffect(.regular.tint(tint.opacity(0.55)), in: Capsule())
    }
}

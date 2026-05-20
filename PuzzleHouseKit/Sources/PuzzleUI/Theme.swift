import SwiftUI
import PuzzleCore

public enum PuzzleTheme {
    public static let cardCornerRadius: CGFloat = 18
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

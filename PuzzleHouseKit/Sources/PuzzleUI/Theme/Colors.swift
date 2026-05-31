import SwiftUI
import PuzzleScoring

/// Semantic color tokens. One source of truth so the matrix, charts, and any
/// future legends agree on what "solved" / "failed" / "champion" look like.
public enum PuzzleColor {
    public static let solved = Color.green
    public static let failed = Color.red
    public static let notPlayed = Color.secondary
    public static let championAccent = Color.orange
    public static let surfaceStroke = Color.secondary.opacity(0.35)
}

/// Completion-state colors, shared by the Today checklist matrix and anything
/// else that visualizes per-game solved/failed/not-played state.
public extension CompletionState {
    var fillColor: Color {
        switch self {
        case .solved: return PuzzleColor.solved.opacity(0.18)
        case .failed: return PuzzleColor.failed.opacity(0.15)
        case .notPlayed: return PuzzleColor.notPlayed.opacity(0.08)
        }
    }

    var borderColor: Color {
        switch self {
        case .solved: return PuzzleColor.solved.opacity(0.55)
        case .failed: return PuzzleColor.failed.opacity(0.45)
        case .notPlayed: return PuzzleColor.notPlayed.opacity(0.35)
        }
    }
}

/// The warm app-background gradient (cooler in dark mode). Promoted out of
/// `TodayView` so every redesigned screen and iPad column shares one backdrop.
public struct PuzzleBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        let isDark = colorScheme == .dark
        return LinearGradient(
            colors: isDark
                ? [Color(red: 0.10, green: 0.07, blue: 0.05),
                   Color(red: 0.16, green: 0.10, blue: 0.06)]
                : [Color(red: 1.00, green: 0.97, blue: 0.93),
                   Color(red: 1.00, green: 0.91, blue: 0.83)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

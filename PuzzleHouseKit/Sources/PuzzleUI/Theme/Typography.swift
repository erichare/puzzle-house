import SwiftUI

/// Semantic type roles built on scalable text styles. Defining fonts in terms
/// of `Font.title2`/`.headline`/etc. (never `.system(size:)`) is what makes
/// Dynamic Type work for free — every role scales with the user's text size.
public enum PuzzleFont {
    /// Large screen / household title.
    public static let screenTitle = Font.title2.bold()
    /// Section header ("Today's puzzles", "Results").
    public static let sectionHeader = Font.headline
    /// Title inside a card or row.
    public static let cardTitle = Font.body.weight(.semibold)
    /// Numeric metric (score, count) — monospaced digits so columns align.
    public static let metricValue = Font.body.monospacedDigit().weight(.semibold)
    /// Secondary / supporting caption.
    public static let caption = Font.caption
    /// Emphasized caption (progress labels, badges).
    public static let captionStrong = Font.caption.weight(.semibold)
    /// Glyph inside a matrix cell (✓ / ✗ / –).
    public static let cellGlyph = Font.caption
}

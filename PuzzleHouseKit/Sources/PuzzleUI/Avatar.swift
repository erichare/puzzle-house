import SwiftUI

public struct Avatar: View {
    public let emoji: String
    public let displayName: String
    public let size: CGFloat

    public init(emoji: String, displayName: String, size: CGFloat = 36) {
        self.emoji = emoji
        self.displayName = displayName
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle().fill(PuzzleTheme.secondaryFill)
            Text(emoji).font(.system(size: size * 0.55))
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text(displayName))
    }
}

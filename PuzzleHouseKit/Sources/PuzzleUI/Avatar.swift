import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct Avatar: View {
    public let emoji: String
    public let displayName: String
    public let size: CGFloat
    public let photoData: Data?

    public init(
        emoji: String,
        displayName: String,
        size: CGFloat = 36,
        photoData: Data? = nil
    ) {
        self.emoji = emoji
        self.displayName = displayName
        self.size = size
        self.photoData = photoData
    }

    public var body: some View {
        Group {
            #if canImport(UIKit)
            if let data = photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
            } else {
                emojiCircle
            }
            #else
            emojiCircle
            #endif
        }
        .accessibilityLabel(Text(displayName))
    }

    private var emojiCircle: some View {
        ZStack {
            Circle().fill(PuzzleTheme.secondaryFill)
            Text(emoji).font(.system(size: size * 0.55))
        }
        .frame(width: size, height: size)
    }
}

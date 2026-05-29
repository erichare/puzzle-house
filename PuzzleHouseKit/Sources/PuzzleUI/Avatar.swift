import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
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
            if let data = photoData, let image = Self.platformImage(from: data) {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
            } else {
                emojiCircle
            }
        }
        .accessibilityLabel(Text(displayName))
    }

    /// Decode avatar photo bytes into a SwiftUI `Image` on whichever platform
    /// we're running — `UIImage` on iOS, `NSImage` on macOS — so avatar photos
    /// render natively on the Mac instead of degrading to the emoji fallback.
    private static func platformImage(from data: Data) -> Image? {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #elseif canImport(AppKit)
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
        #else
        return nil
        #endif
    }

    private var emojiCircle: some View {
        ZStack {
            Circle().fill(PuzzleTheme.secondaryFill)
            Text(emoji).font(.system(size: size * 0.55))
        }
        .frame(width: size, height: size)
    }
}

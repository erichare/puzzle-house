import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// Renders the Puzzle House app icon and the iMessage app icon set.
//
// Usage:
//   swift run make-icon                          # main 1024×1024 to default path
//   swift run make-icon <output.png>             # main 1024×1024 to a custom path
//   swift run make-icon --imessage <out-dir>     # 11 iMessage icons (4:3) into <out-dir>
//
// All output PNGs are opaque (no alpha channel) — App Store's validator
// rejects icons with an alpha channel even when every pixel is fully opaque.

let args = CommandLine.arguments

enum Mode {
    case mainIcon(outputPath: String)
    case iMessageIcons(directory: String)
}

func resolveMode() -> Mode {
    let cwd = FileManager.default.currentDirectoryPath
    if args.contains("--imessage") {
        guard let idx = args.firstIndex(of: "--imessage"), idx + 1 < args.count else {
            fputs("error: --imessage requires an output directory\n", stderr); exit(2)
        }
        return .iMessageIcons(directory: args[idx + 1])
    }
    if args.count > 1, !args[1].hasPrefix("--") {
        return .mainIcon(outputPath: args[1])
    }
    return .mainIcon(outputPath: (cwd as NSString)
        .appendingPathComponent("PuzzleHouse/Assets.xcassets/AppIcon.appiconset/icon.png"))
}

let mode = resolveMode()

// MARK: - Rendering

/// Renders the Puzzle House icon at the given dimensions. The 2×2 tile grid
/// + center house scale uniformly for non-square aspect ratios.
func renderIcon(width: Int, height: Int) -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    // CGImageAlphaInfo.noneSkipLast — bitmap is 32 bpp RGBX (alpha
    // skipped), and the PNG that ImageIO writes from a CGImage in this
    // format has NO alpha channel at all. That's required for App Store
    // app icons; otherwise altool rejects with error 90717.
    guard let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }

    let canvas = CGRect(x: 0, y: 0, width: width, height: height)
    let w = CGFloat(width), h = CGFloat(height)
    let s = min(w, h)
    let radius = s * 0.22

    // Background gradient
    let bgTop = CGColor(srgbRed: 1.00, green: 0.91, blue: 0.83, alpha: 1)
    let bgBot = CGColor(srgbRed: 1.00, green: 0.69, blue: 0.53, alpha: 1)
    if let bg = CGGradient(
        colorsSpace: colorSpace, colors: [bgTop, bgBot] as CFArray, locations: [0, 1]
    ) {
        context.saveGState()
        // Always clip to a rounded rect; the OS masks app icons anyway,
        // but having the rendered bitmap match the masked shape keeps
        // the iMessage previews looking clean too.
        context.addPath(CGPath(roundedRect: canvas, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        context.drawLinearGradient(bg, start: CGPoint(x: 0, y: h), end: .zero, options: [])
        context.restoreGState()
    }

    // 2×2 tiles
    struct Tile { let color: CGColor }
    let tiles: [Tile] = [
        Tile(color: CGColor(srgbRed: 0.42, green: 0.66, blue: 0.39, alpha: 1)),   // Wordle (bottom-left)
        Tile(color: CGColor(srgbRed: 0.69, green: 0.51, blue: 0.78, alpha: 1)),   // Connections (bottom-right)
        Tile(color: CGColor(srgbRed: 0.23, green: 0.51, blue: 0.96, alpha: 1)),   // Strands (top-left)
        Tile(color: CGColor(srgbRed: 0.95, green: 0.84, blue: 0.25, alpha: 1)),   // Emoji Game (top-right)
    ]
    let tileSize = s * 0.31
    let tileCorner = s * 0.08
    let tileGap = s * 0.06
    let gridSide = tileSize * 2 + tileGap
    let originX = (w - gridSide) / 2
    let originY = (h - gridSide) / 2 - s * 0.02
    let positions: [CGPoint] = [
        .init(x: originX, y: originY),                              // bottom-left
        .init(x: originX + tileSize + tileGap, y: originY),         // bottom-right
        .init(x: originX, y: originY + tileSize + tileGap),         // top-left
        .init(x: originX + tileSize + tileGap, y: originY + tileSize + tileGap), // top-right
    ]
    for (i, tile) in tiles.enumerated() {
        let rect = CGRect(origin: positions[i], size: CGSize(width: tileSize, height: tileSize))
        context.saveGState()
        // Soft shadow only on larger renders — at 54×40 it just becomes mud.
        if s >= 256 {
            context.setShadow(
                offset: CGSize(width: 0, height: -s * 0.012),
                blur: s * 0.024,
                color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.18)
            )
        }
        let path = CGPath(roundedRect: rect, cornerWidth: tileCorner, cornerHeight: tileCorner, transform: nil)
        context.addPath(path)
        context.setFillColor(tile.color)
        context.fillPath()
        context.restoreGState()
    }

    // Center house glyph
    let fontSize = s * 0.22
    let font = CTFontCreateWithName("AppleColorEmoji" as CFString, fontSize, nil)
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "🏠", attributes: attrs))
    var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
    let textWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

    // White circle background for legibility.
    let circleR = max(textWidth, ascent + descent) / 2 + s * 0.028
    let circleRect = CGRect(x: w / 2 - circleR, y: h / 2 - circleR - s * 0.02,
                            width: circleR * 2, height: circleR * 2)
    context.saveGState()
    if s >= 256 {
        context.setShadow(offset: CGSize(width: 0, height: -s * 0.006),
                          blur: s * 0.016,
                          color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.3))
    }
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
    context.fillEllipse(in: circleRect)
    context.restoreGState()

    context.saveGState()
    context.textPosition = CGPoint(x: w / 2 - textWidth / 2,
                                   y: h / 2 - (ascent + descent) / 2 - s * 0.02)
    CTLineDraw(line, context)
    context.restoreGState()

    return context.makeImage()
}

// MARK: - PNG writing

func writePNG(_ image: CGImage, to url: URL) -> Bool {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                              withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { return false }
    // Belt-and-suspenders: tell ImageIO to omit alpha. CGImage created
    // via `.noneSkipLast` already encodes as opaque PNG, but setting
    // the destination property too makes the intent explicit.
    let properties: [CFString: Any] = [
        kCGImagePropertyHasAlpha: false,
    ]
    CGImageDestinationAddImage(dest, image, properties as CFDictionary)
    return CGImageDestinationFinalize(dest)
}

// MARK: - iMessage icon set

/// Required sizes for an iMessage app icon set (in points × scale).
/// The order matches Contents.json declarations below; filenames mirror
/// what Xcode emits when you generate a fresh stickersiconset.
struct IMessageIcon {
    let width: Int
    let height: Int
    let filename: String
}

let iMessageIcons: [IMessageIcon] = [
    .init(width: 1024, height: 768, filename: "icon-1024x768.png"),    // App Store marketing
    .init(width: 120,  height: 90,  filename: "icon-60x45@2x.png"),    // iPhone 2x
    .init(width: 180,  height: 135, filename: "icon-60x45@3x.png"),    // iPhone 3x
    .init(width: 134,  height: 100, filename: "icon-67x50@2x.png"),    // iPad 2x
    .init(width: 148,  height: 110, filename: "icon-74x55@2x.png"),    // iPad 2x large
    .init(width: 54,   height: 40,  filename: "icon-27x20@2x.png"),    // Messages app drawer
    .init(width: 81,   height: 60,  filename: "icon-27x20@3x.png"),
    .init(width: 64,   height: 48,  filename: "icon-32x24@2x.png"),    // Messages settings
    .init(width: 96,   height: 72,  filename: "icon-32x24@3x.png"),
]

/// Contents.json for the iMessage stickersiconset. Sizes are declared in
/// base points; the @2x / @3x scales above compose the actual pixel sizes
/// the App Store wants. iOS / iMessage look up the right asset by size +
/// scale + idiom.
let iMessageContentsJSON = """
{
  "images" : [
    { "filename" : "icon-60x45@2x.png", "idiom" : "iphone", "scale" : "2x", "size" : "60x45" },
    { "filename" : "icon-60x45@3x.png", "idiom" : "iphone", "scale" : "3x", "size" : "60x45" },
    { "filename" : "icon-67x50@2x.png", "idiom" : "ipad", "scale" : "2x", "size" : "67x50" },
    { "filename" : "icon-74x55@2x.png", "idiom" : "ipad", "scale" : "2x", "size" : "74x55" },
    { "filename" : "icon-27x20@2x.png", "idiom" : "universal", "platform" : "ios", "scale" : "2x", "size" : "27x20" },
    { "filename" : "icon-27x20@3x.png", "idiom" : "universal", "platform" : "ios", "scale" : "3x", "size" : "27x20" },
    { "filename" : "icon-32x24@2x.png", "idiom" : "universal", "platform" : "ios", "scale" : "2x", "size" : "32x24" },
    { "filename" : "icon-32x24@3x.png", "idiom" : "universal", "platform" : "ios", "scale" : "3x", "size" : "32x24" },
    { "filename" : "icon-1024x768.png", "idiom" : "ios-marketing", "platform" : "ios", "scale" : "1x", "size" : "1024x768" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "pre-rendered" : true }
}
"""

// MARK: - Driver

switch mode {
case .mainIcon(let outputPath):
    guard let img = renderIcon(width: 1024, height: 1024) else {
        fputs("error: couldn't render main icon\n", stderr); exit(1)
    }
    let url = URL(fileURLWithPath: outputPath)
    guard writePNG(img, to: url) else {
        fputs("error: couldn't write \(outputPath)\n", stderr); exit(1)
    }
    print("wrote \(outputPath) (1024x1024, opaque)")

case .iMessageIcons(let directory):
    let dir = URL(fileURLWithPath: directory)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let contentsURL = dir.appendingPathComponent("Contents.json")
    try? iMessageContentsJSON.write(to: contentsURL, atomically: true, encoding: .utf8)
    print("wrote \(contentsURL.path)")
    for spec in iMessageIcons {
        guard let img = renderIcon(width: spec.width, height: spec.height) else {
            fputs("error: couldn't render \(spec.filename)\n", stderr); exit(1)
        }
        let url = dir.appendingPathComponent(spec.filename)
        guard writePNG(img, to: url) else {
            fputs("error: couldn't write \(url.path)\n", stderr); exit(1)
        }
        print("wrote \(url.path) (\(spec.width)x\(spec.height))")
    }
}

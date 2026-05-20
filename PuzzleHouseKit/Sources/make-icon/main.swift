import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// Renders the Puzzle House app icon — a soft peach gradient with four
// rounded tiles representing Wordle (green), Connections (purple), Strands
// (blue), and Emoji Game (yellow), plus a tiny house glyph between them.
//
// Usage:
//   swift run make-icon [output.png]
// Defaults to PuzzleHouse/Assets.xcassets/AppIcon.appiconset/icon.png

let size: CGFloat = 1024
let radius: CGFloat = 220

let args = CommandLine.arguments
let outputPath: String = {
    if args.count > 1 { return args[1] }
    let fm = FileManager.default
    let cwd = fm.currentDirectoryPath
    return (cwd as NSString).appendingPathComponent("PuzzleHouse/Assets.xcassets/AppIcon.appiconset/icon.png")
}()

let colorSpace = CGColorSpaceCreateDeviceRGB()
let context = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

// MARK: - Background gradient

let bgTop = CGColor(srgbRed: 1.00, green: 0.91, blue: 0.83, alpha: 1)
let bgBot = CGColor(srgbRed: 1.00, green: 0.69, blue: 0.53, alpha: 1)
let bgGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [bgTop, bgBot] as CFArray,
    locations: [0.0, 1.0]
)!
context.saveGState()
let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
                    cornerWidth: radius, cornerHeight: radius, transform: nil)
context.addPath(bgPath); context.clip()
context.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: 0, y: 0),
    options: []
)
context.restoreGState()

// MARK: - Tiles

struct Tile {
    let color: CGColor
    let position: CGPoint
}

let tileSide: CGFloat = 320
let tileCorner: CGFloat = 80
let tileGap: CGFloat = 56
let gridSide = tileSide * 2 + tileGap
let originX = (size - gridSide) / 2
let originY = (size - gridSide) / 2 - 20

let tiles: [Tile] = [
    Tile(color: CGColor(srgbRed: 0.42, green: 0.66, blue: 0.39, alpha: 1),  // Wordle 🟩
         position: CGPoint(x: originX, y: originY + tileSide + tileGap)),
    Tile(color: CGColor(srgbRed: 0.69, green: 0.51, blue: 0.78, alpha: 1),  // Connections 🟪
         position: CGPoint(x: originX + tileSide + tileGap, y: originY + tileSide + tileGap)),
    Tile(color: CGColor(srgbRed: 0.23, green: 0.51, blue: 0.96, alpha: 1),  // Strands 🔵
         position: CGPoint(x: originX, y: originY)),
    Tile(color: CGColor(srgbRed: 0.95, green: 0.84, blue: 0.25, alpha: 1),  // Emoji Game 🟡
         position: CGPoint(x: originX + tileSide + tileGap, y: originY)),
]

for tile in tiles {
    let rect = CGRect(origin: tile.position, size: CGSize(width: tileSide, height: tileSide))
    // Soft drop shadow
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -10),
        blur: 24,
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.18)
    )
    let tilePath = CGPath(roundedRect: rect, cornerWidth: tileCorner, cornerHeight: tileCorner, transform: nil)
    context.addPath(tilePath)
    context.setFillColor(tile.color)
    context.fillPath()
    context.restoreGState()

    // Subtle inner highlight on top edge
    let highlight = CGRect(
        x: rect.minX + 24,
        y: rect.maxY - 36,
        width: rect.width - 48,
        height: 4
    )
    context.saveGState()
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.45))
    let hPath = CGPath(roundedRect: highlight, cornerWidth: 2, cornerHeight: 2, transform: nil)
    context.addPath(hPath); context.fillPath()
    context.restoreGState()
}

// MARK: - Center house glyph

let house = "🏠" as NSString
let fontSize: CGFloat = 220
let font = CTFontCreateWithName("AppleColorEmoji" as CFString, fontSize, nil)
let attrs: [NSAttributedString.Key: Any] = [
    NSAttributedString.Key(kCTFontAttributeName as String): font,
]
let astr = NSAttributedString(string: house as String, attributes: attrs)
let line = CTLineCreateWithAttributedString(astr)
var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
let height = ascent + descent

context.saveGState()
let centerX = size / 2 - width / 2
let centerY = size / 2 - (ascent + descent) / 2 - 20
context.setShadow(
    offset: CGSize(width: 0, height: -6),
    blur: 16,
    color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.3)
)
// Slight white circle behind for legibility
let circleR = max(width, height) / 2 + 28
let circleRect = CGRect(
    x: size / 2 - circleR,
    y: size / 2 - circleR - 20,
    width: circleR * 2,
    height: circleR * 2
)
context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
context.fillEllipse(in: circleRect)
context.restoreGState()

context.saveGState()
context.textPosition = CGPoint(x: centerX, y: centerY)
CTLineDraw(line, context)
context.restoreGState()

// MARK: - Write PNG

guard let cgImage = context.makeImage() else {
    fputs("error: failed to create CGImage\n", stderr)
    exit(1)
}
let url = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
guard let destination = CGImageDestinationCreateWithURL(
    url as CFURL, UTType.png.identifier as CFString, 1, nil
) else {
    fputs("error: couldn't open \(outputPath) for writing\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(destination, cgImage, nil)
if !CGImageDestinationFinalize(destination) {
    fputs("error: PNG write failed\n", stderr)
    exit(1)
}

print("wrote \(outputPath) (\(Int(size))x\(Int(size)))")

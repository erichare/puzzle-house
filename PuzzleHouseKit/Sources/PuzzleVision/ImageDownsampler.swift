import Foundation
import CoreGraphics
import ImageIO

/// Memory-safe image downsampling for Share Extension use. NEVER load a full
/// screenshot via `UIImage(data:)` — a 4032×3024 image decompresses to ~50 MB
/// and Share Extensions die at ~120 MB. Always go through here.
public enum ImageDownsampler {

    public static func downsample(
        data: Data,
        maxPixelDimension: Int
    ) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return nil
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
    }

    /// Decode a full-resolution `CGImage` from image data, cross-platform
    /// (no `UIImage`/`NSImage` round-trip). Prefer `downsample(data:maxPixelDimension:)`
    /// for large screenshots in memory-constrained contexts; use this when you
    /// already hold reasonably-sized bytes (e.g. a pasteboard/dropped image on
    /// macOS) and want the original pixels for OCR.
    public static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

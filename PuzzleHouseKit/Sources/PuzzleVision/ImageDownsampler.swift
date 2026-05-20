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
}

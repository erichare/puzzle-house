import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Downsamples + JPEG-encodes an avatar image so it fits cleanly inside a
/// CloudKit `Data` field (target ~50 KB). Keeps the CKRecord well under the
/// 1 MB per-record cap with room for everything else.
public enum AvatarPhotoEncoder {
    public static let maxPixelDimension = 256
    public static let jpegQuality: CGFloat = 0.7

    /// Pass in raw image data (any format `CGImageSource` can read — HEIC,
    /// JPEG, PNG, etc.) and get back a square-ish 256×256 JPEG.
    public static func encode(_ rawData: Data) -> Data? {
        guard let cgImage = ImageDownsampler.downsample(
            data: rawData, maxPixelDimension: maxPixelDimension
        ) else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            out, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: jpegQuality,
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }
}

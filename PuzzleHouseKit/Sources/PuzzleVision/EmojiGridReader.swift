import Foundation
import CoreGraphics
import PuzzleCore

/// Reconstructs the Emoji Game grid from raw pixel sampling. Vision OCR cannot
/// reliably read emoji glyphs, so week 3 implementation will:
///
/// 1. Detect the grid bounding box (large rectangular region of saturated tiles).
/// 2. Sample center pixels of each cell.
/// 3. Match each sampled color/feature against a known reference set bundled
///    with the app.
/// 4. Synthesize a text payload of the form
///    `EmojiGame #<n> <correct>/<total>\n<rows>` for `EmojiGameParser`.
///
/// The skeleton below establishes the public surface.
public enum EmojiGridReader {

    public struct ReadResult: Hashable, Sendable {
        public let correct: Int
        public let total: Int
        public let grid: String
    }

    public static func read(image: CGImage, puzzleNumber: Int) throws -> ReadResult {
        throw OCRError.unrecognizedPuzzleFormat
    }
}

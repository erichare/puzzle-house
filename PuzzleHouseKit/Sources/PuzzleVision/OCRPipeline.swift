import Foundation
import CoreGraphics
#if canImport(Vision)
import Vision
#endif
import PuzzleCore
import PuzzleParsers

public enum OCRError: Error, Sendable {
    case visionUnavailable
    case noTextRecognized
    case unrecognizedPuzzleFormat
}

/// Runs Vision text recognition on a screenshot and tries each registered
/// parser against the recovered text. The real Emoji Game pipeline (week 3)
/// will additionally pixel-sample the grid since Vision is unreliable for
/// emoji glyphs.
public enum OCRPipeline {

    public static func recognizeText(in image: CGImage) async throws -> String {
        #if canImport(Vision)
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                if lines.isEmpty {
                    continuation.resume(throwing: OCRError.noTextRecognized)
                } else {
                    continuation.resume(returning: lines.joined(separator: "\n"))
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
        #else
        throw OCRError.visionUnavailable
        #endif
    }

    public static func parseResult(from image: CGImage) async throws -> ParsedResult {
        let text = try await recognizeText(in: image)
        if let parsed = ParserRegistry.parse(text) {
            return parsed
        }
        // Fall back to Emoji Game extraction: Vision can read the score
        // caption even when it can't read the emoji grid.
        if let synthesized = synthesizeEmojiGame(from: text) {
            if let parsed = ParserRegistry.parse(synthesized) {
                return parsed
            }
        }
        throw OCRError.unrecognizedPuzzleFormat
    }

    /// Pulls a puzzle number and an "X/Y" score line out of arbitrary OCR
    /// text and shapes them into `EmojiGameParser`-compatible input. Returns
    /// nil if neither can be found with confidence.
    public static func synthesizeEmojiGame(from text: String) -> String? {
        let lines = text.split(separator: "\n").map(String.init)
        let puzzleNumber = lines.lazy
            .compactMap { line -> Int? in
                let pattern = #"#(\d{1,5})"#
                guard let range = line.range(of: pattern, options: .regularExpression) else { return nil }
                return Int(line[range].dropFirst())
            }
            .first
        let scorePair = lines.lazy
            .compactMap { line -> (Int, Int)? in
                let pattern = #"\b(\d{1,2})\s*/\s*(\d{1,2})\b"#
                guard let range = line.range(of: pattern, options: .regularExpression) else { return nil }
                let parts = line[range].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
                guard parts.count == 2 else { return nil }
                return (parts[0], parts[1])
            }
            .first
        guard let n = puzzleNumber, let (correct, total) = scorePair else {
            return nil
        }
        return "EmojiGame #\(n) \(correct)/\(total)"
    }
}

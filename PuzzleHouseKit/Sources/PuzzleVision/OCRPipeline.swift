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

    /// Pulls a puzzle number and a score out of arbitrary OCR text and shapes
    /// them into `EmojiGameParser`-compatible input. Tries three patterns in
    /// order; returns the first match.
    ///
    /// - `EmojiGame #42 4/5` synthesized text from earlier (perfect)
    /// - `Emoji Game #42 ... 3/5 correct` from a header with X/Y elsewhere
    /// - `6 moves` from Apple News' Emoji Game post-solve screen — no
    ///   visible puzzle number, so we use today's `puzzleDayEpoch` as the
    ///   number (each day's puzzle is uniquely identified by its date)
    public static func synthesizeEmojiGame(
        from text: String,
        today: Date = Date(),
        timeZone: TimeZone = .current
    ) -> String? {
        let lines = text.split(separator: "\n").map(String.init)

        let explicitNumber = lines.lazy
            .compactMap { line -> Int? in
                guard let r = line.range(of: #"#(\d{1,6})"#, options: .regularExpression) else { return nil }
                return Int(line[r].dropFirst())
            }
            .first

        // 1) Try X/Y score
        if let pair: (Int, Int) = lines.lazy.compactMap({ line -> (Int, Int)? in
            guard let r = line.range(of: #"\b(\d{1,2})\s*/\s*(\d{1,2})\b"#, options: .regularExpression) else { return nil }
            let parts = line[r].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            guard parts.count == 2 else { return nil }
            return (parts[0], parts[1])
        }).first {
            let number = explicitNumber ?? Self.dateBasedPuzzleNumber(today, in: timeZone)
            return "EmojiGame #\(number) \(pair.0)/\(pair.1)"
        }

        // 2) Apple News post-solve screen: "N moves"
        if let moves = lines.lazy.compactMap({ line -> Int? in
            guard let r = line.range(of: #"(?i)\b(\d{1,2})\s+moves?\b"#, options: .regularExpression) else { return nil }
            let digits = line[r].prefix { !$0.isWhitespace }
            return Int(digits)
        }).first {
            let number = explicitNumber ?? Self.dateBasedPuzzleNumber(today, in: timeZone)
            let categories = extractEmojiGameCategories(from: lines)
            let header = "EmojiGame #\(number) moves=\(moves)"
            if categories.isEmpty {
                return header
            }
            return header + "\n" + categories.joined(separator: "\n")
        }

        return nil
    }

    /// Pulls the puzzle's category-answer phrases out of OCR text. Apple
    /// News' Emoji Game renders these in big all-caps (e.g. "BLUE CHEESE").
    /// Heuristic: keep lines that are at least 4 chars, mostly letters, and
    /// uppercase. Drops UI chrome like "MORE PUZZLES" or "SHARE".
    public static func extractEmojiGameCategories(from lines: [String]) -> [String] {
        let blocklist: Set<String> = [
            "MORE PUZZLES", "SHARE", "SHARE SCORE", "DONE", "LEADERBOARDS",
            "GET STARTED", "GET STARTED:", "PLAY AGAIN", "APPLE NEWS",
        ]
        return lines.compactMap { rawLine -> String? in
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 4 else { return nil }
            let letters = trimmed.filter { $0.isLetter }
            guard letters.count >= 4 else { return nil }
            // Require everything to be uppercase letters, spaces, apostrophes,
            // or ampersands — Apple News' rendering uses that subset.
            let allowed = CharacterSet.uppercaseLetters
                .union(.whitespaces)
                .union(CharacterSet(charactersIn: "'&-"))
            guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
            // Need at least one capital letter (skips pure punctuation rows).
            guard trimmed.contains(where: { $0.isUppercase }) else { return nil }
            if blocklist.contains(trimmed) { return nil }
            return trimmed
        }
        .prefix(3)              // Apple News' Emoji Game has 3 categories
        .map { $0 }
    }

    /// `YYYYMMDD` integer — keeps one Emoji Game record per day even when
    /// the source app doesn't expose a puzzle number.
    static func dateBasedPuzzleNumber(_ date: Date, in zone: TimeZone) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let parts = cal.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 1970) * 10_000 + (parts.month ?? 1) * 100 + (parts.day ?? 1)
    }
}

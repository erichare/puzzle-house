import Foundation
import PuzzleCore

/// Apple News' Emoji Game has no native share-text format. The OCR pipeline in
/// `PuzzleVision` reconstructs the result into one of two synthetic payloads
/// that this parser then handles:
///
/// 1. Score-based:  `EmojiGame #42 4/5` — N correct out of M total
/// 2. Moves-based:  `EmojiGame #42 moves=6` — solved with N moves (fewer is
///    better; used when the source UI only exposes "N moves taken")
///
/// Both forms set `rawScore` such that higher `goodness` = better play.
public enum EmojiGameParser: PuzzleParser {
    public static let gameID = Game.emojiGame.id
    public static let displayName = Game.emojiGame.displayName

    private static let xyPattern = #"^EmojiGame\s+#?(\d+)\s+(\d+)/(\d+)\s*$"#
    private static let movesPattern = #"^EmojiGame\s+#?(\d+)\s+moves=(\d+)\s*$"#

    public static func canParse(_ text: String) -> Bool {
        let first = ParserHelpers.firstLine(text)
        return first.range(of: xyPattern, options: .regularExpression) != nil
            || first.range(of: movesPattern, options: .regularExpression) != nil
    }

    public static func parse(_ text: String) throws -> ParsedResult {
        let normalized = ParserHelpers.normalize(text)
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let header = lines.first else {
            throw PuzzleParserError.missingHeader(gameID: gameID)
        }

        let grid = lines.dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        if let xy = try matchXY(header) {
            let solved = xy.correct == xy.total
            return ParsedResult(
                gameID: gameID,
                puzzleNumber: xy.number,
                rawScore: .custom(value: Double(xy.correct), solved: solved),
                gridData: grid.isEmpty ? nil : grid,
                metadata: ["correct": String(xy.correct), "outOf": String(xy.total)]
            )
        }
        if let mv = try matchMoves(header) {
            // Fewer moves = better. Convert to goodness by negating so the
            // CombinedScore z-score ranks lower-move players higher.
            return ParsedResult(
                gameID: gameID,
                puzzleNumber: mv.number,
                rawScore: .custom(value: -Double(mv.moves), solved: true),
                gridData: grid.isEmpty ? nil : grid,
                metadata: ["moves": String(mv.moves)]
            )
        }
        throw PuzzleParserError.missingHeader(gameID: gameID)
    }

    // MARK: - Regex helpers

    private struct XY { let number: Int; let correct: Int; let total: Int }
    private struct Moves { let number: Int; let moves: Int }

    private static func matchXY(_ header: String) throws -> XY? {
        let regex = try NSRegularExpression(pattern: xyPattern)
        let nsRange = NSRange(header.startIndex..<header.endIndex, in: header)
        guard let m = regex.firstMatch(in: header, range: nsRange), m.numberOfRanges == 4,
              let nRange = Range(m.range(at: 1), in: header),
              let cRange = Range(m.range(at: 2), in: header),
              let tRange = Range(m.range(at: 3), in: header),
              let n = Int(header[nRange]),
              let c = Int(header[cRange]),
              let t = Int(header[tRange])
        else { return nil }
        return XY(number: n, correct: c, total: t)
    }

    private static func matchMoves(_ header: String) throws -> Moves? {
        let regex = try NSRegularExpression(pattern: movesPattern)
        let nsRange = NSRange(header.startIndex..<header.endIndex, in: header)
        guard let m = regex.firstMatch(in: header, range: nsRange), m.numberOfRanges == 3,
              let nRange = Range(m.range(at: 1), in: header),
              let movesRange = Range(m.range(at: 2), in: header),
              let n = Int(header[nRange]),
              let mv = Int(header[movesRange])
        else { return nil }
        return Moves(number: n, moves: mv)
    }
}

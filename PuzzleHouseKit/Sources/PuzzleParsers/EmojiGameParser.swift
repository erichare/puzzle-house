import Foundation
import PuzzleCore

/// Apple News' Emoji Game has no native share-text format. The OCR pipeline in
/// `PuzzleVision` reconstructs the result into a synthetic text payload that
/// this parser then handles. Format we agree on:
///
///     EmojiGame #42 4/5
///     😀😀😀😀😀
///
/// Until OCR ships in week 3, this parser is registered but inert — `canParse`
/// returns true only for the synthetic prefix so paste-from-NYT flows are never
/// accidentally routed here.
public enum EmojiGameParser: PuzzleParser {
    public static let gameID = Game.emojiGame.id
    public static let displayName = Game.emojiGame.displayName

    private static let headerPattern = #"^EmojiGame\s+#?(\d+)\s+(\d+)/(\d+)\s*$"#

    public static func canParse(_ text: String) -> Bool {
        let first = ParserHelpers.firstLine(text)
        return first.range(of: headerPattern, options: .regularExpression) != nil
    }

    public static func parse(_ text: String) throws -> ParsedResult {
        let normalized = ParserHelpers.normalize(text)
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let header = lines.first else {
            throw PuzzleParserError.missingHeader(gameID: gameID)
        }
        let regex = try NSRegularExpression(pattern: headerPattern)
        let nsRange = NSRange(header.startIndex..<header.endIndex, in: header)
        guard let match = regex.firstMatch(in: header, range: nsRange), match.numberOfRanges == 4,
              let numberRange = Range(match.range(at: 1), in: header),
              let correctRange = Range(match.range(at: 2), in: header),
              let totalRange = Range(match.range(at: 3), in: header),
              let puzzleNumber = Int(header[numberRange]),
              let correct = Int(header[correctRange]),
              let total = Int(header[totalRange])
        else {
            throw PuzzleParserError.missingHeader(gameID: gameID)
        }

        let grid = lines.dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        let solved = correct == total
        return ParsedResult(
            gameID: gameID,
            puzzleNumber: puzzleNumber,
            rawScore: .custom(value: Double(correct), solved: solved),
            gridData: grid.isEmpty ? nil : grid,
            metadata: ["correct": String(correct), "outOf": String(total)]
        )
    }
}

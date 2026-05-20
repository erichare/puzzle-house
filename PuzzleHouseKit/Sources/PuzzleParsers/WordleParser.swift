import Foundation
import PuzzleCore

/// Wordle share text:
///
///     Wordle 1,247 4/6
///
///     ⬛🟨⬛⬛⬛
///     ⬛⬛🟨🟨⬛
///     🟨🟩🟨⬛⬛
///     🟩🟩🟩🟩🟩
///
/// Variants:
/// - Hard mode appends `*` after the score: `4/6*`
/// - Failed runs use `X/6` instead of a number
/// - Light mode uses ⬜ instead of ⬛
/// - Number may have a comma group separator
public enum WordleParser: PuzzleParser {
    public static let gameID = Game.wordle.id
    public static let displayName = Game.wordle.displayName

    private static let headerPattern = #"^Wordle\s+([\d,]+)\s+(X|\d+)/(\d+)\*?\s*$"#
    private static let gridTiles: Set<Character> = ["⬛", "⬜", "🟨", "🟩"]

    public static func canParse(_ text: String) -> Bool {
        let first = ParserHelpers.firstLine(text)
        return first.range(of: headerPattern, options: .regularExpression) != nil
    }

    public static func parse(_ text: String) throws -> ParsedResult {
        let normalized = ParserHelpers.normalize(text)
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let header = lines.first,
              let match = header.range(of: headerPattern, options: .regularExpression),
              match.lowerBound == header.startIndex
        else {
            throw PuzzleParserError.missingHeader(gameID: gameID)
        }

        let captures = WordleParser.captureHeader(header)
        guard let puzzleNumber = ParserHelpers.parseNumber(captures.number),
              let outOf = Int(captures.outOf)
        else {
            throw PuzzleParserError.malformedScore(gameID: gameID, detail: header)
        }

        let solved = captures.used != "X"
        let used: Int
        if solved {
            guard let parsed = Int(captures.used) else {
                throw PuzzleParserError.malformedScore(gameID: gameID, detail: header)
            }
            used = parsed
        } else {
            used = outOf + 1
        }

        let grid = lines
            .dropFirst()
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .filter { line in
                line.allSatisfy { gridTiles.contains($0) || $0.isWhitespace }
            }

        if solved && grid.count != used {
            throw PuzzleParserError.malformedGrid(
                gameID: gameID,
                detail: "expected \(used) rows, found \(grid.count)"
            )
        }

        return ParsedResult(
            gameID: gameID,
            puzzleNumber: puzzleNumber,
            rawScore: .guesses(used: used, outOf: outOf, solved: solved),
            gridData: grid.joined(separator: "\n"),
            metadata: [
                "hardMode": header.hasSuffix("*") ? "true" : "false",
            ]
        )
    }

    // MARK: - Regex helper

    private static func captureHeader(_ header: String) -> (number: String, used: String, outOf: String) {
        let regex = try? NSRegularExpression(pattern: headerPattern)
        let range = NSRange(header.startIndex..<header.endIndex, in: header)
        guard let m = regex?.firstMatch(in: header, range: range),
              m.numberOfRanges == 4,
              let r1 = Range(m.range(at: 1), in: header),
              let r2 = Range(m.range(at: 2), in: header),
              let r3 = Range(m.range(at: 3), in: header)
        else {
            return ("", "", "")
        }
        return (String(header[r1]), String(header[r2]), String(header[r3]))
    }
}

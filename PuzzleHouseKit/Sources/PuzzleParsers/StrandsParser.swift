import Foundation
import PuzzleCore

/// Strands share text:
///
///     Strands #234
///     "Today's theme"
///     🔵🟡🔵🔵
///     🔵🔵🔵🔵
///
/// 🟡 = spangram, 🔵 = theme word, 💡 = hint used.
/// Strands has no fail state — every grid completes — so "score" is hints used.
public enum StrandsParser: PuzzleParser {
    public static let gameID = Game.strands.id
    public static let displayName = Game.strands.displayName

    private static let tiles: Set<Character> = ["🔵", "🟡", "💡"]
    private static let headerPattern = #"^Strands\s*#?(\d+)\s*$"#

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

        let digits = header[match].drop(while: { !$0.isNumber }).prefix(while: { $0.isNumber })
        guard let puzzleNumber = Int(digits) else {
            throw PuzzleParserError.missingHeader(gameID: gameID)
        }

        var theme: String?
        var gridLines: [String] = []
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.allSatisfy({ tiles.contains($0) }) {
                gridLines.append(trimmed)
            } else if theme == nil {
                theme = trimmed
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }

        guard !gridLines.isEmpty else {
            throw PuzzleParserError.malformedGrid(gameID: gameID, detail: "no tiles found")
        }

        let hints = gridLines.reduce(0) { $0 + $1.countingOccurrences(of: ["💡"]) }
        return ParsedResult(
            gameID: gameID,
            puzzleNumber: puzzleNumber,
            rawScore: .hints(count: hints, solved: true),
            gridData: gridLines.joined(separator: "\n"),
            metadata: theme.map { ["theme": $0] } ?? [:]
        )
    }
}

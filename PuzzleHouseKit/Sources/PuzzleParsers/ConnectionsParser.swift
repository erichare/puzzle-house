import Foundation
import PuzzleCore

/// Connections share text:
///
///     Connections
///     Puzzle #234
///     🟪🟪🟪🟪
///     🟨🟨🟨🟨
///     🟦🟦🟦🟦
///     🟩🟩🟩🟩
///
/// Each row is one guess: all-same-color = correct group, mixed = a mistake.
/// Solved means all four groups guessed; you fail after 4 mistakes.
public enum ConnectionsParser: PuzzleParser {
    public static let gameID = Game.connections.id
    public static let displayName = Game.connections.displayName

    private static let tiles: Set<Character> = ["🟨", "🟩", "🟦", "🟪", "🟫", "🟧"]
    private static let maxMistakes = 4
    private static let groupSize = 4

    public static func canParse(_ text: String) -> Bool {
        let normalized = ParserHelpers.normalize(text)
        let firstLine = normalized.split(separator: "\n").first.map(String.init) ?? ""
        return firstLine.range(of: #"^Connections\s*$"#, options: .regularExpression) != nil
    }

    public static func parse(_ text: String) throws -> ParsedResult {
        let normalized = ParserHelpers.normalize(text)
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first?.range(of: #"^Connections\s*$"#, options: .regularExpression) != nil else {
            throw PuzzleParserError.missingHeader(gameID: gameID)
        }
        guard let puzzleNumber = Self.extractPuzzleNumber(lines) else {
            throw PuzzleParserError.missingHeader(gameID: gameID)
        }

        let rows = lines
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return false }
                return trimmed.allSatisfy { tiles.contains($0) }
            }
            .filter { $0.count == groupSize }

        guard !rows.isEmpty else {
            throw PuzzleParserError.malformedGrid(gameID: gameID, detail: "no emoji rows found")
        }

        let mistakes = rows.reduce(0) { acc, row in
            let unique = Set(row)
            return acc + (unique.count == 1 ? 0 : 1)
        }
        let correctGroups = rows.count - mistakes
        let solved = correctGroups >= groupSize && mistakes < maxMistakes + 1

        return ParsedResult(
            gameID: gameID,
            puzzleNumber: puzzleNumber,
            rawScore: .mistakes(count: mistakes, maxAllowed: maxMistakes, solved: solved),
            gridData: rows.joined(separator: "\n"),
            metadata: ["correctGroups": String(correctGroups)]
        )
    }

    private static func extractPuzzleNumber(_ lines: [String]) -> Int? {
        let pattern = #"^Puzzle\s*#?(\d+)\s*$"#
        for line in lines.prefix(5) {
            guard let range = line.range(of: pattern, options: .regularExpression) else { continue }
            let digits = line[range].drop(while: { !$0.isNumber })
                .prefix(while: { $0.isNumber })
            return Int(digits)
        }
        return nil
    }
}

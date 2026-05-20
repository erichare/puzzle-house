import Foundation
import PuzzleCore
import PuzzleParsers

/// Reads a puzzle share text from stdin (or from `--text "..."`) and prints the
/// parsed result. Useful for sanity-checking parsers without an Xcode build.
///
/// Usage:
///   echo "Wordle 1,247 4/6\n\n⬛⬛⬛⬛⬛..." | swift run puzzlecheck
///   swift run puzzlecheck --text "Wordle 1,247 4/6\n..."

func readInput() -> String {
    let args = CommandLine.arguments
    if let idx = args.firstIndex(of: "--text"), idx + 1 < args.count {
        return args[idx + 1]
    }
    var buffer = ""
    while let line = readLine(strippingNewline: false) {
        buffer += line
    }
    return buffer
}

let text = readInput().trimmingCharacters(in: .whitespacesAndNewlines)

guard !text.isEmpty else {
    FileHandle.standardError.write(Data("error: no input provided\n".utf8))
    exit(2)
}

guard let parsed = ParserRegistry.parse(text) else {
    FileHandle.standardError.write(Data("error: unrecognized puzzle format\n".utf8))
    exit(1)
}

print("game:    \(parsed.gameID)")
print("puzzle:  #\(parsed.puzzleNumber)")
print("score:   \(formatScore(parsed.rawScore))")
print("solved:  \(parsed.rawScore.solved ? "yes" : "no")")
if !parsed.metadata.isEmpty {
    print("meta:    \(parsed.metadata.sorted { $0.key < $1.key }.map { "\($0)=\($1)" }.joined(separator: ", "))")
}
if let grid = parsed.gridData, !grid.isEmpty {
    print("grid:")
    for line in grid.split(separator: "\n") {
        print("  \(line)")
    }
}

func formatScore(_ score: RawScore) -> String {
    switch score {
    case .guesses(let used, let outOf, let solved):
        return solved ? "\(used)/\(outOf)" : "X/\(outOf)"
    case .mistakes(let count, let max, let solved):
        return solved ? "\(count) mistake(s) of \(max)" : "failed (\(count)/\(max) mistakes)"
    case .hints(let count, _):
        return "\(count) hint(s)"
    case .custom(let value, let solved):
        return "\(value) (\(solved ? "solved" : "not solved"))"
    }
}

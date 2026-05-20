import Foundation
import PuzzleCore

public enum SpoilerVisibility: Hashable, Sendable {
    /// Show the full grid and score.
    case full
    /// Show only that the author played; hide grid and score.
    case hidden
}

public enum SpoilerPolicy {

    /// Decides whether a viewer should see the full grid/score for a given result.
    ///
    /// Rules:
    /// - If `hideSpoilersUntilSolved` is off in the viewer's preferences: always `.full`.
    /// - The viewer's own results: always `.full`.
    /// - Otherwise: `.full` only if the viewer has submitted their own result
    ///   for the same `(gameID, puzzleNumber)`.
    public static func visibility(
        of result: PuzzleResult,
        viewerUserID: String,
        viewerResults: [PuzzleResult],
        viewerPreferences: UserPreferences
    ) -> SpoilerVisibility {
        if !viewerPreferences.hideSpoilersUntilSolved { return .full }
        if result.authorUserID == viewerUserID { return .full }
        let solvedSamePuzzle = viewerResults.contains {
            $0.authorUserID == viewerUserID
                && $0.gameID == result.gameID
                && $0.puzzleNumber == result.puzzleNumber
        }
        return solvedSamePuzzle ? .full : .hidden
    }

    /// Convenience that builds a viewer-relative lookup map. Useful when
    /// rendering a list — pay the cost once.
    public static func visibilities(
        for results: [PuzzleResult],
        viewerUserID: String,
        viewerPreferences: UserPreferences
    ) -> [PuzzleResult.ID: SpoilerVisibility] {
        let viewerResults = results.filter { $0.authorUserID == viewerUserID }
        var out: [PuzzleResult.ID: SpoilerVisibility] = [:]
        for r in results {
            out[r.id] = visibility(
                of: r,
                viewerUserID: viewerUserID,
                viewerResults: viewerResults,
                viewerPreferences: viewerPreferences
            )
        }
        return out
    }
}

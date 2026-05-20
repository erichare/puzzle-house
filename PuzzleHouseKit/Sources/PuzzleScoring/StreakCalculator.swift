import Foundation
import PuzzleCore

public enum StreakCalculator {

    /// "Active" cutoff: a member who hasn't played in this many days is excluded
    /// from house-streak math, so one person on vacation doesn't break it.
    public static let activeWindowDays = 14

    /// Per-game streak for a single user.
    /// Counts consecutive days ending at `today` (inclusive) that contain at least
    /// one result for `gameID`. A gap of one day breaks it.
    public static func gameStreak(
        results: [PuzzleResult],
        gameID: String,
        userID: String,
        today: PuzzleDay
    ) -> Int {
        let days = Set(
            results
                .filter { $0.gameID == gameID && $0.authorUserID == userID }
                .map(\.puzzleDay)
        )
        return countBackwards(from: today, while: { days.contains($0) })
    }

    /// House streak: consecutive days where every *active* household member
    /// submitted at least one puzzle.
    public static func houseStreak(
        results: [PuzzleResult],
        memberUserIDs: [String],
        today: PuzzleDay
    ) -> Int {
        let active = activeMembers(results: results, memberUserIDs: memberUserIDs, today: today)
        guard !active.isEmpty else { return 0 }

        let resultsByDay = Dictionary(grouping: results, by: \.puzzleDay)
        return countBackwards(from: today) { day in
            guard let dayResults = resultsByDay[day] else { return false }
            let playersThatDay = Set(dayResults.map(\.authorUserID))
            return active.isSubset(of: playersThatDay)
        }
    }

    public static func activeMembers(
        results: [PuzzleResult],
        memberUserIDs: [String],
        today: PuzzleDay
    ) -> Set<String> {
        let cutoff = today.advanced(by: -activeWindowDays)
        var active: Set<String> = []
        for uid in memberUserIDs {
            let hasRecent = results.contains {
                $0.authorUserID == uid && $0.puzzleDay > cutoff
            }
            if hasRecent { active.insert(uid) }
        }
        return active
    }

    private static func countBackwards(
        from start: PuzzleDay,
        while predicate: (PuzzleDay) -> Bool
    ) -> Int {
        var count = 0
        var cursor = start
        while predicate(cursor) {
            count += 1
            cursor = cursor.advanced(by: -1)
        }
        return count
    }
}

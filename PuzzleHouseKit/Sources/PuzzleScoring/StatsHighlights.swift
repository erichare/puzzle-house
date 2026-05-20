import Foundation
import PuzzleCore

public struct StatsHighlight: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let glyph: String   // SF Symbol name

    public init(id: String, title: String, detail: String, glyph: String) {
        self.id = id
        self.title = title
        self.detail = detail
        self.glyph = glyph
    }
}

/// Derives a handful of "did you know?" factoids from the rolling 14-day
/// window. Each highlight is independent — if its source data is missing,
/// it's just skipped, so the section gracefully shrinks for new households.
public enum StatsHighlights {

    public static func compute(
        results: [PuzzleResult],
        memberDisplayName: @escaping (String) -> String,
        memberAvatar: @escaping (String) -> String,
        today: PuzzleDay,
        windowDays: Int = 14
    ) -> [StatsHighlight] {
        let earliest = today.advanced(by: -(windowDays - 1))
        let window = results.filter { $0.puzzleDay >= earliest && $0.puzzleDay <= today }
        guard !window.isEmpty else { return [] }

        var out: [StatsHighlight] = []

        // 1. Most-played game
        let byGame = Dictionary(grouping: window, by: \.gameID).mapValues(\.count)
        if let top = byGame.max(by: { $0.value < $1.value }) {
            let name = Game.known(by: top.key)?.displayName ?? top.key
            let emoji = Game.known(by: top.key)?.emoji ?? "🧩"
            out.append(StatsHighlight(
                id: "most-played",
                title: "Most-played game",
                detail: "\(emoji) \(name) — \(top.value) plays this fortnight",
                glyph: "chart.bar.fill"
            ))
        }

        // 2. Championship leader (most days topping the combined-score leaderboard)
        let days = Set(window.map(\.puzzleDay))
        var champCounts: [String: Int] = [:]
        for day in days {
            let board = CombinedScore.leaderboard(window, day: day)
            if let top = board.first { champCounts[top.userID, default: 0] += 1 }
        }
        if let leader = champCounts.max(by: { $0.value < $1.value }), leader.value > 0 {
            let avatar = memberAvatar(leader.key)
            let name = memberDisplayName(leader.key)
            out.append(StatsHighlight(
                id: "champ",
                title: "Reigning champion",
                detail: "\(avatar) \(name) topped the leaderboard \(leader.value) day\(leader.value == 1 ? "" : "s")",
                glyph: "trophy.fill"
            ))
        }

        // 3. Longest single-game streak across the household
        var streakBest: (String, String, Int)?
        for member in Set(window.map(\.authorUserID)) {
            for game in Set(window.filter { $0.authorUserID == member }.map(\.gameID)) {
                let s = StreakCalculator.gameStreak(
                    results: window, gameID: game, userID: member, today: today
                )
                if s > (streakBest?.2 ?? 0) {
                    streakBest = (member, game, s)
                }
            }
        }
        if let (uid, gid, count) = streakBest, count >= 2 {
            let name = memberDisplayName(uid)
            let game = Game.known(by: gid)?.displayName ?? gid
            out.append(StatsHighlight(
                id: "streak",
                title: "Longest current streak",
                detail: "\(memberAvatar(uid)) \(name) — 🔥 \(count) \(game) day\(count == 1 ? "" : "s")",
                glyph: "flame.fill"
            ))
        }

        // 4. Earliest submitter (median submit time)
        let bySubmitter = Dictionary(grouping: window, by: \.authorUserID)
            .mapValues { entries -> Double in
                let cal = Calendar(identifier: .gregorian)
                let minutes = entries.map { r -> Double in
                    let c = cal.dateComponents([.hour, .minute], from: r.submittedAt)
                    return Double(c.hour ?? 0) * 60 + Double(c.minute ?? 0)
                }
                return minutes.sorted()[minutes.count / 2]
            }
        if let earliest = bySubmitter.min(by: { $0.value < $1.value }), bySubmitter.count > 1 {
            let hours = Int(earliest.value) / 60
            let mins = Int(earliest.value) % 60
            out.append(StatsHighlight(
                id: "early",
                title: "Earliest player",
                detail: "\(memberAvatar(earliest.key)) \(memberDisplayName(earliest.key)) — usually plays by \(String(format: "%d:%02d", hours, mins))",
                glyph: "alarm.fill"
            ))
        }

        // 5. Sweep days (one person tops every game played that day)
        var sweeps: [String: Int] = [:]
        for day in days {
            let dayResults = window.filter { $0.puzzleDay == day }
            let gamesPlayed = Set(dayResults.map(\.gameID))
            guard gamesPlayed.count > 1 else { continue }
            var winsByPlayer: [String: Int] = [:]
            for game in gamesPlayed {
                let perGame = dayResults.filter { $0.gameID == game }
                if let best = perGame.max(by: { $0.rawScore.goodness < $1.rawScore.goodness }) {
                    winsByPlayer[best.authorUserID, default: 0] += 1
                }
            }
            if let (uid, count) = winsByPlayer.max(by: { $0.value < $1.value }), count == gamesPlayed.count {
                sweeps[uid, default: 0] += 1
            }
        }
        if let (uid, count) = sweeps.max(by: { $0.value < $1.value }), count > 0 {
            out.append(StatsHighlight(
                id: "sweep",
                title: "Sweep days",
                detail: "\(memberAvatar(uid)) \(memberDisplayName(uid)) won every game on \(count) day\(count == 1 ? "" : "s")",
                glyph: "rosette"
            ))
        }

        // 6. Volume: total puzzles solved in the window
        let solved = window.filter { $0.rawScore.solved }.count
        out.append(StatsHighlight(
            id: "volume",
            title: "Household puzzles solved",
            detail: "\(solved) in the last \(windowDays) day\(windowDays == 1 ? "" : "s")",
            glyph: "checkmark.circle.fill"
        ))

        return out
    }
}

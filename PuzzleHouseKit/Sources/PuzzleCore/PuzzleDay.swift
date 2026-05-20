import Foundation

/// Anchors the concept of "a puzzle day" to a household's time zone so streaks
/// and leaderboards don't shift around when individual members travel.
public struct PuzzleDay: Hashable, Sendable, Codable, Comparable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = parts.year ?? 1970
        self.month = parts.month ?? 1
        self.day = parts.day ?? 1
    }

    public func startOfDay(in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(year: year, month: month, day: day)
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    public func advanced(by days: Int) -> PuzzleDay {
        let utc = TimeZone(identifier: "UTC") ?? .gmt
        let base = startOfDay(in: utc)
        let next = base.addingTimeInterval(TimeInterval(days) * 86_400)
        return PuzzleDay(date: next, timeZone: utc)
    }

    public static func < (lhs: PuzzleDay, rhs: PuzzleDay) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }
}

public extension PuzzleDay {
    var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Sortable integer encoding: `year*10000 + month*100 + day`.
    /// 2026-05-19 → 20260519. Used for CloudKit range queries since String
    /// fields don't support `>=`.
    var epoch: Int64 {
        Int64(year) * 10_000 + Int64(month) * 100 + Int64(day)
    }

    init(epoch: Int64) {
        let y = Int(epoch / 10_000)
        let m = Int((epoch % 10_000) / 100)
        let d = Int(epoch % 100)
        self.init(year: y, month: m, day: d)
    }
}

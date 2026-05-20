import XCTest
import PuzzleCore
@testable import PuzzleHouseApp

final class NotificationPolicyTests: XCTestCase {

    func testFallbackTimeWhenNoHistory() {
        let (h, m) = NotificationPolicy.reminderTime(
            preference: .auto,
            recentSubmissions: []
        )
        XCTAssertEqual(h, NotificationPolicy.fallbackReminderHour)
        XCTAssertEqual(m, NotificationPolicy.fallbackReminderMinute)
    }

    func testFixedPreferenceWins() {
        let (h, m) = NotificationPolicy.reminderTime(
            preference: .fixed(hour: 6, minute: 45),
            recentSubmissions: dates(at: [(8, 0), (9, 0), (10, 0)])
        )
        XCTAssertEqual(h, 6)
        XCTAssertEqual(m, 45)
    }

    func testAutoPicksMedianSubmitTime() {
        let (h, m) = NotificationPolicy.reminderTime(
            preference: .auto,
            recentSubmissions: dates(at: [(7, 30), (8, 0), (9, 15), (10, 0), (22, 0)]),
            in: TimeZone(identifier: "UTC")!
        )
        // Median is the 3rd entry of 5: 09:15
        XCTAssertEqual(h, 9)
        XCTAssertEqual(m, 15)
    }

    private func dates(at hourMinutes: [(Int, Int)]) -> [Date] {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 19; c.timeZone = TimeZone(identifier: "UTC")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return hourMinutes.map { hm in
            c.hour = hm.0; c.minute = hm.1
            return cal.date(from: c)!
        }
    }
}

import XCTest
@testable import PuzzleCore

final class PuzzleDayTests: XCTestCase {

    func testDateConversionAnchorsToTimeZone() {
        // 2026-05-19 01:00 UTC is still 2026-05-18 in Los Angeles.
        let utc = TimeZone(identifier: "UTC")!
        let la = TimeZone(identifier: "America/Los_Angeles")!
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 19
        components.hour = 1
        components.timeZone = utc
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let early = calendar.date(from: components)!
        XCTAssertEqual(PuzzleDay(date: early, timeZone: utc).isoString, "2026-05-19")
        XCTAssertEqual(PuzzleDay(date: early, timeZone: la).isoString, "2026-05-18")
    }

    func testAdvanceForwardAndBackward() {
        let d = PuzzleDay(year: 2026, month: 5, day: 19)
        XCTAssertEqual(d.advanced(by: 1).isoString, "2026-05-20")
        XCTAssertEqual(d.advanced(by: -1).isoString, "2026-05-18")
        XCTAssertEqual(d.advanced(by: 30).isoString, "2026-06-18")
    }

    func testOrderingAcrossYearBoundary() {
        let dec = PuzzleDay(year: 2025, month: 12, day: 31)
        let jan = PuzzleDay(year: 2026, month: 1, day: 1)
        XCTAssertTrue(dec < jan)
        XCTAssertTrue(jan > dec)
        XCTAssertEqual(dec.advanced(by: 1), jan)
    }

    func testEpochRoundTripsAndSortsCorrectly() {
        let day = PuzzleDay(year: 2026, month: 5, day: 19)
        XCTAssertEqual(day.epoch, 20260519)
        XCTAssertEqual(PuzzleDay(epoch: day.epoch), day)

        let earlier = PuzzleDay(year: 2025, month: 12, day: 31)
        let later = PuzzleDay(year: 2026, month: 1, day: 1)
        XCTAssertLessThan(earlier.epoch, later.epoch)
    }

    func testStartOfDayIsMidnightInZone() {
        let day = PuzzleDay(year: 2026, month: 5, day: 19)
        let utc = TimeZone(identifier: "UTC")!
        let start = day.startOfDay(in: utc)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let parts = calendar.dateComponents([.hour, .minute, .second], from: start)
        XCTAssertEqual(parts.hour, 0)
        XCTAssertEqual(parts.minute, 0)
        XCTAssertEqual(parts.second, 0)
    }
}

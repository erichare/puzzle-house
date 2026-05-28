import XCTest
@testable import PuzzleCore

final class MembershipTests: XCTestCase {

    func testDeterministicIDIsStableForSamePair() {
        let a = Membership.deterministicID(householdID: "household-abc", userID: "_user_42")
        let b = Membership.deterministicID(householdID: "household-abc", userID: "_user_42")
        XCTAssertEqual(a, b)
    }

    func testDeterministicIDDiffersByHouseholdAndUser() {
        let base = Membership.deterministicID(householdID: "h1", userID: "u1")
        XCTAssertNotEqual(base, Membership.deterministicID(householdID: "h2", userID: "u1"))
        XCTAssertNotEqual(base, Membership.deterministicID(householdID: "h1", userID: "u2"))
    }

    func testDeterministicIDSanitizesNonAlphanumerics() {
        // CloudKit user record names can carry punctuation; the token has to
        // stay a safe record-name string.
        let id = Membership.deterministicID(householdID: "h1", userID: "_a1b2:c3/d4")
        XCTAssertTrue(id.hasPrefix("mb-h1-"))
        XCTAssertFalse(id.contains(":"))
        XCTAssertFalse(id.contains("/"))
    }
}

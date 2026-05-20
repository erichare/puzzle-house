import Foundation
import PuzzleCore
import PuzzleCloudKit

/// In-memory `CloudKitServicing` for unit tests. Avoids any real CK calls.
final class FakeCloudKitService: CloudKitServicing, @unchecked Sendable {
    var userID: String
    var households: [Household]
    var members: [Household.ID: [Membership]]
    var resultsByDay: [Household.ID: [PuzzleDay: [PuzzleResult]]]
    var reactions: [Reaction] = []

    init(
        userID: String = "me",
        households: [Household] = [],
        members: [Household.ID: [Membership]] = [:],
        resultsByDay: [Household.ID: [PuzzleDay: [PuzzleResult]]] = [:]
    ) {
        self.userID = userID
        self.households = households
        self.members = members
        self.resultsByDay = resultsByDay
    }

    func currentUserRecordName() async throws -> String { userID }
    func households() async throws -> [Household] { households }

    func createHousehold(name: String, iconEmoji: String) async throws -> Household {
        let h = Household(
            id: Household.newZoneName(),
            name: name,
            iconEmoji: iconEmoji,
            createdByUserID: userID
        )
        households.append(h)
        members[h.id] = [
            Membership(householdID: h.id, userID: userID, displayName: "Me", role: .owner)
        ]
        return h
    }

    func update(_ household: Household) async throws {
        if let idx = households.firstIndex(where: { $0.id == household.id }) {
            households[idx] = household
        }
    }

    func deleteHousehold(_ id: Household.ID) async throws {
        households.removeAll { $0.id == id }
        members.removeValue(forKey: id)
        resultsByDay.removeValue(forKey: id)
    }

    func shareURL(for household: Household) async throws -> URL {
        URL(string: "https://www.icloud.com/share/fake-\(household.id)")!
    }

    func members(in householdID: Household.ID) async throws -> [Membership] {
        members[householdID] ?? []
    }

    func submit(_ result: PuzzleResult) async throws {
        resultsByDay[result.householdID, default: [:]][result.puzzleDay, default: []].append(result)
    }

    func results(in householdID: Household.ID, on day: PuzzleDay) async throws -> [PuzzleResult] {
        resultsByDay[householdID]?[day] ?? []
    }

    func recentResults(in householdID: Household.ID, since day: PuzzleDay) async throws -> [PuzzleResult] {
        let allDays = resultsByDay[householdID] ?? [:]
        return allDays.flatMap { d, results in d >= day ? results : [] }
    }

    func react(to resultID: PuzzleResult.ID, in householdID: Household.ID, emoji: String) async throws {
        reactions.append(Reaction(targetResultID: resultID, authorUserID: userID, emoji: emoji))
    }
}

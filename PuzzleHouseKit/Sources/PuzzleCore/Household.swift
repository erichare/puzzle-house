import Foundation

public struct Household: Hashable, Sendable, Codable, Identifiable {
    public typealias ID = String

    public let id: ID                // zone name: "household-<uuid>"
    public var name: String
    public var iconEmoji: String
    public var timeZoneIdentifier: String
    public var createdByUserID: String
    public var createdAt: Date

    public init(
        id: ID,
        name: String,
        iconEmoji: String = "🏠",
        timeZoneIdentifier: String = TimeZone.current.identifier,
        createdByUserID: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.iconEmoji = iconEmoji
        self.timeZoneIdentifier = timeZoneIdentifier
        self.createdByUserID = createdByUserID
        self.createdAt = createdAt
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }
}

public extension Household {
    static func newZoneName() -> Household.ID {
        "household-\(UUID().uuidString.lowercased())"
    }
}

import Foundation

/// A user's presence in a particular household. `displayName` is
/// household-scoped — you might be "Eric" in your friends' house and "Son" in
/// the family house.
public struct Membership: Hashable, Sendable, Codable, Identifiable {
    public typealias ID = String

    public let id: ID
    public let householdID: Household.ID
    public let userID: String
    public var displayName: String
    public var avatarEmoji: String
    /// Optional PNG bytes for a custom avatar photo. Capped to ~256×256 by
    /// the editor flow so it fits inside CloudKit's record size budget.
    /// Nil means "use `avatarEmoji` instead".
    public var avatarPhotoData: Data?
    public var role: Role
    public let joinedAt: Date

    public enum Role: String, Hashable, Sendable, Codable {
        case owner
        case member
    }

    public init(
        id: ID = UUID().uuidString,
        householdID: Household.ID,
        userID: String,
        displayName: String,
        avatarEmoji: String = "🧩",
        avatarPhotoData: Data? = nil,
        role: Role = .member,
        joinedAt: Date = Date()
    ) {
        self.id = id
        self.householdID = householdID
        self.userID = userID
        self.displayName = displayName
        self.avatarEmoji = avatarEmoji
        self.avatarPhotoData = avatarPhotoData
        self.role = role
        self.joinedAt = joinedAt
    }
}

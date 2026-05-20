import Foundation

/// A user identified by their CloudKit user record. Stored in the private DB.
/// `displayName` here is the user's own default; per-household display names
/// live on `Membership`.
public struct User: Hashable, Sendable, Codable, Identifiable {
    public let id: String           // CKRecord.ID.recordName
    public var displayName: String
    public var avatarEmoji: String
    public var defaultHouseholdID: Household.ID?
    public var preferences: UserPreferences

    public init(
        id: String,
        displayName: String,
        avatarEmoji: String = "🧩",
        defaultHouseholdID: Household.ID? = nil,
        preferences: UserPreferences = .init()
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarEmoji = avatarEmoji
        self.defaultHouseholdID = defaultHouseholdID
        self.preferences = preferences
    }
}

public struct UserPreferences: Hashable, Sendable, Codable {
    public var hideSpoilersUntilSolved: Bool
    public var notifySolvedBeforeYou: Bool
    public var notifyDailyReminder: Bool
    public var notifyHouseholdChampion: Bool
    public var notifyWeeklyRecap: Bool
    public var preferredReminderTime: ReminderTime

    public init(
        hideSpoilersUntilSolved: Bool = true,
        notifySolvedBeforeYou: Bool = true,
        notifyDailyReminder: Bool = true,
        notifyHouseholdChampion: Bool = true,
        notifyWeeklyRecap: Bool = true,
        preferredReminderTime: ReminderTime = .auto
    ) {
        self.hideSpoilersUntilSolved = hideSpoilersUntilSolved
        self.notifySolvedBeforeYou = notifySolvedBeforeYou
        self.notifyDailyReminder = notifyDailyReminder
        self.notifyHouseholdChampion = notifyHouseholdChampion
        self.notifyWeeklyRecap = notifyWeeklyRecap
        self.preferredReminderTime = preferredReminderTime
    }
}

public enum ReminderTime: Hashable, Sendable, Codable {
    case auto                       // derived from rolling 7-day median submit time
    case fixed(hour: Int, minute: Int)
}

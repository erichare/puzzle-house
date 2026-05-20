import Foundation
import UserNotifications
import PuzzleCore

public protocol NotificationServicing: Sendable {
    func requestAuthorization() async throws -> Bool
    func currentAuthorizationStatus() async -> AuthorizationStatus

    func scheduleDailyReminder(hour: Int, minute: Int) async throws
    func scheduleWeeklyRecap(weekday: Int, hour: Int) async throws
    func scheduleOneShot(identifier: String, title: String, body: String) async

    func cancelAll() async
    func cancel(identifier: NotificationIdentifier) async
}

public enum AuthorizationStatus: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
}

public enum NotificationIdentifier: String, Sendable {
    case dailyReminder = "puzzle-house.daily-reminder"
    case weeklyRecap = "puzzle-house.weekly-recap"
}

public final class NotificationService: NotificationServicing, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    public func currentAuthorizationStatus() async -> AuthorizationStatus {
        let settings = await center.notificationSettings()
        return Self.map(settings.authorizationStatus)
    }

    public func scheduleDailyReminder(hour: Int, minute: Int) async throws {
        await cancel(identifier: .dailyReminder)
        let content = UNMutableNotificationContent()
        content.title = "Puzzles waiting"
        content.body = "Mom or Dad might have already played \u{1F440}"
        content.sound = .default

        var date = DateComponents()
        date.hour = hour
        date.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let request = UNNotificationRequest(
            identifier: NotificationIdentifier.dailyReminder.rawValue,
            content: content,
            trigger: trigger
        )
        try await center.add(request)
    }

    public func scheduleWeeklyRecap(weekday: Int, hour: Int) async throws {
        await cancel(identifier: .weeklyRecap)
        let content = UNMutableNotificationContent()
        content.title = "Your week in puzzles"
        content.body = "See who won the most days, longest streak, biggest comeback."
        content.sound = .default

        var date = DateComponents()
        date.weekday = weekday      // 1 = Sunday, 7 = Saturday
        date.hour = hour
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let request = UNNotificationRequest(
            identifier: NotificationIdentifier.weeklyRecap.rawValue,
            content: content,
            trigger: trigger
        )
        try await center.add(request)
    }

    public func scheduleOneShot(identifier: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // Fire as soon as iOS allows — ~1 s delay is enough to land while
        // the user is still in the app.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    public func cancelAll() async {
        center.removeAllPendingNotificationRequests()
    }

    public func cancel(identifier: NotificationIdentifier) async {
        center.removePendingNotificationRequests(withIdentifiers: [identifier.rawValue])
    }

    private static func map(_ status: UNAuthorizationStatus) -> AuthorizationStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .notDetermined
        }
    }
}

// MARK: - Scheduling policy

/// Pure logic for deciding what to schedule based on user preferences and a
/// rolling history of submit times. Lives separately so it's trivially
/// testable without touching UNUserNotificationCenter.
public enum NotificationPolicy {
    /// Default daily reminder time when no submit history is available yet.
    public static let fallbackReminderHour = 9
    public static let fallbackReminderMinute = 0

    /// Sunday at 19:00 local — when weekly recap fires.
    public static let weeklyRecapWeekday = 1   // 1 = Sunday in iOS / Gregorian
    public static let weeklyRecapHour = 19

    /// Picks a reminder hour/minute based on the user's rolling submit times.
    /// Returns the fallback when there's no data or when prefs say "fixed".
    public static func reminderTime(
        preference: ReminderTime,
        recentSubmissions: [Date],
        in timeZone: TimeZone = .current
    ) -> (hour: Int, minute: Int) {
        switch preference {
        case .fixed(let hour, let minute):
            return (hour, minute)
        case .auto:
            guard !recentSubmissions.isEmpty else {
                return (fallbackReminderHour, fallbackReminderMinute)
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let minutes = recentSubmissions.map { date -> Int in
                let c = calendar.dateComponents([.hour, .minute], from: date)
                return (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }.sorted()
            let median = minutes[minutes.count / 2]
            return (median / 60, median % 60)
        }
    }
}

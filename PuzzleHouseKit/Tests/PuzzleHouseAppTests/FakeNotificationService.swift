import Foundation
@testable import PuzzleHouseApp

final class FakeNotificationService: NotificationServicing, @unchecked Sendable {
    var status: AuthorizationStatus = .notDetermined
    var grantOnRequest: Bool = true

    private(set) var scheduledReminder: (hour: Int, minute: Int)?
    private(set) var scheduledWeekly: (weekday: Int, hour: Int)?
    private(set) var cancelAllCount = 0
    private(set) var cancelledIDs: [NotificationIdentifier] = []

    func requestAuthorization() async throws -> Bool {
        status = grantOnRequest ? .authorized : .denied
        return grantOnRequest
    }
    func currentAuthorizationStatus() async -> AuthorizationStatus { status }

    func scheduleDailyReminder(hour: Int, minute: Int) async throws {
        scheduledReminder = (hour, minute)
    }
    func scheduleWeeklyRecap(weekday: Int, hour: Int) async throws {
        scheduledWeekly = (weekday, hour)
    }
    func scheduleOneShot(identifier: String, title: String, body: String) async {
        // No-op for tests; we don't actually deliver notifications.
    }
    func cancelAll() async {
        cancelAllCount += 1
        scheduledReminder = nil
        scheduledWeekly = nil
    }
    func cancel(identifier: NotificationIdentifier) async {
        cancelledIDs.append(identifier)
    }
}

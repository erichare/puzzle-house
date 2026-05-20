import Foundation
import Observation
import PuzzleCore
import PuzzleCloudKit
import PuzzleParsers
import PuzzleScoring

/// Observable application state. Holds the current user, the list of
/// households the user belongs to, the active household, today's results, and
/// a 14-day rolling window used for streak math.
@MainActor
@Observable
public final class HouseholdStore {
    public enum BootstrapState: Sendable, Equatable {
        case idle
        case loading
        case ready
        case error(String)
    }

    public private(set) var state: BootstrapState = .idle
    public private(set) var currentUserID: String?
    public private(set) var households: [Household] = []
    public private(set) var selectedHouseholdID: Household.ID?
    public private(set) var members: [Membership] = []
    public private(set) var today: PuzzleDay
    public private(set) var todayResults: [PuzzleResult] = []
    public private(set) var recentResults: [PuzzleResult] = []
    public private(set) var notificationStatus: AuthorizationStatus = .notDetermined
    public var preferences: UserPreferences

    /// How many days of history to keep loaded for streak math.
    public static let streakWindowDays = 14

    private let service: any CloudKitServicing
    private let queue: OfflineWriteQueue?
    private let notifications: any NotificationServicing
    private let clock: @Sendable () -> Date

    public init(
        service: any CloudKitServicing,
        queue: OfflineWriteQueue? = nil,
        notifications: any NotificationServicing = NotificationService(),
        preferences: UserPreferences = .init(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.service = service
        self.queue = queue
        self.notifications = notifications
        self.preferences = preferences
        self.clock = now
        self.today = PuzzleDay(date: now(), timeZone: .current)
    }

    // MARK: - Derived

    public var selectedHousehold: Household? {
        guard let id = selectedHouseholdID else { return nil }
        return households.first(where: { $0.id == id })
    }

    public var spoilerMap: [PuzzleResult.ID: SpoilerVisibility] {
        guard let uid = currentUserID else { return [:] }
        return SpoilerPolicy.visibilities(
            for: todayResults,
            viewerUserID: uid,
            viewerPreferences: preferences
        )
    }

    public var leaderboard: [PlayerDailyScore] {
        CombinedScore.leaderboard(todayResults, day: today)
    }

    public var houseStreak: Int {
        StreakCalculator.houseStreak(
            results: recentResults,
            memberUserIDs: members.map(\.userID),
            today: today
        )
    }

    public func gameStreak(userID: String, gameID: String) -> Int {
        StreakCalculator.gameStreak(
            results: recentResults,
            gameID: gameID,
            userID: userID,
            today: today
        )
    }

    public func displayName(for userID: String) -> String {
        members.first(where: { $0.userID == userID })?.displayName ?? "Someone"
    }

    public func avatarEmoji(for userID: String) -> String {
        members.first(where: { $0.userID == userID })?.avatarEmoji ?? "🧩"
    }

    // MARK: - Bootstrap

    public func bootstrap() async {
        state = .loading
        do {
            self.currentUserID = try await service.currentUserRecordName()
            self.households = try await service.households()
            self.selectedHouseholdID = households.first?.id
            if let id = selectedHouseholdID {
                await loadHousehold(id)
                await drainPendingResults()   // catch up on Share-Ext submissions
            }
            notificationStatus = await notifications.currentAuthorizationStatus()
            if notificationStatus == .authorized {
                await rescheduleNotifications()
            }
            state = .ready
        } catch {
            state = .error(String(describing: error))
        }
    }

    // MARK: - Notifications

    public func requestNotificationPermission() async {
        if let granted = try? await notifications.requestAuthorization() {
            notificationStatus = granted ? .authorized : .denied
            if granted { await rescheduleNotifications() }
        }
    }

    /// Wipes the offline write queue. Returns the number of items dropped so
    /// the UI can report it. Doesn't touch CloudKit — for that, delete the
    /// household in the Houses tab.
    @discardableResult
    public func clearLocalData() -> Int {
        guard let queue else { return 0 }
        let dropped = (try? queue.count()) ?? 0
        for r in (try? queue.pending()) ?? [] { queue.remove(r.id) }
        return dropped
    }

    public func rescheduleNotifications() async {
        // Clear everything first; we re-add based on current prefs.
        await notifications.cancelAll()
        if preferences.notifyDailyReminder {
            let mySubmissions = recentResults
                .filter { $0.authorUserID == currentUserID }
                .map(\.submittedAt)
            let timeZone = selectedHousehold?.timeZone ?? .current
            let (hour, minute) = NotificationPolicy.reminderTime(
                preference: preferences.preferredReminderTime,
                recentSubmissions: mySubmissions,
                in: timeZone
            )
            try? await notifications.scheduleDailyReminder(hour: hour, minute: minute)
        }
        if preferences.notifyWeeklyRecap {
            try? await notifications.scheduleWeeklyRecap(
                weekday: NotificationPolicy.weeklyRecapWeekday,
                hour: NotificationPolicy.weeklyRecapHour
            )
        }
    }

    public func switchHousehold(_ id: Household.ID) async {
        selectedHouseholdID = id
        await loadHousehold(id)
    }

    public func refresh() async {
        guard let id = selectedHouseholdID else { return }
        await loadHousehold(id)
    }

    /// Called from the app entry point on `scenePhase` → `.active` and after
    /// successful submits. Idempotent; safe to call repeatedly.
    public func drainPendingResults() async {
        guard let queue,
              let householdID = selectedHouseholdID,
              let uid = currentUserID,
              let household = selectedHousehold
        else { return }

        let pending = (try? queue.pending()) ?? []
        guard !pending.isEmpty else { return }

        for placeholder in pending {
            let deterministicID = PuzzleResult.deterministicID(
                authorUserID: uid,
                gameID: placeholder.gameID,
                puzzleNumber: placeholder.puzzleNumber
            )
            let real = PuzzleResult(
                id: deterministicID,
                householdID: householdID,
                authorUserID: uid,
                gameID: placeholder.gameID,
                puzzleNumber: placeholder.puzzleNumber,
                puzzleDay: PuzzleDay(date: placeholder.submittedAt, timeZone: household.timeZone),
                rawScore: placeholder.rawScore,
                rawPayload: placeholder.rawPayload,
                gridData: placeholder.gridData,
                submittedAt: placeholder.submittedAt
            )
            do {
                try await service.submit(real)
                queue.remove(placeholder.id)
            } catch {
                // Leave in queue; we'll try again next time. Don't fail the whole drain.
                continue
            }
        }
        await refresh()
    }

    private func loadHousehold(_ id: Household.ID) async {
        let now = clock()
        let timeZone = households.first(where: { $0.id == id })?.timeZone ?? .current
        today = PuzzleDay(date: now, timeZone: timeZone)
        let windowStart = today.advanced(by: -Self.streakWindowDays)

        async let m = try service.members(in: id)
        async let r = try service.results(in: id, on: today)
        async let recent = try service.recentResults(in: id, since: windowStart)
        do {
            members = try await m
            todayResults = Self.dedupe(try await r)
            recentResults = Self.dedupe(try await recent)
        } catch {
            state = .error(String(describing: error))
        }
    }

    /// Collapse duplicate (user, game, puzzleNumber, day) tuples — defends
    /// against any stray pre-deterministic-ID records still sitting in the
    /// shared zone. Keeps the most recently submitted entry.
    static func dedupe(_ results: [PuzzleResult]) -> [PuzzleResult] {
        let sorted = results.sorted { $0.submittedAt < $1.submittedAt }
        var byKey: [String: PuzzleResult] = [:]
        for r in sorted {
            let key = "\(r.authorUserID)|\(r.gameID)|\(r.puzzleNumber)|\(r.puzzleDay.epoch)"
            byKey[key] = r        // later overwrites earlier
        }
        return Array(byKey.values).sorted { $0.submittedAt < $1.submittedAt }
    }

    // MARK: - Mutations

    public func createHousehold(name: String, iconEmoji: String) async throws {
        let new = try await service.createHousehold(name: name, iconEmoji: iconEmoji)
        households.append(new)
        await switchHousehold(new.id)
    }

    public func renameHousehold(_ household: Household, name: String, iconEmoji: String) async throws {
        var updated = household
        updated.name = name
        updated.iconEmoji = iconEmoji
        try await service.update(updated)
        if let idx = households.firstIndex(where: { $0.id == household.id }) {
            households[idx] = updated
        }
    }

    public func deleteHousehold(_ household: Household) async throws {
        try await service.deleteHousehold(household.id)
        households.removeAll { $0.id == household.id }
        if selectedHouseholdID == household.id {
            selectedHouseholdID = households.first?.id
            if let id = selectedHouseholdID { await loadHousehold(id) }
            else {
                members = []
                todayResults = []
                recentResults = []
            }
        }
    }

    public func inviteURL(for household: Household) async throws -> URL {
        try await service.shareURL(for: household)
    }

    public func submit(parsed: ParsedResult, rawPayload: String) async throws {
        guard let householdID = selectedHouseholdID,
              let uid = currentUserID,
              let household = selectedHousehold
        else { return }
        let result = PuzzleResult(
            parsed: parsed,
            householdID: householdID,
            authorUserID: uid,
            rawPayload: rawPayload,
            timeZone: household.timeZone,
            submittedAt: clock()
        )
        try await service.submit(result)
        await refresh()
    }

    public func react(to resultID: PuzzleResult.ID, emoji: String) async throws {
        guard let householdID = selectedHouseholdID else { return }
        try await service.react(to: resultID, in: householdID, emoji: emoji)
    }
}

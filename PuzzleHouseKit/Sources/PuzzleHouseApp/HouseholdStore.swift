import Foundation
import Observation
import CloudKit
#if canImport(WidgetKit)
import WidgetKit
#endif
import PuzzleCore
import PuzzleCloudKit
import PuzzleParsers
import PuzzleScoring

/// Observable application state. Holds the current user, the list of
/// households the user belongs to, the active household, today's results, and
/// a 14-day rolling window used for streak math.
/// Process-wide accessor so the `AppDelegate` (which exists outside the
/// SwiftUI hierarchy) can route incoming silent pushes to whichever store
/// the app set up at launch. Set once during `PuzzleHouseAppEntry.init`.
@MainActor
public enum PuzzleHouseSharedStore {
    public static var current: HouseholdStore?
    /// Share metadata delivered before the store was ready — typically a cold
    /// launch from tapping an invite link, where the scene connects before
    /// `bootstrap()` finishes. Drained by `drainPendingShareIfNeeded()`.
    public static var pendingShareMetadata: CKShare.Metadata?
}

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
    public private(set) var reactions: [Reaction] = []
    public private(set) var notificationStatus: AuthorizationStatus = .notDetermined
    public private(set) var lastDrainError: String?
    public private(set) var lastDrainCount: Int = 0
    /// True while we're in the middle of swapping to / refreshing a household.
    /// Driven by `loadHousehold` so UI can show a spinner.
    public private(set) var isLoadingHousehold: Bool = false
    /// True while we're accepting an incoming invite and waiting for the
    /// shared house to replicate into our account. Drives the "Joining…" UI.
    public private(set) var isJoining: Bool = false
    public var preferences: UserPreferences

    /// How many days of history to keep loaded for streak math.
    public static let streakWindowDays = 14

    private let service: any CloudKitServicing
    private let queue: OfflineWriteQueue?
    private let notifications: any NotificationServicing
    private let widgetStore: WidgetSnapshotStore?
    private let clock: @Sendable () -> Date

    public init(
        service: any CloudKitServicing,
        queue: OfflineWriteQueue? = nil,
        notifications: any NotificationServicing = NotificationService(),
        widgetStore: WidgetSnapshotStore? = nil,
        preferences: UserPreferences = .init(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.service = service
        self.queue = queue
        self.notifications = notifications
        self.widgetStore = widgetStore
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

    public func avatarPhotoData(for userID: String) -> Data? {
        members.first(where: { $0.userID == userID })?.avatarPhotoData
    }

    // MARK: - Bootstrap

    public func bootstrap() async {
        state = .loading
        do {
            self.currentUserID = try await service.currentUserRecordName()
            self.households = try await service.households()
            // Subscribe for silent pushes so other members' changes refresh us.
            await service.ensureSyncSubscriptions()
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

    /// How many submissions are currently waiting in the offline queue. The
    /// Settings → Diagnostics screen reads this; the Share Extension drops
    /// entries here when it can't reach iCloud directly.
    public func pendingQueueCount() -> Int {
        (try? queue?.count()) ?? 0
    }

    /// Called from the app entry point on `scenePhase` → `.active` and after
    /// successful submits. Idempotent; safe to call repeatedly. Records the
    /// last drain count + any error so the Diagnostics view can show what
    /// happened.
    public func drainPendingResults() async {
        guard let queue else {
            lastDrainError = "No App Group container available — drain skipped."
            return
        }
        guard let householdID = selectedHouseholdID,
              let uid = currentUserID,
              let household = selectedHousehold
        else {
            lastDrainError = "No household selected yet — drain skipped."
            return
        }

        let pending = (try? queue.pending()) ?? []
        guard !pending.isEmpty else {
            lastDrainCount = 0
            lastDrainError = nil
            return
        }

        var submitted = 0
        var firstError: String?
        for placeholder in pending {
            let deterministicID = PuzzleResult.deterministicID(
                authorUserID: uid,
                gameID: placeholder.gameID,
                puzzleNumber: placeholder.puzzleNumber
            )
            // The Share Extension computed `puzzleDay` at share time using
            // the user's then-current time zone; respect that rather than
            // re-deriving from submittedAt (which would jump to a new day
            // if the user crossed midnight between sharing and the drain
            // running). `household` is kept in the guard above so we can
            // still surface it as an error if it disappears, but we don't
            // need its time zone here.
            _ = household
            let real = PuzzleResult(
                id: deterministicID,
                householdID: householdID,
                authorUserID: uid,
                gameID: placeholder.gameID,
                puzzleNumber: placeholder.puzzleNumber,
                puzzleDay: placeholder.puzzleDay,
                rawScore: placeholder.rawScore,
                rawPayload: placeholder.rawPayload,
                gridData: placeholder.gridData,
                submittedAt: placeholder.submittedAt
            )
            do {
                try await service.submit(real)
                queue.remove(placeholder.id)
                insertOptimistically(real)
                submitted += 1
            } catch {
                if firstError == nil {
                    firstError = String(describing: error)
                }
                continue
            }
        }
        lastDrainCount = submitted
        lastDrainError = firstError
        if submitted > 0 {
            await refresh()
        }
    }

    private func loadHousehold(_ id: Household.ID) async {
        isLoadingHousehold = true
        defer { isLoadingHousehold = false }

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
            return
        }
        // Self-heal: if we belong to this house but have no membership record
        // yet (joined before membership-on-join shipped, or the accept-time
        // write lost a race with zone replication), create one now so we show
        // up in everyone's roster — then reflect it locally.
        if let uid = currentUserID, !members.contains(where: { $0.userID == uid }) {
            if (try? await service.ensureMembership(in: id)) != nil {
                members = (try? await service.members(in: id)) ?? members
            }
        }
        // Reactions are optional. If the Reaction record type isn't indexed in
        // CloudKit yet (typical on a fresh container), or any other error
        // happens, just show an empty list rather than failing the whole load.
        reactions = (try? await service.reactions(in: id, since: windowStart)) ?? []
        writeWidgetSnapshot()
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private func writeWidgetSnapshot() {
        guard let widgetStore, let household = selectedHousehold else { return }
        let entries = leaderboard.map { score in
            WidgetSnapshot.Entry(
                userID: score.userID,
                displayName: displayName(for: score.userID),
                avatarEmoji: avatarEmoji(for: score.userID),
                combinedScore: score.combined,
                gamesPlayed: score.perGame.count
            )
        }
        let snap = WidgetSnapshot(
            updatedAt: clock(),
            householdName: household.name,
            householdIcon: household.iconEmoji,
            dayISO: today.isoString,
            houseStreak: houseStreak,
            entries: entries
        )
        widgetStore.write(snap)
    }

    public func reactions(for resultID: PuzzleResult.ID) -> [Reaction] {
        reactions.filter { $0.targetResultID == resultID }
    }

    public func reactionSummary(for resultID: PuzzleResult.ID) -> [(emoji: String, count: Int)] {
        let r = reactions(for: resultID)
        let grouped = Dictionary(grouping: r, by: \.emoji)
        return grouped.map { ($0.key, $0.value.count) }
            .sorted { $0.count > $1.count }
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

    /// Called by the AppDelegate when iOS hands us a CKShare metadata after
    /// the recipient taps a share URL. Accepts the share, refreshes the
    /// household list so the new entry shows up in the Houses tab, and
    /// switches to it.
    public func acceptIncomingShare(_ metadata: CKShare.Metadata) async {
        isJoining = true
        defer { isJoining = false }
        do {
            let id = try await service.acceptShare(metadata)
            // The shared zone may still be replicating into our account. Poll
            // briefly for the house to surface in our list before switching, so
            // we don't land on an empty screen the first time.
            for attempt in 0..<6 {
                let all = (try? await service.households()) ?? households
                households = all
                if all.contains(where: { $0.id == id }) { break }
                if attempt < 5 { try? await Task.sleep(for: .milliseconds(700)) }
            }
            // Switch regardless — `loadHousehold` retries zone resolution and
            // its backfill writes our membership so we appear in the roster.
            await switchHousehold(id)
        } catch {
            state = .error(friendlyShareError(error))
        }
    }

    /// Accept an invite that arrived before we were ready (cold launch). Safe
    /// to call repeatedly; it no-ops until we're bootstrapped and only runs
    /// once per stashed invite. Call after `bootstrap()`.
    public func drainPendingShareIfNeeded() async {
        guard currentUserID != nil else { return }   // wait until bootstrapped
        guard let metadata = PuzzleHouseSharedStore.pendingShareMetadata else { return }
        PuzzleHouseSharedStore.pendingShareMetadata = nil
        await acceptIncomingShare(metadata)
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
        insertOptimistically(result)
        await refresh()
    }

    /// Insert a freshly-submitted result into the in-memory lists so the UI
    /// updates immediately, without waiting for the CloudKit roundtrip.
    /// Dedupe in `loadHousehold` handles any duplicate that comes back from
    /// the subsequent refresh.
    private func insertOptimistically(_ result: PuzzleResult) {
        if result.puzzleDay == today {
            todayResults = Self.dedupe(todayResults + [result])
        }
        let windowStart = today.advanced(by: -Self.streakWindowDays)
        if result.puzzleDay >= windowStart {
            recentResults = Self.dedupe(recentResults + [result])
        }
        writeWidgetSnapshot()
    }

    public func deleteResult(_ result: PuzzleResult) async throws {
        guard let householdID = selectedHouseholdID else { return }
        try await service.deleteResult(result.id, in: householdID)
        todayResults.removeAll { $0.id == result.id }
        recentResults.removeAll { $0.id == result.id }
    }

    public func react(to resultID: PuzzleResult.ID, emoji: String) async throws {
        guard let householdID = selectedHouseholdID, let uid = currentUserID else { return }
        try await service.react(to: resultID, in: householdID, emoji: emoji)
        // Optimistic local update: replace any existing reaction by the same
        // user on the same result so the UI reflects "one reaction per
        // person" immediately.
        reactions.removeAll { $0.targetResultID == resultID && $0.authorUserID == uid }
        let id = Reaction.deterministicID(targetResultID: resultID, authorUserID: uid)
        reactions.append(Reaction(id: id, targetResultID: resultID, authorUserID: uid, emoji: emoji))
    }

    public func clearMyReaction(on resultID: PuzzleResult.ID) async throws {
        guard let householdID = selectedHouseholdID, let uid = currentUserID else { return }
        try await service.clearReaction(to: resultID, in: householdID)
        reactions.removeAll { $0.targetResultID == resultID && $0.authorUserID == uid }
    }

    public func myReaction(for resultID: PuzzleResult.ID) -> String? {
        guard let uid = currentUserID else { return nil }
        return reactions.first { $0.targetResultID == resultID && $0.authorUserID == uid }?.emoji
    }

    // MARK: - Remote notification handling

    /// Called by the AppDelegate when a CloudKit silent push arrives. Refresh
    /// data, then run two derived-state checks: "Mom solved before you" and
    /// "Today's champion is decided".
    public func handleRemoteCloudKitNotification() async {
        await refresh()
        await runSolvedBeforeYouCheck()
        await runChampionCheck()
    }

    /// Fires a local notification the first time, per (household, game, day),
    /// that another member submits a result the viewer hasn't matched yet.
    private func runSolvedBeforeYouCheck() async {
        guard preferences.notifySolvedBeforeYou,
              let uid = currentUserID,
              let householdID = selectedHouseholdID
        else { return }
        let myToday = Set(
            todayResults.filter { $0.authorUserID == uid }
                .map { "\($0.gameID)|\($0.puzzleNumber)" }
        )
        for result in todayResults where result.authorUserID != uid {
            let key = "\(result.gameID)|\(result.puzzleNumber)"
            if myToday.contains(key) { continue }
            let dedupeKey = "solved-before-you|\(householdID)|\(key)|\(result.authorUserID)"
            if recentlyFired(dedupeKey) { continue }
            let body = "\(displayName(for: result.authorUserID)) just submitted \(Game.known(by: result.gameID)?.displayName ?? result.gameID) — your turn."
            await notifications.scheduleOneShot(
                identifier: dedupeKey,
                title: "Solved before you",
                body: body
            )
            markFired(dedupeKey)
        }
    }

    /// Fires a "today's champion" notification once per (household, day),
    /// when everyone in the active set has at least one submission today.
    private func runChampionCheck() async {
        guard preferences.notifyHouseholdChampion,
              let householdID = selectedHouseholdID
        else { return }
        let active = StreakCalculator.activeMembers(
            results: recentResults,
            memberUserIDs: members.map(\.userID),
            today: today
        )
        guard !active.isEmpty else { return }
        let playedToday = Set(todayResults.map(\.authorUserID))
        guard active.isSubset(of: playedToday) else { return }
        guard let champion = leaderboard.first else { return }
        let dedupeKey = "champion|\(householdID)|\(today.isoString)"
        if recentlyFired(dedupeKey) { return }
        let body = "🏆 \(displayName(for: champion.userID)) takes the crown — everyone's played."
        await notifications.scheduleOneShot(
            identifier: dedupeKey,
            title: "Today's house champion",
            body: body
        )
        markFired(dedupeKey)
    }

    // MARK: - Per-day notification dedupe

    /// `UserDefaults`-backed sentinel so we don't re-fire the same alert.
    private func recentlyFired(_ key: String) -> Bool {
        UserDefaults.standard.string(forKey: "puzzle-house.fired.\(key)") == today.isoString
    }
    private func markFired(_ key: String) {
        UserDefaults.standard.set(today.isoString, forKey: "puzzle-house.fired.\(key)")
    }

    public func updateMyMembership(
        displayName: String,
        avatarEmoji: String,
        avatarPhotoData: Data?
    ) async throws {
        guard let uid = currentUserID,
              let existing = members.first(where: { $0.userID == uid })
        else { return }
        var updated = existing
        updated.displayName = displayName
        updated.avatarEmoji = avatarEmoji
        updated.avatarPhotoData = avatarPhotoData
        try await service.updateMembership(updated)
        // Reassign the entire array so the @Observable registrar definitely
        // fires for any view tracking `members` (including ones that look up
        // a member via `members.first(where:)` rather than indexing).
        members = members.map { $0.userID == uid ? updated : $0 }
    }

    public func isOwner(of household: Household) -> Bool {
        household.createdByUserID == currentUserID
    }

    /// Owner action: remove someone else from the current house. Drops them as
    /// a CKShare participant and deletes their membership record.
    public func removeMember(_ membership: Membership) async throws {
        guard let householdID = selectedHouseholdID else { return }
        try await service.removeMember(userID: membership.userID, from: householdID)
        members = members.filter { $0.userID != membership.userID }
    }

    /// Leave a shared house (or delete it if you're the owner). Mirrors the
    /// Houses-tab swipe action; exposed by name for the Manage Members screen.
    public func leaveHousehold(_ household: Household) async throws {
        try await deleteHousehold(household)
    }

    /// Maps the common CloudKit sharing failures to copy a person can act on,
    /// instead of dumping a raw `CKError`.
    private func friendlyShareError(_ error: Error) -> String {
        if let ck = error as? CKError {
            switch ck.code {
            case .notAuthenticated:
                return "You need to be signed in to iCloud to join a house. Open Settings, tap your name, turn on iCloud, then tap the link again."
            case .networkUnavailable, .networkFailure:
                return "No internet connection. Reconnect, then tap the invite link again."
            case .serviceUnavailable, .requestRateLimited, .zoneBusy, .serverResponseLost:
                return "iCloud is busy right now. Give it a moment, then tap the invite link again."
            default:
                break
            }
        }
        return "We couldn't open that invite. Make sure you're signed in to iCloud, then tap the link again."
    }
}

import Foundation
import Observation
import Supabase
import LearningCore

/// `profiles` columns written by the app (never the e-mail address).
private struct ProfilePatch: Encodable, Sendable {
    var displayName: String?
    var notificationPrefs: NotificationPreferences

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case notificationPrefs = "notification_prefs"
    }
}

private struct ProfileRow: Decodable, Sendable {
    var displayName: String?
    var notificationPrefs: NotificationPreferences?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case notificationPrefs = "notification_prefs"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        notificationPrefs = try? c.decodeIfPresent(NotificationPreferences.self, forKey: .notificationPrefs)
    }
}

/// PostgREST calls, kept off the main actor: the SDK's `PostgrestResponse` is not `Sendable`, so it cannot be
/// returned to `SyncService` (main actor). These helpers only hand back `Sendable` values.
private enum Remote {
    static func upsert<Row: Encodable & Sendable>(_ client: SupabaseClient, table: String, row: Row,
                                                  onConflict: String) async throws {
        try await client.from(table).upsert(row, onConflict: onConflict).execute()
    }

    static func updateProfile(_ client: SupabaseClient, patch: ProfilePatch, userId: String) async throws {
        try await client.from("profiles").update(patch).eq("id", value: userId).execute()
    }

    static func profile(_ client: SupabaseClient, userId: String) async throws -> ProfileRow {
        try await client.from("profiles").select().eq("id", value: userId).single().execute().value
    }

    static func rpc<Params: Encodable & Sendable, Response: Decodable & Sendable>(
        _ client: SupabaseClient, _ function: String, params: Params
    ) async throws -> Response {
        try await client.rpc(function, params: params).execute().value
    }
}

/// Local-first synchronisation with Supabase: push dirty rows (`sync_push`), pull changes since the stored
/// server cursor (`sync_pull`), merge (newer `updated_at` wins; attempts immutable except a pending result).
/// Idempotent (client-generated UUIDs), retried with exponential backoff, restarted on connectivity changes.
@MainActor
@Observable
final class SyncService {
    enum Reason: String, Sendable {
        case launch, foreground, sessionCompleted, connectivity, manual, retry, settings, restore
    }

    private enum Outcome { case done, skipped, failed }

    private(set) var isSyncing = false
    private(set) var lastSyncAt: Date?
    private(set) var lastRunSucceeded = true

    /// Called after server data was merged locally. `scheduleChanged` is true when the schedule came from the server.
    @ObservationIgnored var onDataChanged: (@MainActor (_ scheduleChanged: Bool) async -> Void)?

    private let backend: BackendClient
    private let local: LocalStore
    private let settings: SettingsStore
    private let network: NetworkMonitor
    private let currentUserId: @MainActor () -> String?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var rerunRequested = false
    @ObservationIgnored private var failureCount = 0

    init(backend: BackendClient, local: LocalStore, settings: SettingsStore, network: NetworkMonitor,
         currentUserId: @escaping @MainActor () -> String?) {
        self.backend = backend
        self.local = local
        self.settings = settings
        self.network = network
        self.currentUserId = currentUserId
    }

    // MARK: Triggers

    /// Fire-and-forget: coalesces concurrent requests (one run at a time, one rerun if asked meanwhile).
    func requestSync(_ reason: Reason) {
        guard currentUserId() != nil else { return }
        if runTask != nil {
            rerunRequested = true
            return
        }
        retryTask?.cancel()
        retryTask = nil
        runTask = Task { [weak self] in await self?.runLoop() }
    }

    /// Requests a sync and waits for the end of the run. Returns true when it completed.
    @discardableResult
    func syncNow(_ reason: Reason = .manual) async -> Bool {
        requestSync(reason)
        await runTask?.value
        return lastRunSucceeded
    }

    func cancelAll() {
        runTask?.cancel()
        retryTask?.cancel()
        runTask = nil
        retryTask = nil
        rerunRequested = false
    }

    private func runLoop() async {
        isSyncing = true
        var outcome = Outcome.done
        repeat {
            rerunRequested = false
            outcome = await performSync()
        } while rerunRequested && outcome != .failed
        isSyncing = false
        runTask = nil
        switch outcome {
        case .done:
            failureCount = 0
            lastRunSucceeded = true
            lastSyncAt = Date()
        case .skipped:
            lastRunSucceeded = false
        case .failed:
            failureCount += 1
            lastRunSucceeded = false
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        let exponent = Double(min(max(failureCount, 1), 7) - 1)
        let delay = min(300.0, 5.0 * pow(2.0, exponent))
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.retryTask = nil
            self?.requestSync(.retry)
        }
    }

    // MARK: One run

    private func performSync() async -> Outcome {
        guard let userId = currentUserId(), let client = backend.client else { return .skipped }
        guard network.isOnline else { return .skipped }
        let languageId = settings.profile.languageId
        do {
            try await pushProfileLevel(client: client, userId: userId)
            try await pushDirtyRows(client: client, languageId: languageId)
            let since = local.value(String.self, for: Self.cursorKey(languageId)) ?? SyncCursor.epoch
            try await pull(client: client, languageId: languageId, since: since)
            return .done
        } catch {
            Log.sync.error("sync failed: \(String(describing: type(of: error)), privacy: .public)")
            return .failed
        }
    }

    private static func cursorKey(_ languageId: String) -> String { "sync.cursor.\(languageId)" }

    // MARK: Push

    /// `user_languages`, `daily_schedules` and `profiles` (PostgREST, upserts).
    private func pushProfileLevel(client: SupabaseClient, userId: String) async throws {
        let profile = settings.profile
        if profile.userLanguageDirty, profile.startedAt != nil {
            let row = UserLanguageDTO(profile: profile, userId: userId)
            try await Remote.upsert(client, table: "user_languages", row: row, onConflict: "user_id,language_id")
            settings.updateProfile {
                if $0.userLanguageUpdatedAt == profile.userLanguageUpdatedAt { $0.userLanguageDirty = false }
            }
        }
        let record = settings.record
        if record.scheduleDirty {
            let row = ScheduleDTO(schedule: record.schedule, updatedAt: record.scheduleUpdatedAt, userId: userId)
            try await Remote.upsert(client, table: "daily_schedules", row: row, onConflict: "user_id")
            settings.markScheduleClean(updatedAt: record.scheduleUpdatedAt)
        }
        if settings.profile.profileDirty || record.notificationsDirty {
            let patch = ProfilePatch(displayName: settings.profile.displayName, notificationPrefs: settings.notificationPreferences)
            try await Remote.updateProfile(client, patch: patch, userId: userId)
            settings.markNotificationsAndProfileClean(notificationsUpdatedAt: record.notificationsUpdatedAt)
        }
    }

    private func pushDirtyRows(client: SupabaseClient, languageId: String) async throws {
        for _ in 0..<25 {
            let sessions = local.dirtySessions(limit: 200)
            let attempts = local.dirtyAttempts(limit: 200)
            let states = local.dirtyMemoryStates(limit: 300)
            let vocabulary = local.dirtyVocabulary(limit: 200)
            var payload = SyncPushPayload(languageId: languageId)
            payload.sessions = sessions.map(SessionDTO.init(record:))
            payload.attempts = attempts.map { AttemptDTO(record: $0.value, updatedAt: $0.updatedAt) }
            payload.memoryStates = states.map { MemoryStateDTO(state: $0.value) }
            payload.vocabulary = vocabulary.map(VocabularyDTO.init(record:))
            if payload.isEmpty { return }
            let response: SyncPushResponse = try await Remote.rpc(
                client, "sync_push", params: SyncPushParams(payload: payload))
            // Rejected rows (unknown exercise or unit on the server) are not retried forever: they are marked sent.
            local.markSessionsClean(sessions.map { (id: $0.id, updatedAt: $0.updatedAt) })
            local.markAttemptsClean(attempts.map { (id: $0.value.id, updatedAt: $0.updatedAt) })
            local.markMemoryStatesClean(states.map { (id: $0.value.unitId, updatedAt: $0.updatedAt) })
            local.markVocabularyClean(vocabulary.map { (id: $0.dictionaryItemId, updatedAt: $0.updatedAt) })
            let rejected = response.rejected.values.reduce(0, +)
            if rejected > 0 { Log.sync.notice("sync_push rejected \(rejected) rows") }
        }
    }

    // MARK: Pull & merge

    private func pull(client: SupabaseClient, languageId: String, since: String) async throws {
        let response: SyncPullResponse = try await Remote.rpc(
            client, "sync_pull", params: SyncPullParams(languageId: languageId, since: since))
        let result = merge(response)
        local.setValue(response.serverTime, for: Self.cursorKey(languageId))
        if result.changed || result.scheduleChanged { await onDataChanged?(result.scheduleChanged) }
    }

    private func merge(_ r: SyncPullResponse) -> (changed: Bool, scheduleChanged: Bool) {
        if r.droppedRows > 0 { Log.sync.notice("sync_pull: \(r.droppedRows) rows ignored (undecodable)") }
        var changed = false
        var scheduleChanged = false
        if local.mergeRemoteSessions(r.sessions.compactMap { $0.toRecord() }) > 0 { changed = true }
        if local.mergeRemoteAttempts(r.attempts.compactMap { $0.toRecord() }) > 0 { changed = true }
        if local.mergeRemoteMemoryStates(r.memoryStates.compactMap { $0.toState() }) > 0 { changed = true }
        if local.mergeRemoteVocabulary(r.vocabulary.compactMap { $0.toRecord() }) > 0 { changed = true }
        if let remote = r.userLanguage, mergeUserLanguage(remote) { changed = true }
        if let dto = r.schedule, let schedule = dto.toSchedule() {
            let updatedAt = dto.updatedAt.flatMap(ISODate.date(from:)) ?? .distantPast
            if settings.applyRemoteSchedule(schedule, updatedAt: updatedAt) {
                changed = true
                scheduleChanged = true
            }
        }
        return (changed, scheduleChanged)
    }

    private func mergeUserLanguage(_ remote: UserLanguageDTO) -> Bool {
        let remoteUpdated = remote.updatedAt.flatMap(ISODate.date(from:)) ?? .distantPast
        let profile = settings.profile
        guard remoteUpdated > (profile.userLanguageUpdatedAt ?? .distantPast) else { return false }
        settings.updateProfile {
            $0.estimatedLevel = remote.estimatedLevel ?? $0.estimatedLevel
            $0.startLessonSequence = remote.startLessonSequence ?? $0.startLessonSequence
            $0.placement = remote.placement ?? $0.placement
            $0.startedAt = remote.startedAt.flatMap(ISODate.date(from:)) ?? $0.startedAt
            $0.userLanguageUpdatedAt = remoteUpdated
            $0.userLanguageDirty = false
        }
        return true
    }

    // MARK: Restore on a new iPhone

    /// Full pull from the epoch cursor (+ profile row). Returns true when the account already has a
    /// started language: the onboarding is then considered done.
    func restoreFromServer() async -> Bool {
        await runTask?.value
        guard let userId = currentUserId(), let client = backend.client, network.isOnline else { return false }
        do {
            let row = try await Remote.profile(client, userId: userId)
            if settings.profile.displayName == nil, let name = row.displayName, !name.isEmpty {
                settings.updateProfile { $0.displayName = name }
            }
            if let prefs = row.notificationPrefs { settings.applyRemoteNotificationPreferences(prefs) }
            try await pull(client: client, languageId: settings.profile.languageId, since: SyncCursor.epoch)
            guard settings.profile.startedAt != nil else { return false }
            settings.updateProfile { $0.onboardingCompleted = true }
            return true
        } catch {
            Log.sync.error("restore failed: \(String(describing: type(of: error)), privacy: .public)")
            return false
        }
    }
}

import Foundation
import Observation
import UIKit
import UserNotifications
import LearningCore

// CONTRACT FILE — owned by the "services" workstream (B1).
// Single dependency container, injected at the root with `.environment(appEnvironment)` and read
// in views with `@Environment(AppEnvironment.self) private var env`.

enum AppRoute: Equatable {
    case loading
    case contentError
    /// Welcome + account (signed out, first launch) or the rest of the onboarding (signed in).
    case onboarding
    /// Login / sign-up for a returning user.
    case auth
    case home
}

@MainActor
@Observable
final class AppEnvironment {
    let store: LearningStore
    let tutor: TutorService
    let speech: SpeechService
    let restrictions: RestrictionManager
    let notifications: NotificationScheduler
    // B1 additions
    let config: AppConfig
    let backend: BackendClient
    let local: LocalStore
    let network: NetworkMonitor
    let settings: SettingsStore
    let content: ContentService
    let auth: AuthService
    let sync: SyncService

    private(set) var isBooting = true
    private(set) var isRestoring = false
    private(set) var welcomeSeen: Bool
    /// Screen Time authorization was withdrawn while the restrictions were enabled.
    var screenTimeAlertVisible = false
    /// French message when `RestrictionManager.apply` failed after a schedule change.
    private(set) var restrictionError: String?

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var screenTimeAlertShown = false
    private static let welcomeKey = "quinze.welcomeSeen"

    init(config: AppConfig, backend: BackendClient, local: LocalStore,
         restrictions: RestrictionManager, notifications: NotificationScheduler) {
        let network = NetworkMonitor()
        let settings = SettingsStore(local: local)
        let content = ContentService(backend: backend, network: network)
        let auth = AuthService(backend: backend)
        let sync = SyncService(backend: backend, local: local, settings: settings, network: network,
                               currentUserId: { [weak auth] in auth?.userId })
        let ai = AIClient(backend: backend)
        let store = LearningStore(local: local, content: content, settings: settings, restrictions: restrictions,
                                  notifications: notifications, sync: sync, network: network, ai: ai)
        self.config = config
        self.backend = backend
        self.local = local
        self.network = network
        self.settings = settings
        self.content = content
        self.auth = auth
        self.sync = sync
        self.store = store
        self.tutor = TutorService(ai: ai, network: network, store: store)
        self.speech = SpeechService()
        self.restrictions = restrictions
        self.notifications = notifications
        self.welcomeSeen = UserDefaults.standard.bool(forKey: Self.welcomeKey)
    }

    static func live() -> AppEnvironment {
        let config = AppConfig.load()
        return AppEnvironment(config: config, backend: BackendClient(config: config), local: LocalStore(),
                              restrictions: .shared, notifications: .shared)
    }

    /// In-memory environment for SwiftUI previews.
    static func preview() -> AppEnvironment {
        let config = AppConfig(supabaseURL: nil, anonKey: nil)
        return AppEnvironment(config: config, backend: BackendClient(config: config), local: LocalStore(inMemory: true),
                              restrictions: .shared, notifications: .shared)
    }

    // MARK: Routing

    var route: AppRoute {
        if isBooting || isRestoring { return .loading }
        switch auth.state {
        case .loading:
            return .loading
        case .signedOut:
            return welcomeSeen ? .auth : .onboarding
        case .signedIn, .passwordRecovery:
            if store.engine == nil { return .contentError }
            return settings.profile.onboardingCompleted ? .home : .onboarding
        }
    }

    func markWelcomeSeen() {
        welcomeSeen = true
        UserDefaults.standard.set(true, forKey: Self.welcomeKey)
    }

    // MARK: Launch

    func bootstrap() async {
        guard isBooting else { return }
        network.onRegain = { [weak self] in self?.connectivityRegained() }
        network.start()
        auth.onSignedIn = { [weak self] in await self?.postSignIn() }
        // Assigned through a local: Swift 6.0 rejects `sync.onDataChanged = { … }` written directly
        // ("converting non-sendable function value…"), the local form is accepted.
        let syncService = sync
        syncService.onDataChanged = { [weak self] scheduleChanged in await self?.syncDidMerge(scheduleChanged: scheduleChanged) }
        auth.start()
        await content.load(languageCode: settings.profile.languageId)
        store.attachContent()
        restrictions.refreshAuthorization()
        restrictions.reconcile(now: .now)
        if auth.state == .signedIn { await postSignIn() }
        isBooting = false
        startObservers()
        Task { await content.checkForUpdate() }
    }

    /// After a login (or at launch when a session exists): ownership check, restore on a new iPhone, normal start.
    func postSignIn() async {
        guard let uid = auth.userId else { return }
        if let owner = settings.profile.userId, owner != uid, !owner.hasPrefix("local-") { wipeLocalData() }
        settings.updateProfile { $0.userId = uid }
        if let name = auth.consumePendingDisplayName() { settings.setDisplayName(name) }
        if !settings.profile.onboardingCompleted {
            isRestoring = true
            _ = await sync.restoreFromServer()
            isRestoring = false
        }
        store.attachContent()
        await store.refresh()
        if settings.profile.onboardingCompleted { await startNormalOperation() }
    }

    private func startNormalOperation() async {
        applyRestrictionSchedule()
        sync.requestSync(.launch)
        await store.refresh()
        await store.rescheduleNotifications()
        await store.processPendingGradings()
    }

    /// Onboarding finished (first lesson done or postponed).
    func completeOnboarding() {
        settings.updateProfile {
            $0.onboardingCompleted = true
            $0.onboardingStep = 0
        }
        Task { await startNormalOperation() }
    }

    // MARK: Scene & system events

    func didBecomeActive() async {
        guard !isBooting else { return }
        let previous = restrictions.authorization
        restrictions.refreshAuthorization()
        restrictions.reconcile(now: .now)
        checkScreenTimeAuthorization(previous: previous)
        guard auth.state == .signedIn, settings.profile.onboardingCompleted else { return }
        sync.requestSync(.foreground)
        await store.refresh()
        await store.rescheduleNotifications()
        await store.processPendingGradings()
        await content.checkForUpdate()
    }

    func didEnterBackground() {
        store.suspendActiveSessions()
    }

    func handle(url: URL) async {
        await auth.handle(url: url)
    }

    private func connectivityRegained() {
        guard auth.state == .signedIn, settings.profile.onboardingCompleted else { return }
        sync.requestSync(.connectivity)
        Task {
            await store.processPendingGradings()
            await content.checkForUpdate()
        }
    }

    private func checkScreenTimeAuthorization(previous: RestrictionAuthorization) {
        let current = restrictions.authorization
        let revoked = restrictions.isEnabled && current == .denied
        if revoked {
            guard !screenTimeAlertShown else { return }
            screenTimeAlertShown = true
            screenTimeAlertVisible = true
            let preferences = settings.notificationPreferences
            Task { await notifications.notifyAuthorizationProblem(preferences: preferences) }
        } else if current == .approved {
            screenTimeAlertShown = false
        }
    }

    private func startObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.timeZoneDidChange() }
        })
        observers.append(center.addObserver(forName: UIApplication.significantTimeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.significantTimeChange() }
        })
    }

    /// New time zone: slots keep their wall-clock times; windows and reminders are re-registered.
    func timeZoneDidChange() async {
        guard auth.state == .signedIn, settings.profile.onboardingCompleted else { return }
        var schedule = settings.schedule
        schedule.timeZoneIdentifier = TimeZone.current.identifier
        settings.updateSchedule(schedule)
        await scheduleDidChange()
    }

    /// Midnight, clock change…: today's slots must be recomputed.
    private func significantTimeChange() async {
        guard auth.state == .signedIn, settings.profile.onboardingCompleted else { return }
        restrictions.reconcile(now: .now)
        await store.refresh()
        await store.rescheduleNotifications()
    }

    private func syncDidMerge(scheduleChanged: Bool) async {
        if scheduleChanged { applyRestrictionSchedule() }
        await store.refresh()
        if settings.profile.onboardingCompleted { await store.rescheduleNotifications() }
    }

    // MARK: Settings actions

    /// Validates and saves a schedule, then re-applies restrictions, reminders and sync.
    @discardableResult
    func saveSchedule(_ schedule: DailySchedule) async -> [DailySchedule.Issue] {
        let issues = settings.updateSchedule(schedule)
        guard issues.isEmpty else { return issues }
        await scheduleDidChange()
        return []
    }

    func scheduleDidChange() async {
        applyRestrictionSchedule()
        await store.rescheduleNotifications()
        await store.refresh()
        sync.requestSync(.settings)
    }

    private func applyRestrictionSchedule() {
        restrictionError = nil
        guard restrictions.isEnabled else { return }
        do {
            try restrictions.apply(schedule: settings.schedule)
        } catch {
            Log.app.error("restriction schedule could not be applied")
            restrictionError = "Les restrictions n'ont pas pu être programmées. Vérifie l'autorisation Temps d'écran dans les Réglages."
        }
    }

    func updateNotificationPreferences(_ preferences: NotificationPreferences) async {
        settings.updateNotificationPreferences(preferences)
        await store.rescheduleNotifications()
        sync.requestSync(.settings)
    }

    // MARK: Account

    /// Syncs (best effort, 6 s), signs out and switches the restrictions off: without an account there is no lesson to lift them.
    func logout() async -> Bool {
        store.suspendActiveSessions()
        let sync = self.sync
        _ = try? await withTimeout(seconds: 6) { await sync.syncNow(.manual) }
        guard await auth.signOut() else { return false }
        sync.cancelAll()
        shutDownRestrictions(reason: "logout")
        clearNotifications()
        return true
    }

    /// Server deletion first (needs the network), then local wipe, restrictions off, back to the welcome screen.
    func deleteAccount() async throws {
        store.suspendActiveSessions()
        try await auth.deleteAccountOnServer()
        sync.cancelAll()
        wipeLocalData()
        shutDownRestrictions(reason: "account_deleted")
        clearNotifications()
        welcomeSeen = false
        UserDefaults.standard.removeObject(forKey: Self.welcomeKey)
        await auth.finishDeletion()
    }

    private func wipeLocalData() {
        local.wipeAll()
        settings.reload()
        store.reset()
    }

    private func shutDownRestrictions(reason: String) {
        restrictions.emergencyUnlock(reason: reason)
        restrictions.setEnabled(false, schedule: settings.schedule)
    }

    private func clearNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}

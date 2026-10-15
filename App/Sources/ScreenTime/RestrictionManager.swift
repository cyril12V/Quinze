import Foundation
import Observation
import FamilyControls
import DeviceActivity
import UIKit
import OSLog
import LearningPrimitives

// CONTRACT FILE — owned by the "Screen Time" workstream (A).
// Other workstreams only use the members declared here. A replaces the TODOs and may add members.
//
// Responsibilities: Screen Time authorization, app selection (opaque tokens kept on device in the
// App Group, never synced), DeviceActivity scheduling of the three slot windows, lifting the slot's
// shield when its lesson is completed, emergency unlock, crash/expiry reconciliation.
//
// The state machine itself lives in `Shared/SlotEngine.swift` (shared with the extensions).

enum RestrictionAuthorization: Equatable, Sendable {
    case notDetermined
    case approved
    case denied
    /// Family Controls not available (simulator, missing entitlement, iOS restriction).
    case unavailable
}

enum RestrictionMode: String, Codable, Sendable, CaseIterable {
    /// Shield the apps, categories and websites picked by the user.
    case selectedApps
    /// Shield every app category except the apps picked as allowed (this app must be among them).
    case allExceptAllowed

    var displayName: String {
        switch self {
        case .selectedApps: return "Bloquer les apps choisies"
        case .allExceptAllowed: return "Tout bloquer sauf les apps autorisées"
        }
    }
}

enum SlotRestrictionState: String, Codable, Sendable {
    /// No restriction planned (feature off, no authorization or no selection).
    case none
    /// Will activate at the slot time.
    case scheduled
    /// Apps are shielded now.
    case active
    /// Lifted because the lesson was completed.
    case liftedByCompletion
    /// Lifted by the emergency unlock.
    case liftedByEmergency
    /// Lifted automatically at the end of the safety window.
    case expired
}

struct SlotRestrictionStatus: Equatable, Sendable {
    var slot: SessionSlot
    var day: LocalDay
    var state: SlotRestrictionState
    var activatedAt: Date?
    var expiresAt: Date?
}

/// Errors thrown by `RestrictionManager.apply(schedule:)`.
enum RestrictionError: Error, Equatable, LocalizedError {
    case notAuthorized
    case invalidSchedule
    case monitoringFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "L'autorisation Temps d'écran est nécessaire pour restreindre des apps."
        case .invalidSchedule:
            return "Les horaires choisis ne permettent pas de programmer les restrictions."
        case .monitoringFailed(let detail):
            return "La programmation des restrictions a échoué. \(detail)"
        }
    }
}

extension RestrictionMode {
    init(_ stored: StoredMode) {
        switch stored {
        case .selectedApps: self = .selectedApps
        case .allExceptAllowed: self = .allExceptAllowed
        }
    }

    var stored: StoredMode {
        switch self {
        case .selectedApps: return .selectedApps
        case .allExceptAllowed: return .allExceptAllowed
        }
    }
}

@MainActor
@Observable
final class RestrictionManager {
    static let shared = RestrictionManager()

    private(set) var authorization: RestrictionAuthorization = .notDetermined
    /// Current picker selection (bound to the FamilyActivityPicker by `AppSelectionView`).
    private(set) var selection = FamilyActivitySelection()
    private(set) var mode: RestrictionMode = .selectedApps
    /// User-level switch for the feature ("Restreindre les apps pendant les leçons").
    private(set) var isEnabled: Bool = false
    /// Slots whose shield is active right now (today).
    private(set) var activeSlots: [SessionSlot] = []
    /// Last problem worth showing in the settings (French), nil when everything is fine.
    private(set) var lastErrorMessage: String?

    var isRestrictionActive: Bool { !activeSlots.isEmpty }
    var hasSelection: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty
    }

    /// Preferences used for the "authorization lost" alert. The settings screen may replace it.
    @ObservationIgnored var notificationPreferencesProvider: @MainActor () -> NotificationPreferences = {
        NotificationScheduler.shared.lastKnownPreferences
    }

    private let stateStore: SharedStateStore
    private let shields: any ShieldControlling
    private let center = DeviceActivityCenter()
    private let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "fr.elmdigitalagency.quinze", category: "restrictions")
    @ObservationIgnored private var systemObservers: [NSObjectProtocol] = []

    init(stateStore: SharedStateStore = .shared,
         shields: any ShieldControlling = SystemShieldController(),
         observeSystemChanges: Bool = true) {
        self.stateStore = stateStore
        self.shields = shields
        loadFromSharedState()
        authorization = Self.currentAuthorization()
        if observeSystemChanges { startObservingSystemChanges() }
    }

    private var engine: SlotEngine { SlotEngine(store: stateStore, shields: shields) }

    // MARK: Authorization

    /// Reads the current authorization status (call on launch and when returning to foreground).
    /// Detects a revocation (approved before, not approved now): shields are dropped and the user is alerted.
    func refreshAuthorization() {
        let current = Self.currentAuthorization()
        authorization = current
        let wasApproved = stateStore.load().authorizationWasApproved
        if current == .approved {
            if !wasApproved { engine.setAuthorizationApproved(true) }
        } else if wasApproved {
            engine.setAuthorizationApproved(false)
            handleRevocation()
        }
    }

    /// Shows the system Screen Time authorization prompt (individual authorization).
    func requestAuthorization() async -> RestrictionAuthorization {
#if targetEnvironment(simulator)
        authorization = .unavailable
        lastErrorMessage = "Temps d'écran n'est pas disponible dans le simulateur."
        return .unavailable
#else
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            log.error("Screen Time authorization failed: \(String(describing: error), privacy: .public)")
            authorization = Self.classify(error)
            lastErrorMessage = Self.message(for: error)
            return authorization
        }
        lastErrorMessage = nil
        refreshAuthorization()
        restartMonitoringIfPossible()
        return authorization
#endif
    }

    private static func currentAuthorization() -> RestrictionAuthorization {
#if targetEnvironment(simulator)
        return .unavailable
#else
        switch AuthorizationCenter.shared.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .approved: return .approved
        @unknown default: return .unavailable
        }
#endif
    }

    private static func classify(_ error: Error) -> RestrictionAuthorization {
        guard let familyError = error as? FamilyControlsError else { return currentAuthorization() }
        switch familyError {
        case .authorizationCanceled, .networkError:
            // The user can simply try again.
            let current = currentAuthorization()
            return current == .unavailable ? .notDetermined : current
        case .authorizationConflict:
            return .denied
        default:
            return .unavailable
        }
    }

    private static func message(for error: Error) -> String {
        guard let familyError = error as? FamilyControlsError else {
            return "L'autorisation Temps d'écran a échoué."
        }
        switch familyError {
        case .authorizationCanceled:
            return "Autorisation annulée. Tu peux réessayer quand tu veux."
        case .networkError:
            return "Connecte-toi à internet pour activer Temps d'écran, puis réessaie."
        case .authorizationConflict:
            return "Une autre app de contrôle parental est déjà active sur cet appareil."
        case .invalidAccountType:
            return "Connecte-toi à iCloud dans les Réglages pour activer Temps d'écran."
        case .authenticationMethodUnavailable:
            return "Définis un code de verrouillage sur l'iPhone pour activer Temps d'écran."
        default:
            return "Temps d'écran n'est pas disponible sur cet appareil."
        }
    }

    private func handleRevocation() {
        log.notice("Screen Time authorization revoked")
        center.stopMonitoring(Self.allActivityNames)
        let outcome = engine.reconcile(now: Date(), authorized: false)
        activeSlots = outcome.activeSlots
        guard isEnabled else { return }
        lastErrorMessage = "Les restrictions ne fonctionnent plus : autorisation Temps d'écran retirée."
        let preferences = notificationPreferencesProvider()
        Task { await NotificationScheduler.shared.notifyAuthorizationProblem(preferences: preferences) }
    }

    // MARK: Selection

    /// Saves the selection in the App Group and re-applies the current shields if a slot is active.
    func updateSelection(_ selection: FamilyActivitySelection, mode: RestrictionMode) {
        self.selection = selection
        self.mode = mode
        let data = try? JSONEncoder().encode(selection)
        if data == nil { log.error("Could not encode the Screen Time selection") }
        engine.updateSelection(data: data, mode: mode.stored, now: Date())
        activeSlots = engine.activeSlots(now: Date())
        restartMonitoringIfPossible()
    }

    // MARK: Enable / schedule

    /// Turns the feature on/off. Off = stop monitoring and clear every shield.
    func setEnabled(_ enabled: Bool, schedule: DailySchedule) {
        let now = Date()
        isEnabled = enabled
        engine.setEnabled(enabled, now: now)
        engine.updateSchedule(schedule, now: now)
        if enabled {
            refreshAuthorization()
            do {
                try apply(schedule: schedule)
                lastErrorMessage = nil
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        } else {
            center.stopMonitoring(Self.allActivityNames)
            runReconcile(now: now)
            lastErrorMessage = nil
        }
    }

    /// (Re)starts DeviceActivity monitoring of the three slot windows. Call after any schedule change,
    /// time zone change and at launch.
    func apply(schedule: DailySchedule) throws {
        engine.updateSchedule(schedule, now: Date())
        center.stopMonitoring(Self.allActivityNames)
        defer { runReconcile(now: Date()) }

        guard isEnabled else { return }
        guard schedule.enabled else {
            // Lessons switched off: no restriction should outlive the change.
            engine.liftAll(reason: .disabled, now: Date())
            return
        }
        guard authorization == .approved else { throw RestrictionError.notAuthorized }
        guard hasSelection else { return }
        guard schedule.validate().isEmpty else { throw RestrictionError.invalidSchedule }

        var failure: Error?
        for slot in SessionSlot.allCases {
            let window = schedule.restrictionWindow(for: slot)
            let activitySchedule = DeviceActivitySchedule(
                intervalStart: window.start.dateComponents,
                intervalEnd: window.end.dateComponents,
                repeats: true,
                warningTime: nil)
            do {
                try center.startMonitoring(
                    DeviceActivityName(ScreenTimeNames.activityRawName(for: slot)), during: activitySchedule)
            } catch {
                log.error("startMonitoring failed for \(slot.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
                failure = failure ?? error
            }
        }
        if let failure { throw RestrictionError.monitoringFailed(Self.describe(failure)) }
    }

    private func restartMonitoringIfPossible() {
        guard isEnabled, let schedule = stateStore.load().schedule else { return }
        do {
            try apply(schedule: schedule)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private static func describe(_ error: Error) -> String {
        if let monitoring = error as? DeviceActivityCenter.MonitoringError {
            switch monitoring {
            case .excessiveActivities: return "Trop de programmations Temps d'écran sont déjà actives."
            case .intervalTooShort: return "Une fenêtre de restriction est trop courte."
            case .unauthorized: return "L'autorisation Temps d'écran est manquante."
            default: return "Erreur de programmation."
            }
        }
        return "Erreur de programmation."
    }

    // MARK: Lesson completion / emergency

    /// The slot's lesson was completed (or done during the early-start window): records it in the
    /// App Group so the monitor will not shield it, and lifts its shield if active.
    func sessionCompleted(slot: SessionSlot, day: LocalDay) {
        let now = Date()
        let lifted = engine.markCompleted(slot: slot, day: day, now: now)
        activeSlots = engine.activeSlots(now: now)
        log.info("Lesson completed (\(slot.rawValue, privacy: .public)), shield lifted: \(lifted)")
    }

    /// Lifts every active shield immediately and records the event. Always available.
    func emergencyUnlock(reason: String) {
        let now = Date()
        let lifted = engine.emergencyUnlock(reason: String(reason.prefix(120)), now: now)
        activeSlots = engine.activeSlots(now: now)
        log.notice("Emergency unlock, \(lifted.count) slot(s) lifted")
    }

    // MARK: Reconcile

    /// Crash recovery and consistency: clears shields that are past their safety deadline or whose
    /// lesson is completed, refreshes `activeSlots` and `authorization`. Also re-applies the schedule
    /// when the time zone changed since monitoring was started.
    func reconcile(now: Date) {
        refreshAuthorization()
        let state = stateStore.load()
        let currentZone = TimeZone.autoupdatingCurrent.identifier
        if isEnabled, authorization == .approved, let schedule = state.schedule,
           let startedIn = state.monitoringTimeZoneIdentifier, startedIn != currentZone {
            var updated = schedule
            updated.timeZoneIdentifier = currentZone
            do {
                try apply(schedule: updated)
                lastErrorMessage = nil
            } catch {
                lastErrorMessage = error.localizedDescription
            }
            return
        }
        runReconcile(now: now)
    }

    private func runReconcile(now: Date) {
        let outcome = engine.reconcile(now: now, authorized: authorization == .approved)
        activeSlots = outcome.activeSlots
    }

    // MARK: Status

    func status(for slot: SessionSlot, day: LocalDay) -> SlotRestrictionStatus {
        let stored = stateStore.load().record(slot, day)
        var result = SlotRestrictionStatus(
            slot: slot, day: day, state: SlotRestrictionState.none,
            activatedAt: stored?.activatedAt, expiresAt: stored?.expiresAt)
        guard isEnabled, authorization == .approved, hasSelection else { return result }

        let today = LocalDay(date: Date(), calendar: .autoupdatingCurrent)
        let upcoming: SlotRestrictionState = day >= today ? SlotRestrictionState.scheduled : SlotRestrictionState.none
        guard let record = stored else {
            result.state = upcoming
            return result
        }
        if record.active {
            result.state = .active
        } else if record.completed {
            result.state = .liftedByCompletion
        } else {
            switch record.liftReason {
            case .some(.emergency): result.state = .liftedByEmergency
            case .some(.expired): result.state = .expired
            case .some(.completed): result.state = .liftedByCompletion
            default: result.state = upcoming
            }
        }
        return result
    }

    /// Slots currently registered with DeviceActivity (diagnostics and tests on device).
    var monitoredSlots: [SessionSlot] {
        center.activities.compactMap { ScreenTimeNames.slot(fromActivityRawName: $0.rawValue) }
    }

    // MARK: System changes

    private static var allActivityNames: [DeviceActivityName] {
        SessionSlot.allCases.map { DeviceActivityName(ScreenTimeNames.activityRawName(for: $0)) }
    }

    private func loadFromSharedState() {
        let state = stateStore.load()
        isEnabled = state.enabled
        mode = RestrictionMode(state.mode)
        selection = SystemShieldController.decodeSelection(state.selectionData) ?? FamilyActivitySelection()
    }

    /// Time zone change, daylight saving change, manual clock change.
    private func startObservingSystemChanges() {
        guard systemObservers.isEmpty else { return }
        let names: [Notification.Name] = [.NSSystemTimeZoneDidChange, UIApplication.significantTimeChangeNotification]
        for name in names {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let manager = self else { return }
                    manager.reconcile(now: Date())
                }
            }
            systemObservers.append(token)
        }
    }
}

import Foundation
import Observation
import LearningCore

/// A run through the subjects of one sitting: anglais, puis arabe, puis culture G.
/// The lesson screen shows `controller`; when it is finished, `advance()` starts the next subject.
@MainActor
@Observable
final class StudyRun: Identifiable {
    enum Kind: Equatable {
        /// The lesson of a slot: every enabled subject must be done to complete the slot.
        case slot(SessionSlot)
        /// Free practice, subject after subject.
        case extra
        /// A single session (assessment, focused practice, resumed session).
        case single
    }

    let id = UUID()
    let kind: Kind
    private(set) var controller: LessonController
    /// Subjects studied so far in this run, in order.
    private(set) var studied: [Subject]
    @ObservationIgnored private unowned let coordinator: StudyCoordinator

    init(kind: Kind, controller: LessonController, coordinator: StudyCoordinator) {
        self.kind = kind
        self.controller = controller
        self.studied = [controller.subject]
        self.coordinator = coordinator
    }

    var slot: SessionSlot? {
        if case .slot(let slot) = kind { return slot }
        return nil
    }

    /// Subject that comes after the current one, once it is finished.
    var nextSubject: Subject? {
        guard controller.isFinished else { return nil }
        switch kind {
        case .slot(let slot):
            return coordinator.nextSubject(slot: slot, day: controller.plan.day)
        case .extra:
            return coordinator.enabledSubjects.first { !studied.contains($0) }
        case .single:
            return nil
        }
    }

    /// "Anglais · 1/3"
    var stepLabel: String? {
        let total: Int
        switch kind {
        case .slot, .extra: total = coordinator.enabledSubjects.count
        case .single: return nil
        }
        guard total > 1 else { return nil }
        let position = (coordinator.enabledSubjects.firstIndex(of: controller.subject) ?? 0) + 1
        return "\(controller.subject.displayName) · \(position)/\(total)"
    }

    /// Starts the next subject. Returns false when there is none (or it could not start).
    @discardableResult
    func advance() async -> Bool {
        guard let next = nextSubject else { return false }
        do {
            let started: LessonController?
            switch kind {
            case .slot(let slot): started = try await coordinator.startPart(of: slot, subject: next)
            case .extra: started = try await coordinator.store(next).startExtraSession()
            case .single: started = nil
            }
            guard let started else { return false }
            controller = started
            studied.append(next)
            return true
        } catch {
            // A subject with nothing to study is skipped.
            studied.append(next)
            if case .slot = kind { return await advance() }
            if nextSubject != nil { return await advance() }
            return false
        }
    }
}

/// Coordinates the three subjects: today's slots for the home screen, the order of a sitting,
/// when a slot is complete (every enabled subject done → its apps are unblocked), the reminders.
@MainActor
@Observable
final class StudyCoordinator {
    let stores: [Subject: LearningStore]
    private(set) var today: TodayState = .placeholder
    private(set) var isLoading = false
    var errorMessage: String?
    /// Subject shown by the screens that show one subject at a time (dictionary, progress, path, tutor).
    var focusSubject: Subject = .english
    var focusStore: LearningStore { store(focusSubject) }

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let local: LocalStore
    @ObservationIgnored private let restrictions: RestrictionManager
    @ObservationIgnored private let notifications: NotificationScheduler

    init(stores: [Subject: LearningStore], settings: SettingsStore, local: LocalStore,
         restrictions: RestrictionManager, notifications: NotificationScheduler) {
        self.stores = stores
        self.settings = settings
        self.local = local
        self.restrictions = restrictions
        self.notifications = notifications
        for store in stores.values { store.coordinator = self }
    }

    func store(_ subject: Subject) -> LearningStore {
        stores[subject] ?? stores[.english]!
    }

    /// Enabled subjects whose content is available, in study order.
    var enabledSubjects: [Subject] {
        let list = settings.study.enabledSubjects.filter { stores[$0]?.engine != nil }
        return list.isEmpty ? [.english] : list
    }

    // MARK: Today

    func refresh(now: Date = .now) async {
        isLoading = true
        defer { isLoading = false }
        for subject in Subject.allCases where stores[subject]?.engine != nil {
            await stores[subject]?.refresh(now: now)
        }
        let day = LocalDay(date: now)
        let subjects = enabledSubjects
        let sessions = local.sessions()
        let active = Set(restrictions.activeSlots)
        let schedule = settings.schedule
        let slots = SessionSlot.allCases.map { slot -> SlotState in
            let parts = subjects.map { subject in
                SubjectPart(subject: subject,
                            status: SlotLogic.status(slot: slot, day: day, now: now, schedule: schedule,
                                                     sessions: sessions.filter { $0.subjectCode == subject.code }))
            }
            let status = Self.combinedStatus(parts.map(\.status))
            let sessionId = sessions.first { $0.slot == slot && $0.day == day && $0.status == .inProgress }?.id
            return SlotState(slot: slot, scheduledTime: schedule.time(for: slot), status: status,
                             restrictionActive: active.contains(slot) && status != .completed,
                             sessionId: sessionId, parts: parts)
        }
        let completedDays = SlotLogic.completedDays(sessions: sessions)
        let streak = LearningEngine.streak(completedDays: completedDays, today: day)
        let due = subjects.reduce(0) { $0 + (stores[$1]?.today.dueReviewCount ?? 0) }
        let assessmentDue = stores[.english]?.today.assessmentDue ?? false
        today = TodayState(day: day, slots: slots, streakDays: streak, dueReviewCount: due, assessmentDue: assessmentDue)
    }

    /// A slot is completed when every subject is; in progress as soon as one subject was started or done.
    static func combinedStatus(_ statuses: [SlotStatus]) -> SlotStatus {
        guard let first = statuses.first else { return .upcoming }
        if statuses.allSatisfy({ $0 == .completed }) { return .completed }
        if statuses.contains(.inProgress) || statuses.contains(.completed) { return .inProgress }
        return first
    }

    // MARK: Sittings

    /// Next subject of a slot that is not done yet, in study order.
    func nextSubject(slot: SessionSlot, day: LocalDay) -> Subject? {
        let sessions = local.sessions(on: day)
        return enabledSubjects.first { subject in
            !sessions.contains { $0.slot == slot && $0.subjectCode == subject.code && $0.status == .completed }
        }
    }

    func isSlotComplete(_ slot: SessionSlot, day: LocalDay) -> Bool {
        nextSubject(slot: slot, day: day) == nil
    }

    /// Starts (or resumes) the slot at its first unfinished subject.
    func startSlot(_ slot: SessionSlot) async throws -> StudyRun {
        do {
            let day = LocalDay(date: .now)
            guard let subject = nextSubject(slot: slot, day: day) else { throw LearningStoreError.slotAlreadyCompleted }
            guard let controller = try await startPart(of: slot, subject: subject) else { throw LearningStoreError.emptySession }
            errorMessage = nil
            return StudyRun(kind: .slot(slot), controller: controller, coordinator: self)
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Starts one subject's session of a slot. A subject with nothing left to study gets an empty completed
    /// session (so the slot can still be completed) and the next subject is started instead.
    func startPart(of slot: SessionSlot, subject: Subject) async throws -> LessonController? {
        do {
            return try await store(subject).startSession(for: slot)
        } catch LearningStoreError.emptySession {
            let now = Date.now
            let day = LocalDay(date: now)
            local.saveSession(SessionRecord(id: UUID(), type: slot.defaultSessionType, slot: slot, day: day,
                                            startedAt: now, completedAt: now, status: .completed, updatedAt: now,
                                            subject: subject.code), dirty: true)
            _ = await slotPartCompleted(slot: slot, day: day)
            if let next = nextSubject(slot: slot, day: day) {
                return try await startPart(of: slot, subject: next)
            }
            return nil
        }
    }

    /// Free practice through every enabled subject.
    func startExtra() async throws -> StudyRun {
        var lastError: Error = LearningStoreError.emptySession
        for subject in enabledSubjects {
            do {
                let controller = try await store(subject).startExtraSession()
                errorMessage = nil
                return StudyRun(kind: .extra, controller: controller, coordinator: self)
            } catch {
                lastError = error
            }
        }
        errorMessage = lastError.localizedDescription
        throw lastError
    }

    func startAssessment() async throws -> StudyRun {
        let controller = try await store(.english).startAssessment()
        return StudyRun(kind: .single, controller: controller, coordinator: self)
    }

    func single(_ controller: LessonController) -> StudyRun {
        if let slot = controller.slot {
            return StudyRun(kind: .slot(slot), controller: controller, coordinator: self)
        }
        return StudyRun(kind: .single, controller: controller, coordinator: self)
    }

    /// A session interrupted earlier, whatever its subject.
    func resumableRun() -> StudyRun? {
        for subject in Subject.studyOrder {
            if let controller = stores[subject]?.resumableSession() { return single(controller) }
        }
        return nil
    }

    // MARK: Completion & reminders

    /// Called when one subject's session of a slot is completed. Lifts the slot's shield once every
    /// subject is done. Returns whether a restriction was lifted (nil when none applied or not yet).
    func slotPartCompleted(slot: SessionSlot, day: LocalDay) async -> Bool? {
        guard isSlotComplete(slot, day: day) else { return nil }
        let wasActive = restrictions.activeSlots.contains(slot)
        restrictions.sessionCompleted(slot: slot, day: day)
        let lifted: Bool? = wasActive ? !restrictions.activeSlots.contains(slot) : nil
        await notifications.sessionCompleted(slot: slot, day: day, restrictionsLifted: lifted ?? false,
                                             preferences: settings.notificationPreferences)
        return lifted
    }

    func subjectSessionDidFinish() async {
        await refresh()
        await rescheduleNotifications()
    }

    /// Reminders for the coming days: a slot counts as done only when all its subjects are.
    func rescheduleNotifications(now: Date = .now) async {
        let todayDay = LocalDay(date: now)
        var completed: [LocalDay: Set<SessionSlot>] = [:]
        let days = Set(local.sessions().filter { $0.day >= todayDay }.map(\.day))
        for day in days {
            for slot in SessionSlot.allCases where isSlotComplete(slot, day: day) {
                completed[day, default: []].insert(slot)
            }
        }
        await notifications.reschedule(schedule: settings.schedule, preferences: settings.notificationPreferences,
                                       completed: completed, dueReviewCount: today.dueReviewCount, now: now)
    }
}

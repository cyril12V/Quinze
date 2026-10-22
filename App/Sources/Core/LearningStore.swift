import Foundation
import Observation
import LearningCore

// CONTRACT FILE — owned by the "services" workstream (B1).
// The learning UI (B2) is written against the members declared here: keep their names and types.

enum SlotStatus: String, Sendable {
    /// Scheduled later today (cannot be started yet, except within the early-start window).
    case upcoming
    /// Can be started now.
    case available
    /// Started and not finished (resumable).
    case inProgress
    case completed
    /// The restriction window ended without the lesson being done; it can still be done for practice.
    case missed
}

/// One subject's part of a slot (anglais, arabe, culture G).
struct SubjectPart: Identifiable, Equatable, Sendable {
    var subject: Subject
    var status: SlotStatus
    var id: Subject { subject }
}

struct SlotState: Identifiable, Equatable, Sendable {
    var id: SessionSlot { slot }
    var slot: SessionSlot
    var scheduledTime: TimeOfDay
    var status: SlotStatus
    /// Apps are currently shielded for this slot.
    var restrictionActive: Bool
    var sessionId: UUID?
    /// Subjects of the slot, in study order (empty for a single-subject view).
    var parts: [SubjectPart] = []

    var completedParts: Int { parts.filter { $0.status == .completed }.count }
}

/// Everything the home screen needs (§14.2).
struct TodayState: Equatable, Sendable {
    var day: LocalDay
    var slots: [SlotState]
    var streakDays: Int
    var dueReviewCount: Int
    var assessmentDue: Bool

    var completedCount: Int { slots.filter { $0.status == .completed }.count }
    /// The slot to put forward: in progress, else available, else the next upcoming one.
    var featuredSlot: SlotState? {
        slots.first { $0.status == .inProgress }
            ?? slots.first { $0.status == .available }
            ?? slots.first { $0.status == .upcoming }
    }

    static let placeholder = TodayState(day: LocalDay(date: Date()), slots: [], streakDays: 0, dueReviewCount: 0, assessmentDue: false)
}

struct AssessmentRecord: Identifiable, Equatable, Sendable {
    var id: UUID
    var day: LocalDay
    var score: Double
}

/// Totals for the progress dashboard (§15.1) that the engine does not compute.
struct UsageStats: Equatable, Sendable {
    var sessionsCompleted: Int
    var totalLearningSeconds: Int
    var streakDays: Int
    var assessments: [AssessmentRecord]

    static let zero = UsageStats(sessionsCompleted: 0, totalLearningSeconds: 0, streakDays: 0, assessments: [])
}

enum LearningStoreError: LocalizedError, Equatable {
    case contentUnavailable
    case slotNotYetAvailable(TimeOfDay)
    case slotAlreadyCompleted
    case emptySession

    var errorDescription: String? {
        switch self {
        case .contentUnavailable:
            return "Le contenu des leçons n'est pas encore chargé. Réessaie dans un instant."
        case .slotNotYetAvailable(let time):
            return "Cette leçon sera disponible à \(time)."
        case .slotAlreadyCompleted:
            return "Tu as déjà terminé cette leçon aujourd'hui."
        case .emptySession:
            return "Aucun exercice n'est disponible pour le moment."
        }
    }
}

private struct RefreshComputation: Sendable {
    let dueReviewCount: Int
    let assessmentDue: Bool
    let progress: ProgressReport
}

private enum PlanKind: Sendable {
    case standard
    case assessment
    case focused(String)
}

/// State and actions of ONE subject (anglais, arabe ou culture G): its engine, its learner and its sessions.
/// `StudyCoordinator` chains the subjects of a slot and decides when a slot is complete.
@MainActor
@Observable
final class LearningStore {
    let subject: Subject
    /// Set by the environment: chains subjects, lifts restrictions, plans reminders for the whole day.
    @ObservationIgnored weak var coordinator: StudyCoordinator?
    /// Nil until the content bundle is loaded.
    private(set) var engine: LearningEngine?
    private(set) var learner: LearnerSnapshot = .empty
    private(set) var today: TodayState = .placeholder
    private(set) var stats: UsageStats = .zero
    private(set) var progress: ProgressReport?
    private(set) var displayName: String?
    /// "Anglais"
    private(set) var languageName: String = "Anglais"
    private(set) var isLoading: Bool = false
    /// User-facing error message (French), if the last operation failed.
    var errorMessage: String?
    /// Answers waiting for AI grading (offline or quota reached).
    private(set) var pendingGradingCount: Int = 0

    // Services used by the controllers (same module).
    let local: LocalStore
    let settings: SettingsStore
    let restrictions: RestrictionManager
    let notifications: NotificationScheduler
    let sync: SyncService
    let network: NetworkMonitor
    let ai: AIClient
    private let content: ContentService

    private var trackedWordIds: Set<String> = []
    private var activeControllers: [UUID: LessonController] = [:]
    private var refreshGeneration = 0
    private var isProcessingGradings = false

    init(subject: Subject, local: LocalStore, content: ContentService, settings: SettingsStore, restrictions: RestrictionManager,
         notifications: NotificationScheduler, sync: SyncService, network: NetworkMonitor, ai: AIClient) {
        self.subject = subject
        self.languageName = subject.displayName
        self.local = local
        self.content = content
        self.settings = settings
        self.restrictions = restrictions
        self.notifications = notifications
        self.sync = sync
        self.network = network
        self.ai = ai
    }

    // MARK: Lifecycle

    /// Takes the engine built by the content service.
    func attachContent() {
        engine = content.engines[subject]
        languageName = subject.displayName
    }

    // MARK: This subject's share of local storage

    func myMemoryStates() -> [MemoryState] { local.memoryStates().filter { subject.owns($0.unitId) } }
    func myAttempts() -> [AttemptRecord] { local.recentAttempts(limit: 2_000).filter { subject.owns($0.exerciseId) } }
    func mySessions() -> [SessionRecord] { local.sessions().filter { $0.subjectCode == subject.code } }
    func mySessions(on day: LocalDay) -> [SessionRecord] { local.sessions(on: day).filter { $0.subjectCode == subject.code } }
    private func myPendingGradingCount() -> Int {
        local.pendingGradings(limit: 1_000).filter { subject.owns($0.exerciseId) }.count
    }

    /// The placement test only exists for English.
    private var snapshotProfile: UserProfileRecord {
        guard subject != .english else { return settings.profile }
        var p = settings.profile
        p.placement = nil
        p.estimatedLevel = nil
        return p
    }

    /// Forgets everything in memory (local data was wiped).
    func reset() {
        activeControllers.removeAll()
        learner = .empty
        today = .placeholder
        stats = .zero
        progress = nil
        displayName = nil
        trackedWordIds = []
        pendingGradingCount = 0
    }

    /// The learner as seen by the engine, rebuilt from local storage.
    @discardableResult
    func reloadLearner() -> LearnerSnapshot {
        let snapshot = SnapshotBuilder.build(memoryStates: myMemoryStates(), attempts: myAttempts(),
                                             sessions: mySessions(), profile: snapshotProfile)
        learner = snapshot
        return snapshot
    }

    /// Recomputes today's slots, streak, due reviews and progress from local storage.
    func refresh(now: Date = .now) async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let profile = settings.profile
        let sessions = expireStaleSessions(mySessions(), now: now)
        let snapshot = SnapshotBuilder.build(memoryStates: myMemoryStates(), attempts: myAttempts(),
                                             sessions: sessions, profile: snapshotProfile)
        learner = snapshot
        displayName = profile.displayName
        trackedWordIds = Set(local.vocabulary().map(\.dictionaryItemId).filter { subject.owns($0) })
        pendingGradingCount = myPendingGradingCount()

        let day = LocalDay(date: now)
        let slots = SlotLogic.slotStates(day: day, now: now, schedule: settings.schedule, sessions: sessions,
                                         activeRestrictions: Set(restrictions.activeSlots))
        let completedDays = SlotLogic.completedDays(sessions: sessions)
        let streak = LearningEngine.streak(completedDays: completedDays, today: day)
        let done = sessions.filter { $0.status == .completed && $0.type != .diagnostic }
        let assessments = done.filter { $0.type == .assessment }
            .sorted { $0.day < $1.day }
            .map { AssessmentRecord(id: $0.id, day: $0.day, score: $0.score ?? 0) }
        stats = UsageStats(sessionsCompleted: done.count, totalLearningSeconds: done.reduce(0) { $0 + $1.durationSeconds },
                           streakDays: streak, assessments: assessments)
        // Slots first (cheap), engine computations after.
        today = TodayState(day: day, slots: slots, streakDays: streak, dueReviewCount: today.dueReviewCount,
                           assessmentDue: today.assessmentDue)
        guard let engine else { return }
        let computed = await Task.detached(priority: .userInitiated) {
            RefreshComputation(dueReviewCount: engine.dueReviews(learner: snapshot, now: now).count,
                               assessmentDue: engine.isAssessmentDue(learner: snapshot, now: now),
                               progress: engine.progress(learner: snapshot, now: now))
        }.value
        guard generation == refreshGeneration else { return }
        today = TodayState(day: day, slots: slots, streakDays: streak, dueReviewCount: computed.dueReviewCount,
                           assessmentDue: profile.onboardingCompleted && computed.assessmentDue)
        progress = computed.progress
    }

    /// A session left in progress on a previous day can no longer be resumed.
    private func expireStaleSessions(_ sessions: [SessionRecord], now: Date) -> [SessionRecord] {
        let day = LocalDay(date: now)
        return sessions.map { session in
            guard session.status == .inProgress, session.day < day else { return session }
            var expired = session
            expired.status = .expired
            expired.updatedAt = now
            local.saveSession(expired, dirty: true)
            local.clearRunner(for: expired.id)
            activeControllers[expired.id] = nil
            return expired
        }
    }

    // MARK: Starting sessions

    /// Starts — or resumes if one is in progress — the session of a slot.
    func startSession(for slot: SessionSlot) async throws -> LessonController {
        try await report {
            guard engine != nil else { throw LearningStoreError.contentUnavailable }
            let now = Date.now
            let day = LocalDay(date: now)
            let existing = mySessions(on: day).filter { $0.slot == slot }
            if existing.contains(where: { $0.status == .completed }) { throw LearningStoreError.slotAlreadyCompleted }
            if let running = existing.first(where: { $0.status == .inProgress }), let controller = controller(resuming: running) {
                return controller
            }
            let status = SlotLogic.status(slot: slot, day: day, now: now, schedule: settings.schedule, sessions: existing)
            if status == .upcoming {
                let opens = settings.schedule.time(for: slot).adding(minutes: -settings.schedule.earlyStartMinutes)
                throw LearningStoreError.slotNotYetAvailable(opens)
            }
            // One session per slot per day: a stale row (expired, skipped…) is reused.
            let reuse = existing.first
            return try await launch(kind: .standard, type: slot.defaultSessionType, slot: slot,
                                    sessionId: reuse?.id ?? UUID(), now: now)
        }
    }

    /// Extra practice session (outside slots, e.g. after the 3 daily lessons).
    func startExtraSession() async throws -> LessonController {
        try await report { try await launch(kind: .standard, type: .extra, slot: nil, sessionId: UUID(), now: .now) }
    }

    /// Periodic consolidation test (§15.3).
    func startAssessment() async throws -> LessonController {
        try await report { try await launch(kind: .assessment, type: .assessment, slot: nil, sessionId: UUID(), now: .now) }
    }

    /// Practice focused on one unit (tutor: "Fais-moi réviser cette règle").
    func startFocusedPractice(unitId: String) async throws -> LessonController {
        try await report { try await launch(kind: .focused(unitId), type: .extra, slot: nil, sessionId: UUID(), now: .now) }
    }

    /// The very first lesson at the end of the onboarding (a learning session outside the daily slots).
    func startFirstLesson() async throws -> LessonController {
        try await report { try await launch(kind: .standard, type: .learning, slot: nil, sessionId: UUID(), now: .now) }
    }

    /// A session interrupted earlier (app killed, user left), if any.
    func resumableSession() -> LessonController? {
        let day = LocalDay(date: .now)
        let running = mySessions(on: day)
            .filter { $0.status == .inProgress }
            .sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
        for record in running {
            if let controller = controller(resuming: record) { return controller }
        }
        return nil
    }

    private func report<T>(_ operation: @MainActor () async throws -> T) async throws -> T {
        do {
            let value = try await operation()
            errorMessage = nil
            return value
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func launch(kind: PlanKind, type: SessionType, slot: SessionSlot?, sessionId: UUID, now: Date) async throws -> LessonController {
        guard let engine else { throw LearningStoreError.contentUnavailable }
        isLoading = true
        defer { isLoading = false }
        let snapshot = reloadLearner()
        let day = LocalDay(date: now)
        let seed = sessionId.planSeed
        let raw = await Task.detached(priority: .userInitiated) { () -> SessionPlan in
            switch kind {
            case .standard:
                let plan = engine.planSession(type: type, slot: slot, day: day, learner: snapshot, now: now, seed: seed)
                // Nothing to review yet (new subject): free practice teaches the next lesson instead.
                if plan.items.isEmpty && type == .extra {
                    return engine.planSession(type: .learning, slot: nil, day: day, learner: snapshot, now: now, seed: seed)
                }
                return plan
            case .assessment:
                return engine.planAssessment(day: day, learner: snapshot, now: now, seed: seed)
            case .focused(let unitId):
                return engine.planFocusedPractice(unitId: unitId, day: day, learner: snapshot, now: now, seed: seed)
            }
        }.value
        guard !raw.items.isEmpty else { throw LearningStoreError.emptySession }
        // The session row id and the plan id are the same, so attempts reference an existing session.
        let plan = SessionPlan(id: sessionId, type: raw.type, slot: raw.slot ?? slot, day: raw.day, lessonId: raw.lessonId,
                               newUnitIds: raw.newUnitIds, items: raw.items, estimatedSeconds: raw.estimatedSeconds,
                               createdAt: raw.createdAt)
        let scheduled = slot.map { SlotLogic.instant(day: day, time: settings.schedule.time(for: $0)) }
        let record = SessionRecord(id: sessionId, type: plan.type, slot: plan.slot, day: day, scheduledAt: scheduled,
                                   startedAt: now, status: .inProgress, lessonId: plan.lessonId, updatedAt: now,
                                   subject: subject.code)
        local.saveSession(record, dirty: true)
        let runner = SessionRunner(plan: plan, startedAt: now)
        local.saveRunner(runner, for: sessionId)
        let controller = LessonController(plan: plan, runner: runner, record: record, engine: engine, store: self)
        activeControllers[sessionId] = controller
        Task { await refresh() }
        return controller
    }

    private func controller(resuming record: SessionRecord) -> LessonController? {
        if let existing = activeControllers[record.id], !existing.isFinished { return existing }
        guard let engine, let runner = local.runner(for: record.id) else { return nil }
        let controller = LessonController(plan: runner.plan, runner: runner, record: record, engine: engine, store: self)
        activeControllers[record.id] = controller
        return controller
    }

    /// Called by a controller once its session is completed and persisted.
    func sessionDidFinish(_ controller: LessonController) async {
        activeControllers[controller.id] = nil
        await refresh()
        await coordinator?.subjectSessionDidFinish()
        sync.requestSync(.sessionCompleted)
        await processPendingGradings()
    }

    /// Saves every running session (app going to the background).
    func suspendActiveSessions() {
        for controller in activeControllers.values { controller.suspend() }
    }

    // MARK: Attempts & memory

    /// Applies an attempt to the learner and persists it immediately (attempt + changed memory states).
    func record(attempt: AttemptRecord, now: Date) {
        guard let engine else { return }
        var updated = learner
        let changed = engine.apply(attempt, to: &updated, now: now)
        local.saveAttempt(attempt, updatedAt: now, dirty: true)
        local.upsertMemoryStates(changed, dirty: true)
        learner = updated
    }

    /// Local mode: there is no AI to grade uncertain answers, the learner compares with the expected answer.
    var canGradeWithAI: Bool { ai.isConfigured }

    /// Verdict given by the learner on an uncertain answer (local mode).
    func resolveBySelfGrading(attemptId: UUID, correct: Bool, errorCategory: ErrorCategory?, now: Date = .now) {
        resolvePending(attemptId: attemptId, result: correct ? .correct : .incorrect,
                       errorCategory: correct ? nil : (errorCategory ?? .vocabulary), now: now)
    }

    private func resolvePending(attemptId: UUID, result: AttemptResult, errorCategory: ErrorCategory?, now: Date) {
        guard let engine else { return }
        var updated = learner
        let changed = engine.resolvePendingAttempt(id: attemptId, result: result, errorCategory: errorCategory,
                                                   learner: &updated, now: now)
        if var attempt = local.attempt(id: attemptId) {
            attempt.result = result
            attempt.errorCategory = errorCategory
            local.saveAttempt(attempt, updatedAt: now, dirty: true)
        }
        local.upsertMemoryStates(changed, dirty: true)
        learner = updated
    }

    // MARK: AI grading

    /// Asks the AI to grade an uncertain answer. nil = keep the attempt pending (offline, quota, uncertain…).
    func gradeWithAI(exerciseId: String, answer: String) async -> AIGradeOutcome? {
        guard let engine, network.isOnline else { return nil }
        let code = engine.language.code
        let level = learner.estimatedLevel ?? 1
        let client = ai
        do {
            let response = try await withTimeout(seconds: 10) {
                try await client.grade(languageCode: code, level: level, exerciseId: exerciseId, userAnswer: answer)
            }
            return AIGradeOutcome(response: response)
        } catch {
            Log.lesson.notice("AI grading unavailable: answer kept pending")
            return nil
        }
    }

    func enqueueGrading(attempt: AttemptRecord, now: Date) {
        local.enqueueGrading(attemptId: attempt.id, exerciseId: attempt.exerciseId, userAnswer: attempt.submittedAnswer, now: now)
        pendingGradingCount = myPendingGradingCount()
    }

    /// Grades queued answers when the network allows it (foreground, connectivity regained, after a session).
    func processPendingGradings() async {
        guard network.isOnline, engine != nil, !isProcessingGradings else { return }
        isProcessingGradings = true
        defer { isProcessingGradings = false }
        var resolvedAny = false
        for item in local.pendingGradings(limit: 200).filter({ subject.owns($0.exerciseId) }).prefix(10) {
            guard let engine else { break }
            let client = ai
            let code = engine.language.code
            let level = learner.estimatedLevel ?? 1
            do {
                let response = try await withTimeout(seconds: 15) {
                    try await client.grade(languageCode: code, level: level, exerciseId: item.exerciseId, userAnswer: item.userAnswer)
                }
                if let outcome = AIGradeOutcome(response: response) {
                    resolvePending(attemptId: item.attemptId, result: outcome.result, errorCategory: outcome.errorCategory, now: .now)
                    local.removePendingGrading(attemptId: item.attemptId)
                    resolvedAny = true
                } else {
                    // Still uncertain: after 3 tries the attempt is left pending for good (never penalises the learner).
                    local.bumpGradingTries(attemptId: item.attemptId)
                    if item.tries + 1 >= 3 { local.removePendingGrading(attemptId: item.attemptId) }
                }
            } catch let failure as AIClient.Failure where failure == .rateLimited || failure == .offline || failure == .notConfigured {
                break
            } catch {
                local.bumpGradingTries(attemptId: item.attemptId)
                if item.tries + 1 >= 5 { local.removePendingGrading(attemptId: item.attemptId) }
            }
        }
        pendingGradingCount = myPendingGradingCount()
        if resolvedAny {
            sync.requestSync(.manual)
            await refresh()
        }
    }

    // MARK: Placement (onboarding diagnostic)

    func makeDiagnostic(selfAssessed: SelfAssessedLevel) -> DiagnosticSession? {
        engine?.makeDiagnostic(selfAssessed: selfAssessed, seed: UInt64.random(in: 0...UInt64.max))
    }

    /// Saves the diagnostic outcome (or the self-assessment when the test is skipped) and seeds the memory.
    func completePlacement(_ result: DiagnosticResult?, selfAssessed: SelfAssessedLevel, now: Date = .now) {
        guard let engine else { return }
        var updated = reloadLearner()
        var startSequence: Int?
        if let result {
            let changed = engine.applyPlacement(result, to: &updated, now: now)
            local.upsertMemoryStates(changed, dirty: true)
            startSequence = engine.lesson(result.startLessonId)?.sequence
        }
        settings.recordPlacement(result, selfAssessed: selfAssessed, startLessonSequence: startSequence,
                                 languageId: engine.language.code, now: now)
        reloadLearner()
        sync.requestSync(.manual)
    }

    // MARK: Notifications

    /// Reminders cover the whole day (every subject): planned by the coordinator.
    func rescheduleNotifications(now: Date = .now) async {
        await coordinator?.rescheduleNotifications(now: now)
    }

    // MARK: Time-based sessions

    /// More practice for a session that ended before its target duration (fast learner): reviews and
    /// exercises of the studied notions, never cards, never exercises already in the session.
    func extensionItems(for plan: SessionPlan, now: Date) -> [SessionItem] {
        guard let engine else { return [] }
        let snapshot = learner
        let day = LocalDay(date: now)
        let seed = UInt64(truncatingIfNeeded: Int(now.timeIntervalSince1970)) &+ plan.id.planSeed
        let more = engine.planSession(type: .extra, slot: nil, day: day, learner: snapshot, now: now, seed: seed)
        return more.items.filter { $0.exerciseId != nil }
    }

    /// Target length (seconds) of this subject's part of a session.
    var targetSessionSeconds: Int { settings.study.minutes(for: subject) * 60 }

    // MARK: Content & dictionary

    func unit(_ id: String) -> LearningUnit? { engine?.unit(id) }
    func exercise(_ id: String) -> Exercise? { engine?.exercise(id) }
    func lesson(_ id: String) -> Lesson? { engine?.lesson(id) }

    func dictionaryEntry(for word: String) -> DictionaryItem? {
        engine?.lookup(word)
    }

    func searchDictionary(_ query: String) -> [DictionaryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return engine?.searchDictionary(trimmed) ?? []
    }

    func isWordTracked(_ dictionaryItemId: String) -> Bool {
        trackedWordIds.contains(dictionaryItemId)
    }

    /// "Apprendre ce mot": adds the word to reviews (persisted + synced).
    func trackWord(_ dictionaryItemId: String) async {
        guard let engine, !trackedWordIds.contains(dictionaryItemId) else { return }
        let now = Date.now
        var updated = learner
        guard let state = engine.trackWord(dictionaryItemId: dictionaryItemId, learner: &updated, now: now) else {
            errorMessage = "Ce mot ne peut pas être ajouté à tes révisions."
            return
        }
        local.upsertMemoryStates([state], dirty: true)
        local.saveVocabulary(VocabularyRecord(dictionaryItemId: dictionaryItemId, addedAt: now, status: .learning, updatedAt: now),
                             dirty: true)
        learner = updated
        trackedWordIds.insert(dictionaryItemId)
        sync.requestSync(.manual)
        await refresh()
    }

    func mastery(of unitId: String) -> MasteryReport? {
        engine?.mastery(of: unitId, learner: learner, now: .now)
    }

    /// Mastery of every studied unit, for the progress screen's detail lists.
    func studiedUnits() -> [(unit: LearningUnit, mastery: MasteryReport)] {
        guard let engine else { return [] }
        let now = Date.now
        let snapshot = learner
        let rows = snapshot.memoryStates.values.compactMap { state -> (unit: LearningUnit, mastery: MasteryReport)? in
            // Units only presumed known by the diagnostic and never reviewed are not "studied" yet.
            if state.source == .diagnostic && state.reviewCount == 0 { return nil }
            guard let unit = engine.unit(state.unitId) else { return nil }
            return (unit: unit, mastery: engine.mastery(of: state.unitId, learner: snapshot, now: now))
        }
        return rows.sorted { $0.unit.title.localizedCompare($1.unit.title) == .orderedAscending }
    }
}

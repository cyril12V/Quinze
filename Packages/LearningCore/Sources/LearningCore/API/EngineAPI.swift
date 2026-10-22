import Foundation

// PUBLIC CONTRACT OF THE ENGINE.
// The app is written against exactly these signatures. Implementations live here and in Engine/.
// Public names, parameters and return types below must not change.

/// Indexed, read-only view of a ContentBundle.
public final class ContentIndex: Sendable {
    public let bundle: ContentBundle
    public let unitsById: [String: LearningUnit]
    public let lessonsById: [String: Lesson]
    /// Sorted by `sequence`.
    public let lessonsInOrder: [Lesson]
    /// Lesson, diagnostic and assessment exercises.
    public let exercisesById: [String: Exercise]
    /// Lesson-pool exercises indexed by every unit they practise.
    public let lessonExercisesByUnit: [String: [Exercise]]
    public let dictionaryById: [String: DictionaryItem]
    /// Normalized word and inflected forms -> dictionary item ("went" -> go).
    public let dictionaryByForm: [String: DictionaryItem]
    /// Internal lookup tables (forms, known words, search rows…).
    let tables: ContentIndexTables

    public init(bundle: ContentBundle) {
        let t = ContentIndexTables(bundle: bundle)
        self.bundle = bundle
        self.tables = t
        self.unitsById = t.unitsById
        self.lessonsById = t.lessonsById
        self.lessonsInOrder = t.lessonsInOrder
        self.exercisesById = t.exercisesById
        self.lessonExercisesByUnit = t.lessonExercisesByUnit
        self.dictionaryById = t.dictionaryById
        self.dictionaryByForm = t.dictionaryByForm
    }
}

public struct LearningEngine: Sendable {
    public let index: ContentIndex
    public let configuration: EngineConfiguration

    public init(bundle: ContentBundle, configuration: EngineConfiguration = .default) {
        self.init(index: ContentIndex(bundle: bundle), configuration: configuration)
    }

    public init(index: ContentIndex, configuration: EngineConfiguration = .default) {
        self.index = index
        self.configuration = configuration
    }

    // MARK: Content access

    public var language: LanguageInfo { index.bundle.language }
    public func unit(_ id: String) -> LearningUnit? { index.unitsById[id] }
    public func lesson(_ id: String) -> Lesson? { index.lessonsById[id] }
    public func exercise(_ id: String) -> Exercise? { index.exercisesById[id] }

    // MARK: Planning

    /// Next lesson to introduce: first lesson in sequence not completed/placed whose grammar
    /// prerequisites are sufficiently mastered (or bypassed after `prerequisiteBypassDays`).
    public func nextLesson(for learner: LearnerSnapshot, now: Date) -> Lesson? {
        nextLessonImpl(for: learner, now: now)
    }

    /// Builds a 8–12 interaction session (~5 min) of the given type. Deterministic for a given seed.
    public func planSession(type: SessionType, slot: SessionSlot?, day: LocalDay,
                            learner: LearnerSnapshot, now: Date, seed: UInt64) -> SessionPlan {
        planSessionImpl(type: type, slot: slot, day: day, learner: learner, now: now, seed: seed)
    }

    /// Extra session focused on one unit (tutor button "Fais-moi réviser cette règle").
    public func planFocusedPractice(unitId: String, day: LocalDay, learner: LearnerSnapshot,
                                    now: Date, seed: UInt64) -> SessionPlan {
        planFocusedPracticeImpl(unitId: unitId, day: day, learner: learner, now: now, seed: seed)
    }

    /// True when `assessmentIntervalDays` have passed since the last assessment (or since start).
    public func isAssessmentDue(learner: LearnerSnapshot, now: Date) -> Bool {
        isAssessmentDueImpl(learner: learner, now: now)
    }

    /// Periodic consolidation test built from the assessment pool and never-seen exercises.
    public func planAssessment(day: LocalDay, learner: LearnerSnapshot, now: Date, seed: UInt64) -> SessionPlan {
        planAssessmentImpl(day: day, learner: learner, now: now, seed: seed)
    }

    /// Memory states due now, most urgent (lowest retrievability) first.
    public func dueReviews(learner: LearnerSnapshot, now: Date) -> [MemoryState] {
        dueReviewsImpl(learner: learner, now: now)
    }

    /// A different exercise practising the same primary unit (remediation, §9.2).
    public func similarExercise(to exerciseId: String, learner: LearnerSnapshot,
                                excluding: Set<String>, seed: UInt64) -> Exercise? {
        similarExerciseImpl(to: exerciseId, learner: learner, excluding: excluding, seed: seed)
    }

    // MARK: Evaluation (level 1, deterministic)

    public func evaluate(_ exercise: Exercise, submission: AnswerSubmission) -> Evaluation {
        AnswerEvaluator(index: index).evaluate(exercise, submission)
    }

    // MARK: Memory updates

    /// Applies an attempt to the learner (FSRS + mastery evidence + recent attempts) and returns the
    /// memory states that changed. Pending attempts are recorded but do not update scheduling.
    @discardableResult
    public func apply(_ attempt: AttemptRecord, to learner: inout LearnerSnapshot, now: Date) -> [MemoryState] {
        if learner.startedAt == nil { learner.startedAt = attempt.answeredAt }
        if let i = learner.recentAttempts.lastIndex(where: { $0.id == attempt.id }) {
            // Already recorded (e.g. re-applied after a resume): resolve instead of duplicating.
            guard learner.recentAttempts[i].result == .pending, attempt.result != .pending else { return [] }
            return resolvePendingAttempt(id: attempt.id, result: attempt.result, errorCategory: attempt.errorCategory,
                                         learner: &learner, now: now)
        }
        return MemoryUpdater(index: index, configuration: configuration).apply(attempt, to: &learner, now: now)
    }

    /// Resolves a pending attempt once the AI has graded it, then applies it.
    @discardableResult
    public func resolvePendingAttempt(id: UUID, result: AttemptResult, errorCategory: ErrorCategory?,
                                      learner: inout LearnerSnapshot, now: Date) -> [MemoryState] {
        MemoryUpdater(index: index, configuration: configuration)
            .resolve(id: id, result: result, errorCategory: errorCategory, learner: &learner, now: now)
    }

    // MARK: Mastery & progress

    public func mastery(of unitId: String, learner: LearnerSnapshot, now: Date) -> MasteryReport {
        masteryReport(of: unitId, learner: learner, now: now)
    }

    public func progress(learner: LearnerSnapshot, now: Date) -> ProgressReport {
        buildProgress(learner: learner, now: now)
    }

    /// Consecutive days (ending today or yesterday) on which at least one session was completed.
    public static func streak(completedDays: Set<LocalDay>, today: LocalDay, calendar: Calendar = .current) -> Int {
        var day = completedDays.contains(today) ? today : today.adding(days: -1, calendar: calendar)
        var count = 0
        while completedDays.contains(day) {
            count += 1
            day = day.adding(days: -1, calendar: calendar)
        }
        return count
    }

    // MARK: Diagnostic

    public func makeDiagnostic(selfAssessed: SelfAssessedLevel, seed: UInt64) -> DiagnosticSession {
        makeDiagnosticImpl(selfAssessed: selfAssessed, seed: seed)
    }

    /// Marks placed lessons and seeds memory states for presumed-known units (source `.diagnostic`).
    @discardableResult
    public func applyPlacement(_ result: DiagnosticResult, to learner: inout LearnerSnapshot, now: Date) -> [MemoryState] {
        applyPlacementImpl(result, to: &learner, now: now)
    }

    // MARK: Dictionary

    /// Finds the entry for a tapped word, including inflected forms and contractions ("went", "doesn't").
    public func lookup(_ word: String) -> DictionaryItem? {
        lookupImpl(word)
    }

    /// Prefix/substring search on words and French translations.
    public func searchDictionary(_ query: String, limit: Int = 30) -> [DictionaryItem] {
        searchDictionaryImpl(query, limit: limit)
    }

    /// "Apprendre ce mot": starts tracking the word's unit (source `.dictionary`), never marks it mastered.
    /// Returns nil when the item has no learnable unit.
    @discardableResult
    public func trackWord(dictionaryItemId: String, learner: inout LearnerSnapshot, now: Date) -> MemoryState? {
        trackWordImpl(dictionaryItemId: dictionaryItemId, learner: &learner, now: now)
    }
}

/// UI-independent state machine of one session. Codable so an interrupted session can be resumed.
/// Flow: for an exercise item, `submit` once (item then awaits `advance`); cards only need `advance`.
/// After an incorrect/partial answer, `advance` inserts a similar exercise at the end
/// (at most `maxRemediationsPerSession`). The session is complete when every item has been processed.
public struct SessionRunner: Codable, Hashable, Sendable {
    public private(set) var plan: SessionPlan
    /// Plan items followed by inserted remediation items.
    public private(set) var items: [SessionItem]
    public private(set) var position: Int
    public private(set) var attempts: [AttemptRecord]
    public private(set) var lastEvaluation: Evaluation?
    /// True between `submit` and `advance` on an exercise item.
    public private(set) var awaitingAdvance: Bool
    public private(set) var remediationCount: Int
    public private(set) var startedAt: Date
    /// Exercises already re-queued as-is (when no similar exercise exists).
    private var repeatedExerciseIds: [String]

    public init(plan: SessionPlan, startedAt: Date) {
        self.plan = plan
        self.items = plan.items
        self.position = 0
        self.attempts = []
        self.lastEvaluation = nil
        self.awaitingAdvance = false
        self.remediationCount = 0
        self.startedAt = startedAt
        self.repeatedExerciseIds = []
    }

    public var currentItem: SessionItem? { position < items.count ? items[position] : nil }
    public var isComplete: Bool { position >= items.count }
    public var completedCount: Int { min(position, items.count) }
    public var totalCount: Int { items.count }

    /// Evaluates the answer to the current exercise item and records the attempt.
    public mutating func submit(_ submission: AnswerSubmission, hintUsed: Bool, duration: TimeInterval,
                                engine: LearningEngine, now: Date) -> (evaluation: Evaluation, attempt: AttemptRecord) {
        // A second submission on the same item is ignored (double tap, resumed UI).
        if awaitingAdvance, let last = attempts.last, let evaluation = lastEvaluation {
            return (evaluation, last)
        }
        guard let item = currentItem, let exerciseId = item.exerciseId, let exercise = engine.exercise(exerciseId) else {
            let evaluation = Evaluation(result: .incorrect, expectedAnswer: "", userAnswer: submission.displayText)
            let attempt = AttemptRecord(exerciseId: currentItem?.exerciseId ?? "", sessionId: plan.id, unitIds: [],
                                        exerciseType: .mcq, presentation: currentItem?.presentation ?? .choices,
                                        submittedAnswer: submission.displayText, result: .incorrect, errorCategory: nil,
                                        hintUsed: hintUsed, isRemediation: false, durationSeconds: duration, answeredAt: now)
            return (evaluation, attempt)
        }
        let evaluation = engine.evaluate(exercise, submission: submission)
        let attempt = AttemptRecord(exerciseId: exercise.id, sessionId: plan.id, unitIds: exercise.unitIds,
                                    exerciseType: exercise.type, presentation: item.presentation,
                                    submittedAnswer: submission.displayText, result: evaluation.result,
                                    errorCategory: evaluation.isCorrect ? nil : evaluation.errorCategory,
                                    hintUsed: hintUsed, isRemediation: item.role == .remediation,
                                    durationSeconds: max(duration, 0), answeredAt: now)
        attempts.append(attempt)
        lastEvaluation = evaluation
        awaitingAdvance = true
        return (evaluation, attempt)
    }

    /// Replaces the verdict of the last attempt (AI grading). Returns the updated attempt.
    @discardableResult
    public mutating func overrideLastEvaluation(_ evaluation: Evaluation) -> AttemptRecord? {
        guard !attempts.isEmpty else { return nil }
        let i = attempts.count - 1
        attempts[i].result = evaluation.result
        attempts[i].errorCategory = evaluation.isCorrect ? nil : evaluation.errorCategory
        lastEvaluation = evaluation
        return attempts[i]
    }

    /// Moves to the next item, inserting a remediation item after a wrong answer.
    public mutating func advance(engine: LearningEngine, learner: LearnerSnapshot) {
        guard let item = currentItem else { return }
        if let exerciseId = item.exerciseId, awaitingAdvance, let evaluation = lastEvaluation,
           evaluation.result == .incorrect || evaluation.result == .partial,
           plan.type != .assessment, plan.type != .diagnostic,
           remediationCount < engine.configuration.maxRemediationsPerSession {
            let inSession = Set(items.compactMap { $0.exerciseId })
            let seed = stableHash(plan.id.uuidString) &+ UInt64(position)
            if let similar = engine.similarExercise(to: exerciseId, learner: learner, excluding: inSession, seed: seed) {
                let presentation = SessionRunner.guidedPresentation(for: similar)
                items.append(SessionItem(kind: .exercise(exerciseId: similar.id), role: .remediation,
                                         presentation: presentation, hintAllowed: true))
                remediationCount += 1
            } else if !repeatedExerciseIds.contains(exerciseId) {
                repeatedExerciseIds.append(exerciseId)
                items.append(SessionItem(kind: .exercise(exerciseId: exerciseId), role: .remediation,
                                         presentation: item.presentation, hintAllowed: true))
                remediationCount += 1
            }
        }
        position += 1
        awaitingAdvance = false
        lastEvaluation = nil
    }

    public func summary(engine: LearningEngine, now: Date) -> SessionSummary {
        buildSummary(engine: engine, now: now)
    }

    /// Adds items at the end of the session (time-based sessions: a fast learner gets more practice
    /// until the target duration is reached). Exercises already in the session are skipped.
    /// Returns the number of items added.
    @discardableResult
    public mutating func extend(with newItems: [SessionItem]) -> Int {
        let inSession = Set(items.compactMap { $0.exerciseId })
        var added = 0
        for item in newItems {
            if let exerciseId = item.exerciseId, inSession.contains(exerciseId) { continue }
            items.append(item)
            added += 1
        }
        return added
    }
}

/// Adaptive placement test (15–20 questions, staircase on levels 0...4).
public struct DiagnosticSession: Codable, Hashable, Sendable {
    public private(set) var currentLevel: Int
    public private(set) var answers: [DiagnosticAnswer]
    public private(set) var askedIds: [String]
    public let maxQuestions: Int
    private let minQuestions: Int
    private let seed: UInt64
    private var consecutiveCorrect: Int
    /// No unasked diagnostic question was left when one was requested.
    public private(set) var bankExhausted: Bool

    public var answeredCount: Int { answers.count }
    public var isFinished: Bool {
        if bankExhausted || answers.count >= maxQuestions { return true }
        guard answers.count >= minQuestions else { return false }
        return DiagnosticSupport.isStable(answers)
    }

    public init(startLevel: Int, maxQuestions: Int, minQuestions: Int, seed: UInt64) {
        self.currentLevel = min(max(startLevel, 0), 4)
        self.answers = []
        self.askedIds = []
        self.maxQuestions = max(maxQuestions, 1)
        self.minQuestions = min(max(minQuestions, 1), max(maxQuestions, 1))
        self.seed = seed
        self.consecutiveCorrect = 0
        self.bankExhausted = false
    }

    /// Next question, or nil when finished.
    public mutating func nextExercise(engine: LearningEngine) -> Exercise? {
        guard !isFinished else { return nil }
        // An unanswered question is still pending: ask it again.
        if askedIds.count > answers.count, let pendingId = askedIds.last, let pending = engine.exercise(pendingId) {
            return pending
        }
        let pool = engine.index.bundle.diagnostic.filter { $0.deprecated != true && !askedIds.contains($0.id) }
        guard !pool.isEmpty else {
            bankExhausted = true
            return nil
        }
        var levelPool: [Exercise] = []
        for distance in 0...4 {
            levelPool = pool.filter { abs(($0.level ?? 0) - currentLevel) == distance }
            if distance > 0 {
                // Prefer the lower level when the requested one is empty.
                let lower = levelPool.filter { ($0.level ?? 0) < currentLevel }
                if !lower.isEmpty { levelPool = lower }
            }
            if !levelPool.isEmpty { break }
        }
        // Topic variety: least asked topic first.
        var topicCounts: [String: Int] = [:]
        for id in askedIds { if let t = engine.exercise(id)?.topic { topicCounts[t, default: 0] += 1 } }
        let minCount = levelPool.map { topicCounts[$0.topic ?? "", default: 0] }.min() ?? 0
        let candidates = levelPool.filter { topicCounts[$0.topic ?? "", default: 0] == minCount }.sorted { $0.id < $1.id }
        guard !candidates.isEmpty else {
            bankExhausted = true
            return nil
        }
        var generator = SplitMix64(seed: seed &+ UInt64(askedIds.count))
        let i = generator.nextInt(candidates.count)
        let chosen = candidates[i]
        askedIds.append(chosen.id)
        return chosen
    }

    public mutating func record(exerciseId: String, evaluation: Evaluation, engine: LearningEngine) {
        guard !answers.contains(where: { $0.exerciseId == exerciseId }) else { return }
        let exercise = engine.exercise(exerciseId)
        let level = exercise?.level ?? currentLevel
        let correct = evaluation.isCorrect
        if !askedIds.contains(exerciseId) { askedIds.append(exerciseId) }
        answers.append(DiagnosticAnswer(exerciseId: exerciseId, level: level, topic: exercise?.topic ?? "", correct: correct))
        if correct {
            consecutiveCorrect += 1
            if consecutiveCorrect >= 2 {
                currentLevel = min(currentLevel + 1, 4)
                consecutiveCorrect = 0
            }
        } else {
            currentLevel = max(currentLevel - 1, 0)
            consecutiveCorrect = 0
        }
    }

    public func result(engine: LearningEngine) -> DiagnosticResult {
        engine.diagnosticResult(for: self)
    }
}

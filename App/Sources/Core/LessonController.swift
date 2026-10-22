import Foundation
import Observation
import LearningCore

// CONTRACT FILE — owned by the "services" workstream (B1).
// Drives one session on screen: wraps `SessionRunner`, persists every attempt, asks the AI to
// grade uncertain answers, updates memory states, lifts the slot's restriction on completion.
// The learning UI (B2) only uses the members declared here.

enum LessonPhase: Equatable {
    /// A rule card or a word card is shown (`currentUnit`); the user taps "Continuer".
    case card
    /// An exercise awaits an answer.
    case answering
    /// Waiting for the AI to grade an uncertain answer (short spinner).
    case grading
    /// Correction screen for the last answer.
    case correction(Evaluation)
    /// Session completed (§14.5).
    case finished(SessionSummary)
}

@MainActor
@Observable
final class LessonController: Identifiable {
    let id: UUID
    let plan: SessionPlan

    private(set) var phase: LessonPhase = .answering
    private(set) var currentItem: SessionItem?
    /// Exercise of the current item (nil for cards).
    private(set) var currentExercise: Exercise?
    /// Unit of the current card, or primary unit of the current exercise.
    private(set) var currentUnit: LearningUnit?
    /// Presentation decided by the planner, possibly downgraded (e.g. word bank shown) — read this, not the exercise type.
    private(set) var presentation: PresentationMode = .typed
    private(set) var hintRevealed: Bool = false
    /// 0...1 for the progress bar.
    private(set) var progressFraction: Double = 0
    /// "3 / 10"
    private(set) var progressLabel: String = ""
    /// After completion: whether the slot's app restriction was lifted (nil when no restriction applies).
    private(set) var restrictionLifted: Bool?
    /// The correction of a free answer is waiting for the network to be verified (level 3).
    private(set) var pendingReviewNotice: Bool = false

    var slot: SessionSlot? { plan.slot }
    var type: SessionType { plan.type }
    /// Subject studied in this session.
    var subject: Subject { store.subject }
    /// Items added because the learner was faster than the subject's target duration.
    private(set) var extendedCount = 0
    var isFinished: Bool { if case .finished = phase { return true } else { return false } }
    var summary: SessionSummary? { if case .finished(let s) = phase { return s } else { return nil } }

    private var runner: SessionRunner
    private var record: SessionRecord
    private let engine: LearningEngine
    private unowned let store: LearningStore
    private var itemShownAt = Date()
    private var isBusy = false
    private var isFinishing = false

    /// Built by `LearningStore` (B2 never constructs controllers).
    init(plan: SessionPlan, runner: SessionRunner, record: SessionRecord, engine: LearningEngine, store: LearningStore) {
        self.id = plan.id
        self.plan = plan
        self.runner = runner
        self.record = record
        self.engine = engine
        self.store = store
        restore()
    }

    // MARK: Public actions

    func revealHint() {
        guard case .answering = phase, !hintRevealed, currentItem?.hintAllowed == true else { return }
        hintRevealed = true
        // A fill-in-the-blank typed answer gets its word bank once the hint is requested.
        if presentation == .typed, currentExercise?.type == .fillBlank, currentExercise?.options?.isEmpty == false {
            presentation = .choices
        }
    }

    /// Evaluates the answer (AI grading when uncertain and online), persists the attempt and
    /// moves to `.correction`.
    func submit(_ submission: AnswerSubmission) async {
        guard case .answering = phase, !isBusy, let exercise = currentExercise else { return }
        isBusy = true
        defer { isBusy = false }
        let now = Date.now
        let duration = max(0, now.timeIntervalSince(itemShownAt))
        let outcome = runner.submit(submission, hintUsed: hintRevealed, duration: duration, engine: engine, now: now)
        var evaluation = outcome.evaluation
        var attempt = outcome.attempt

        if evaluation.needsAIReview {
            var graded = false
            if store.network.isOnline {
                phase = .grading
                if let ai = await store.gradeWithAI(exerciseId: exercise.id, answer: attempt.submittedAnswer) {
                    evaluation = Self.merge(ai, into: evaluation)
                    attempt = runner.overrideLastEvaluation(evaluation) ?? attempt
                    graded = true
                }
            }
            if !graded { pendingReviewNotice = true }
        }
        store.record(attempt: attempt, now: now)
        if attempt.result == .pending, store.canGradeWithAI { store.enqueueGrading(attempt: attempt, now: now) }
        persistRunner()
        phase = .correction(evaluation)
    }

    /// Local mode: the answer could not be checked automatically, the learner says whether it matches.
    var canSelfGrade: Bool {
        guard pendingReviewNotice, !store.canGradeWithAI, case .correction(let evaluation) = phase else { return false }
        return evaluation.result == .pending
    }

    func selfGrade(correct: Bool) {
        guard canSelfGrade, case .correction(var evaluation) = phase else { return }
        evaluation.result = correct ? .correct : .incorrect
        evaluation.needsAIReview = false
        evaluation.gradedBy = .localFallback
        if correct { evaluation.errorCategory = nil } else if evaluation.errorCategory == nil { evaluation.errorCategory = .vocabulary }
        if let attempt = runner.overrideLastEvaluation(evaluation) {
            store.resolveBySelfGrading(attemptId: attempt.id, correct: correct, errorCategory: evaluation.errorCategory)
        }
        pendingReviewNotice = false
        persistRunner()
        phase = .correction(evaluation)
    }

    /// From a card or a correction: next item, or `.finished` (persists the session as completed,
    /// lifts the slot restriction, updates notifications, triggers sync).
    func continueToNext() async {
        switch phase {
        case .card, .correction: break
        default: return
        }
        guard !isBusy else { return }
        runner.advance(engine: engine, learner: store.learner)
        if runner.isComplete { extendIfTimeRemains() }
        persistRunner()
        if runner.isComplete {
            await finish()
        } else {
            presentCurrent()
        }
    }

    /// Saves the runner so the session can be resumed later (app backgrounded / user closes).
    func suspend() {
        guard !isFinished, !isFinishing else { return }
        persistRunner()
    }

    /// Time-based sessions: a learner who answers fast keeps practising (reviews of what he knows,
    /// exercises of the notions he is studying) until the subject's target duration is reached.
    private func extendIfTimeRemains() {
        switch plan.type {
        case .learning, .application, .consolidation, .extra: break
        case .diagnostic, .assessment: return
        }
        let elapsed = Date.now.timeIntervalSince(runner.startedAt)
        let target = Double(store.targetSessionSeconds)
        // Stop when less than ~25 s remain, and never more than 60 extra items in one session.
        guard elapsed < target - 25, extendedCount < 60 else { return }
        let batch = Array(store.extensionItems(for: plan, now: .now).prefix(6))
        let added = runner.extend(with: batch)
        extendedCount += added
    }

    // MARK: State

    /// Rebuilds the screen state from the runner (new session or resumed one).
    private func restore() {
        guard !runner.isComplete else {
            // Everything was answered but the completion was not persisted (killed in between).
            Task { await self.finish() }
            return
        }
        presentCurrent()
        if runner.awaitingAdvance, runner.currentItem?.exerciseId != nil, let last = runner.lastEvaluation {
            phase = .correction(last)
        }
    }

    private func presentCurrent() {
        hintRevealed = false
        pendingReviewNotice = false
        itemShownAt = Date()
        updateProgress()
        guard let item = runner.currentItem else { return }
        currentItem = item
        presentation = item.presentation
        switch item.kind {
        case .ruleCard(let unitId), .wordCard(let unitId):
            currentExercise = nil
            currentUnit = engine.unit(unitId)
            phase = .card
        case .exercise(let exerciseId):
            let exercise = engine.exercise(exerciseId)
            currentExercise = exercise
            currentUnit = exercise.flatMap { engine.unit($0.primaryUnitId) }
            // An exercise missing from the content cannot be answered: show it as a card the user can skip.
            phase = exercise == nil ? .card : .answering
        }
    }

    private func updateProgress() {
        let total = max(runner.totalCount, 1)
        progressFraction = min(1, Double(runner.completedCount) / Double(total))
        progressLabel = "\(min(runner.completedCount + 1, total)) / \(total)"
    }

    private func persistRunner() {
        store.local.saveRunner(runner, for: id)
    }

    /// AI verdict -> evaluation shown on the correction screen.
    private static func merge(_ ai: AIGradeOutcome, into evaluation: Evaluation) -> Evaluation {
        var merged = evaluation
        merged.result = ai.result
        merged.errorCategory = ai.errorCategory ?? (ai.result.countsAsSuccess ? nil : evaluation.errorCategory)
        var feedback = (ai.explanation ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let corrected = ai.correctedAnswer?.trimmingCharacters(in: .whitespacesAndNewlines),
           !corrected.isEmpty, !ai.result.countsAsSuccess {
            feedback += (feedback.isEmpty ? "" : "\n") + "Correction proposée : \(corrected)"
        }
        merged.feedback = feedback.isEmpty ? evaluation.feedback : feedback
        merged.needsAIReview = false
        merged.gradedBy = .ai
        return merged
    }

    // MARK: Completion

    private func finish() async {
        guard !isFinishing, !isFinished else { return }
        isFinishing = true
        let now = Date.now
        let summary = runner.summary(engine: engine, now: now)

        var completed = record
        completed.status = .completed
        completed.completedAt = now
        completed.itemCount = summary.attemptCount
        completed.correctCount = summary.correctCount
        completed.durationSeconds = Int(summary.durationSeconds.rounded())
        completed.score = summary.score
        completed.updatedAt = now
        record = completed
        store.local.saveSession(completed, dirty: true)
        store.local.clearRunner(for: id)

        // A slot's shield is lifted once every subject of the slot is done (coordinator).
        var lifted: Bool?
        if let slot = plan.slot, let coordinator = store.coordinator {
            lifted = await coordinator.slotPartCompleted(slot: slot, day: plan.day)
        }
        restrictionLifted = lifted
        currentItem = nil
        currentExercise = nil
        progressFraction = 1
        phase = .finished(summary)
        isFinishing = false
        await store.sessionDidFinish(self)
    }
}

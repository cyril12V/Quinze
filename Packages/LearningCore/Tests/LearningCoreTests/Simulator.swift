import XCTest
@testable import LearningCore

/// Plays sessions with a virtual learner whose probability of success grows with the mastery of the unit.
struct Simulator {
    let engine: LearningEngine
    var learner = LearnerSnapshot()
    var rng: SplitMix64
    /// p(success) = base + gain * mastery(primary unit), capped at 0.97.
    var base: Double
    var gain: Double
    var seed: UInt64 = 1
    var completedDays = Set<LocalDay>()
    struct Record {
        let day: Int
        let slot: SessionSlot
        let plan: SessionPlan
        let summary: SessionSummary
        let exerciseIds: [String]
        let remediations: Int
    }
    var records: [Record] = []
    var lessonCompletionDay: [String: Int] = [:]
    /// Latent knowledge of the virtual learner per unit (0...1): grows with practice, fades with time.
    var knowledge: [String: Double] = [:]
    var lastPractice: [String: Date] = [:]

    init(engine: LearningEngine, seed: UInt64 = 7, base: Double = 0.55, gain: Double = 0.42) {
        self.engine = engine
        self.rng = SplitMix64(seed: seed)
        self.base = base
        self.gain = gain
    }

    /// Knowledge of the exercise: mean over its units (primary counted twice), with forgetting (time constant 20 days).
    func latentKnowledge(of ex: Exercise, at now: Date) -> Double {
        var sum = 0.0, weight = 0.0
        for (i, u) in ex.unitIds.enumerated() {
            let w = i == 0 ? 2.0 : 1.0
            var k = knowledge[u] ?? 0.25
            if let last = lastPractice[u] { k *= exp(-max(0, now.timeIntervalSince(last)) / 86_400 / 20) }
            sum += w * k; weight += w
        }
        return weight == 0 ? 0 : sum / weight
    }

    mutating func practice(_ ex: Exercise, success: Bool, at now: Date) {
        for u in ex.unitIds {
            var k = knowledge[u] ?? 0.25
            if let last = lastPractice[u] { k *= exp(-max(0, now.timeIntervalSince(last)) / 86_400 / 20) }
            k += (success ? 0.12 : 0.05) * (1 - k)
            knowledge[u] = k
            lastPractice[u] = now
        }
    }

    static func hour(_ slot: SessionSlot) -> Int { [9, 14, 20][slot.index] }

    @discardableResult
    mutating func run(day offset: Int, slot: SessionSlot, type: SessionType? = nil, answerAll: Bool = false) -> Record {
        let now0 = TestSupport.date(day: offset, hour: Simulator.hour(slot))
        let day = TestSupport.day(offset)
        if learner.startedAt == nil { learner.startedAt = now0 }
        seed &+= 1
        let sessionType = type ?? slot.defaultSessionType
        let plan: SessionPlan
        if sessionType == .assessment {
            plan = engine.planAssessment(day: day, learner: learner, now: now0, seed: seed)
        } else {
            plan = engine.planSession(type: sessionType, slot: slot, day: day, learner: learner, now: now0, seed: seed)
        }
        var runner = SessionRunner(plan: plan, startedAt: now0)
        var now = now0
        var ids: [String] = []
        var guardCount = 0
        while !runner.isComplete && guardCount < 100 {
            guardCount += 1
            if let id = runner.currentItem?.exerciseId, let ex = engine.exercise(id) {
                let p = answerAll ? 1.0 : min(0.97, base + gain * latentKnowledge(of: ex, at: now))
                let ok = rng.nextDouble() < p
                let sub = ok ? TestSupport.modelSubmission(ex) : TestSupport.wrongSubmission(ex)
                let (ev, attempt) = runner.submit(sub, hintUsed: false, duration: 20, engine: engine, now: now)
                engine.apply(attempt, to: &learner, now: now)
                ids.append(id)
                practice(ex, success: ev.isCorrect, at: now)
            }
            runner.advance(engine: engine, learner: learner)
            now = now.addingTimeInterval(30)
        }
        engine.registerCompletion(of: plan, attempts: runner.attempts, to: &learner, now: now)
        completedDays.insert(day)
        if plan.type == .learning, let l = plan.lessonId, learner.completedLessonIds.contains(l), lessonCompletionDay[l] == nil {
            lessonCompletionDay[l] = offset
        }
        let record = Record(day: offset, slot: slot, plan: plan, summary: runner.summary(engine: engine, now: now), exerciseIds: ids,
                            remediations: runner.remediationCount)
        records.append(record)
        return record
    }

    mutating func runDay(_ offset: Int, assessmentIfDue: Bool = true) {
        run(day: offset, slot: .morning)
        run(day: offset, slot: .afternoon)
        let eveningNow = TestSupport.date(day: offset, hour: 20)
        if assessmentIfDue && engine.isAssessmentDue(learner: learner, now: eveningNow) {
            run(day: offset, slot: .evening, type: .assessment)
        } else {
            run(day: offset, slot: .evening)
        }
    }
}

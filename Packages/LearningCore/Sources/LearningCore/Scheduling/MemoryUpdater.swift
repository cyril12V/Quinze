import Foundation

/// Applies attempts to the learner state: FSRS-4.5 scheduling with the adaptations of the spec
/// (grades, skill weights, rapid repetitions, minimum intervals, secondary units, counters).
struct MemoryUpdater: Sendable {
    let index: ContentIndex
    let configuration: EngineConfiguration
    let fsrs: FSRS

    init(index: ContentIndex, configuration: EngineConfiguration) {
        self.index = index
        self.configuration = configuration
        self.fsrs = FSRS(configuration: configuration)
    }

    // MARK: Entry points

    func apply(_ attempt: AttemptRecord, to learner: inout LearnerSnapshot, now: Date) -> [MemoryState] {
        learner.recentAttempts.append(attempt)
        let limit = max(configuration.attemptHistoryLimit, 1)
        if learner.recentAttempts.count > limit { learner.recentAttempts.removeFirst(learner.recentAttempts.count - limit) }
        return schedule(attempt, learner: &learner, now: now)
    }

    func resolve(id: UUID, result: AttemptResult, errorCategory: ErrorCategory?,
                 learner: inout LearnerSnapshot, now: Date) -> [MemoryState] {
        guard result != .pending,
              let i = learner.recentAttempts.lastIndex(where: { $0.id == id }),
              learner.recentAttempts[i].result == .pending else { return [] }
        learner.recentAttempts[i].result = result
        learner.recentAttempts[i].errorCategory = result.countsAsSuccess ? nil : (errorCategory ?? learner.recentAttempts[i].errorCategory)
        let attempt = learner.recentAttempts[i]
        // The review is dated at the time of the answer, unless another review happened since.
        var at = attempt.answeredAt
        for unitId in attempt.unitIds {
            if let last = learner.memoryStates[unitId]?.lastReviewAt, last > at { at = now; break }
        }
        return schedule(attempt, learner: &learner, now: min(at, now))
    }

    // MARK: Scheduling

    func schedule(_ attempt: AttemptRecord, learner: inout LearnerSnapshot, now: Date) -> [MemoryState] {
        guard attempt.result != .pending else { return [] }
        let exercise = index.exercisesById[attempt.exerciseId]
        let skill = exercise?.skill ?? attempt.exerciseType.defaultSkill
        let success = attempt.result.countsAsSuccess
        var changed: [MemoryState] = []
        var seen = Set<String>()
        for (i, unitId) in attempt.unitIds.enumerated() where seen.insert(unitId).inserted {
            let existing = learner.memoryStates[unitId]
            if i > 0 {
                // Secondary units: successes only, and only units already tracked or introduced by this very lesson.
                guard success else { continue }
                if existing == nil {
                    guard let lessonId = exercise?.lessonId, index.tables.introducingLessonId[unitId] == lessonId else { continue }
                }
            }
            let grade = grade(for: attempt, existing: existing, skill: skill, secondary: i > 0, now: now)
            let updated = update(existing, unitId: unitId, grade: grade, success: success,
                                 hintUsed: attempt.hintUsed, skill: skill, exerciseType: attempt.exerciseType, now: now)
            learner.memoryStates[unitId] = updated
            changed.append(updated)
        }
        return changed
    }

    func grade(for attempt: AttemptRecord, existing: MemoryState?, skill: ExerciseSkill,
               secondary: Bool, now: Date, calendar: Calendar = .current) -> ReviewGrade {
        var grade: ReviewGrade
        switch attempt.result {
        case .incorrect: grade = .again
        case .partial: grade = .hard
        case .pending: grade = .again
        case .correctWithTypo: grade = attempt.hintUsed ? .hard : .good
        case .correct:
            if attempt.hintUsed {
                grade = .hard
            } else if skill == .production, let st = existing, !attempt.isRemediation,
                      !calendar.isDate(st.firstSeenAt, inSameDayAs: now), st.firstSeenAt < now {
                grade = .easy
            } else {
                grade = .good
            }
        }
        if attempt.isRemediation { grade = min(grade, .hard) }
        if secondary { grade = min(grade, .good) }
        return grade
    }

    static func skillWeight(_ skill: ExerciseSkill) -> Double {
        switch skill {
        case .recognition: return EngineTuning.recognitionWeight
        case .recall: return EngineTuning.recallWeight
        case .production: return EngineTuning.productionWeight
        }
    }

    func update(_ existing: MemoryState?, unitId: String, grade: ReviewGrade, success: Bool,
                hintUsed: Bool, skill: ExerciseSkill, exerciseType: ExerciseType, now: Date) -> MemoryState {
        let weight = Self.skillWeight(skill)
        var st: MemoryState
        var delayed = false
        var scheduled = true
        if var current = existing {
            let reference = current.lastReviewAt ?? current.firstSeenAt
            let elapsedSeconds = max(0, now.timeIntervalSince(reference))
            let r = fsrs.retrievability(elapsedDays: elapsedSeconds / 86_400, stability: current.stability)
            let rapid = current.lastReviewAt != nil && elapsedSeconds < EngineTuning.rapidRepetitionMinutes * 60
            let due = now >= current.nextReviewAt
            delayed = success && due && elapsedSeconds >= configuration.delayedSuccessHours * 3600
            if grade == .again {
                if current.successCount > 0 { current.lapseCount += 1 }
                current.stability = fsrs.failureStability(d: current.difficulty, s: current.stability, r: r)
                current.difficulty = fsrs.nextDifficulty(current.difficulty, grade)
                current.nextReviewAt = now.addingTimeInterval(interval(for: current.stability, grade: grade))
            } else if due && !rapid {
                let target = fsrs.successStability(d: current.difficulty, s: current.stability, r: r, grade: grade)
                current.stability = min(current.stability + (target - current.stability) * weight, configuration.maximumIntervalDays)
                current.difficulty = fsrs.nextDifficulty(current.difficulty, grade)
                current.nextReviewAt = now.addingTimeInterval(interval(for: current.stability, grade: grade))
            } else {
                // Early or rapid repetition: only the counters move. Stability grows at due reviews (spacing effect).
                scheduled = false
            }
            st = current
        } else {
            let s0 = fsrs.initialStability(grade)
            let base = fsrs.initialStability(.again)
            let stability = grade == .again ? s0 : base + (s0 - base) * weight
            st = MemoryState(unitId: unitId, stability: stability, difficulty: fsrs.initialDifficulty(grade),
                             source: .lesson, firstSeenAt: now,
                             nextReviewAt: now.addingTimeInterval(interval(for: stability, grade: grade)))
        }
        st.reviewCount += 1
        if success {
            st.successCount += 1
            if !hintUsed { st.noHintSuccessCount += 1 }
            if delayed { st.delayedSuccessCount += 1 }
            if skill == .production { st.productionSuccessCount += 1 }
            st.successfulExerciseTypes.insert(exerciseType)
        } else {
            st.failureCount += 1
        }
        st.recentResults.append(success)
        let limit = max(configuration.recentResultsLimit, 1)
        if st.recentResults.count > limit { st.recentResults.removeFirst(st.recentResults.count - limit) }
        if scheduled { st.lastReviewAt = now }
        st.updatedAt = now
        return st
    }

    /// Seconds until the next review.
    func interval(for stability: Double, grade: ReviewGrade) -> TimeInterval {
        let minHours = grade == .again ? EngineTuning.minIntervalAfterFailureHours : EngineTuning.minIntervalAfterSuccessHours
        let days = min(max(fsrs.interval(stability: stability), minHours / 24), configuration.maximumIntervalDays)
        return days * 86_400
    }
}

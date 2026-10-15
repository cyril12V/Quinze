import Foundation

extension SessionRunner {
    static func makeInitial(plan: SessionPlan, startedAt: Date) -> (items: [SessionItem], position: Int) {
        (plan.items, 0)
    }

    /// Presentation of a remediation item: the most guided one the exercise type allows.
    static func guidedPresentation(for exercise: Exercise) -> PresentationMode {
        switch exercise.type {
        case .mcq: return .choices
        case .match: return .pairs
        case .reorder: return .tokens
        case .fillBlank: return exercise.options != nil ? .choices : .typed
        case .translation, .freeAnswer: return .typed
        }
    }

    func buildSummary(engine: LearningEngine, now: Date) -> SessionSummary {
        var roleByExercise: [String: ItemRole] = [:]
        for item in items {
            if let id = item.exerciseId, roleByExercise[id] == nil { roleByExercise[id] = item.role }
        }
        var worked: [String] = []
        var seenUnits = Set<String>()
        var reviews = 0, correct = 0
        var errors: [ImportantError] = []
        var seenErrors = Set<String>()
        for a in attempts {
            for u in a.unitIds where seenUnits.insert(u).inserted { worked.append(u) }
            if a.result.countsAsSuccess { correct += 1 }
            if !a.isRemediation, let role = roleByExercise[a.exerciseId], role == .oldReview || role == .recentReview { reviews += 1 }
            if a.result == .incorrect, errors.count < 5, seenErrors.insert(a.exerciseId).inserted,
               let ex = engine.exercise(a.exerciseId) {
                errors.append(ImportantError(exerciseId: ex.id, unitId: ex.primaryUnitId, prompt: ex.prompt, expected: ex.answer,
                                             given: a.submittedAnswer, category: a.errorCategory))
            }
        }
        let graded = attempts.filter { $0.result != .pending }.count
        let score: Double? = plan.type == .assessment ? (graded == 0 ? 0 : Double(correct) / Double(graded)) : nil
        return SessionSummary(sessionId: plan.id, type: plan.type, slot: plan.slot, lessonId: plan.lessonId,
                              unitIdsWorked: worked, newUnitIds: plan.newUnitIds, reviewCount: reviews,
                              attemptCount: attempts.count, correctCount: correct, importantErrors: errors,
                              durationSeconds: max(0, now.timeIntervalSince(startedAt)), score: score)
    }
}

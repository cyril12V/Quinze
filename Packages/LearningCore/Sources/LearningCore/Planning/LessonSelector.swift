import Foundation

/// Lesson progression and prerequisites (docs/05-moteur-pedagogique.md, "Choix de la leçon").
struct LessonSelector {
    let engine: LearningEngine

    private var index: ContentIndex { engine.index }

    func isDone(_ lesson: Lesson, _ learner: LearnerSnapshot) -> Bool {
        learner.completedLessonIds.contains(lesson.id) || learner.placedLessonIds.contains(lesson.id)
    }

    /// First lesson of the sequence that is neither completed nor placed.
    func firstPending(_ learner: LearnerSnapshot) -> Lesson? {
        index.lessonsInOrder.first { !isDone($0, learner) }
    }

    /// Units that must be sufficiently mastered before the lesson: prerequisites of its notion, and the notion
    /// itself for a practice lesson (which does not introduce it).
    func prerequisites(of lesson: Lesson) -> [String] {
        guard let grammar = index.unitsById[lesson.grammarUnitId] else { return [] }
        var ids = grammar.prerequisites
        if !lesson.introducesGrammar { ids.append(lesson.grammarUnitId) }
        var seen = Set<String>()
        return ids.filter { index.unitsById[$0] != nil && seen.insert($0).inserted }
    }

    /// A prerequisite is satisfied when it is mastered enough, studied for long enough (anti-blocking bypass), or
    /// presumed known by the diagnostic and not yet contradicted.
    func isSatisfied(_ unitId: String, learner: LearnerSnapshot, now: Date) -> Bool {
        guard let state = learner.memoryStates[unitId] else {
            // Never tracked but taught by a lesson that is done: nothing more can be asked of the learner.
            if let lessonId = index.tables.introducingLessonId[unitId] {
                return learner.completedLessonIds.contains(lessonId) || learner.placedLessonIds.contains(lessonId)
            }
            return false
        }
        if engine.masteryCalculator.score(state) >= engine.configuration.prerequisiteMasteryThreshold { return true }
        if now.timeIntervalSince(state.firstSeenAt) >= Double(engine.configuration.prerequisiteBypassDays) * 86_400 { return true }
        if state.source == .diagnostic && state.failureCount == 0 { return true }
        return false
    }

    /// Unsatisfied prerequisites, weakest first.
    func blockers(of lesson: Lesson, learner: LearnerSnapshot, now: Date) -> [(unitId: String, score: Double)] {
        let calc = engine.masteryCalculator
        return prerequisites(of: lesson)
            .filter { !isSatisfied($0, learner: learner, now: now) }
            .map { id in (id, learner.memoryStates[id].map { calc.score($0) } ?? 0) }
            .sorted { ($0.score, $0.unitId) < ($1.score, $1.unitId) }
    }

    /// The first module whose lessons are all done (at least one really studied) but whose exam is not passed,
    /// when a later lesson is waiting for it. Modules skipped by the placement test need no exam.
    func moduleAwaitingExam(_ learner: LearnerSnapshot) -> Int? {
        let modules = Array(Set(index.lessonsInOrder.map { $0.module })).sorted()
        for module in modules where !learner.passedModules.contains(module) {
            let lessons = index.lessonsInOrder.filter { $0.module == module }
            guard !lessons.isEmpty else { continue }
            if !lessons.allSatisfy({ isDone($0, learner) }) { return nil }
            if lessons.allSatisfy({ learner.placedLessonIds.contains($0.id) }) { continue }
            return module
        }
        return nil
    }

    func nextLesson(_ learner: LearnerSnapshot, now: Date) -> Lesson? {
        index.lessonsInOrder.first { !isDone($0, learner) && blockers(of: $0, learner: learner, now: now).isEmpty }
    }
}

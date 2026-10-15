import Foundation

/// Helpers of the adaptive placement test (docs/05-moteur-pedagogique.md, "Diagnostic et placement").
enum DiagnosticSupport {
    static let labels = ["Débutant", "Premières bases", "Bases acquises", "Élémentaire", "Pré-intermédiaire"]

    static func label(for level: Int) -> String { labels[min(max(level, 0), labels.count - 1)] }

    /// Highest level with at least 60 % of correct answers over at least 2 questions asked at that level.
    static func estimate(_ answers: [DiagnosticAnswer]) -> Int {
        for level in stride(from: 4, through: 0, by: -1) {
            let atLevel = answers.filter { $0.level == level }
            if atLevel.count >= 2, Double(atLevel.filter { $0.correct }.count) / Double(atLevel.count) >= 0.6 { return level }
        }
        return 0
    }

    /// Level stable over the last four answers: they were asked within one level of each other.
    static func isStable(_ answers: [DiagnosticAnswer]) -> Bool {
        let last = answers.suffix(4)
        guard last.count == 4, let lo = last.map({ $0.level }).min(), let hi = last.map({ $0.level }).max() else { return false }
        return hi - lo <= 1
    }
}

extension LearningEngine {
    func makeDiagnosticImpl(selfAssessed: SelfAssessedLevel, seed: UInt64) -> DiagnosticSession {
        DiagnosticSession(startLevel: selfAssessed.rawValue, maxQuestions: configuration.diagnosticMaxQuestions,
                          minQuestions: configuration.diagnosticMinQuestions, seed: seed)
    }

    /// Start lesson of a level: the first lesson of module `level + 1` (or the last lesson when the content is shorter).
    func startLesson(forLevel level: Int) -> Lesson? {
        let lessons = index.lessonsInOrder
        guard !lessons.isEmpty else { return nil }
        if level <= 0 { return lessons.first }
        return lessons.first { $0.module >= level + 1 } ?? lessons.last
    }

    func diagnosticResult(for session: DiagnosticSession) -> DiagnosticResult {
        let level = DiagnosticSupport.estimate(session.answers)
        let start = startLesson(forLevel: level)
        let lessons = index.lessonsInOrder
        let startPosition = start.flatMap { s in lessons.firstIndex { $0.id == s.id } } ?? 0
        let placed = Array(lessons.prefix(startPosition))
        var known: [String] = []
        var seen = Set<String>()
        for lesson in placed {
            for u in lesson.introduces where index.unitsById[u]?.deprecated != true && seen.insert(u).inserted { known.append(u) }
        }
        var topicCounts: [String: (Int, Int)] = [:]
        for a in session.answers {
            var e = topicCounts[a.topic] ?? (0, 0)
            e.0 += 1
            if a.correct { e.1 += 1 }
            topicCounts[a.topic] = e
        }
        var topicScores: [String: Double] = [:]
        for (t, e) in topicCounts { topicScores[t] = Double(e.1) / Double(max(e.0, 1)) }
        return DiagnosticResult(estimatedLevel: level, levelLabel: DiagnosticSupport.label(for: level),
                                startLessonId: start?.id ?? "", placedLessonIds: placed.map { $0.id },
                                knownUnitIds: known, answers: session.answers, topicScores: topicScores)
    }

    func applyPlacementImpl(_ result: DiagnosticResult, to learner: inout LearnerSnapshot, now: Date) -> [MemoryState] {
        learner.estimatedLevel = result.estimatedLevel
        learner.placedLessonIds.formUnion(result.placedLessonIds)
        if learner.startedAt == nil { learner.startedAt = now }
        // Verify the most advanced placed content first; at most `placementChecksPerDay` checks per day.
        var order: [String] = []
        var seen = Set<String>()
        for lessonId in result.placedLessonIds.reversed() {
            guard let lesson = index.lessonsById[lessonId] else { continue }
            for u in lesson.introduces where result.knownUnitIds.contains(u) && seen.insert(u).inserted { order.append(u) }
        }
        for u in result.knownUnitIds where seen.insert(u).inserted { order.append(u) }
        var created: [MemoryState] = []
        var position = 0
        for unitId in order where learner.memoryStates[unitId] == nil && index.unitsById[unitId] != nil {
            let dayOffset = position / EngineTuning.placementChecksPerDay + 1
            let due = now.addingTimeInterval(Double(dayOffset) * 86_400 + Double(position % EngineTuning.placementChecksPerDay) * 60)
            let state = MemoryState(unitId: unitId, stability: EngineTuning.placementStability,
                                    difficulty: EngineTuning.placementDifficulty, source: .diagnostic,
                                    firstSeenAt: now, nextReviewAt: due)
            learner.memoryStates[unitId] = state
            created.append(state)
            position += 1
        }
        return created
    }
}

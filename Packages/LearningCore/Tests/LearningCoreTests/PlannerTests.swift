import XCTest
@testable import LearningCore

final class PlannerTests: XCTestCase {
    var engine: LearningEngine!
    let now = TestSupport.date(day: 0, hour: 9)
    let day0 = TestSupport.day(0)

    override func setUpWithError() throws { engine = try TestSupport.fixtureEngine() }

    private func exerciseIds(_ plan: SessionPlan) -> [String] { plan.items.compactMap { $0.exerciseId } }

    private func assertWellFormed(_ plan: SessionPlan, file: StaticString = #filePath, line: UInt = #line) {
        let ids = exerciseIds(plan)
        XCTAssertGreaterThanOrEqual(ids.count, 8, "too few exercises", file: file, line: line)
        XCTAssertLessThanOrEqual(ids.count, 12, "too many exercises", file: file, line: line)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate exercise in a session", file: file, line: line)
        for id in ids { XCTAssertNotNil(engine.exercise(id), file: file, line: line) }
        XCTAssertGreaterThan(plan.estimatedSeconds, 0, file: file, line: line)
    }

    // MARK: Learning session

    func testFirstLearningSessionIntroducesLessonOne() {
        let plan = engine.planSession(type: .learning, slot: .morning, day: day0, learner: .empty, now: now, seed: 1)
        XCTAssertEqual(plan.type, .learning)
        XCTAssertEqual(plan.slot, .morning)
        XCTAssertEqual(plan.lessonId, "en.l01")
        XCTAssertEqual(plan.newUnitIds, engine.lesson("en.l01")!.introduces)
        assertWellFormed(plan)
        // rule card first (grammar introduction), then the word cards, then the exercises
        XCTAssertEqual(plan.items.first?.kind, .ruleCard(unitId: "en.g01.be"))
        XCTAssertEqual(plan.items.first?.role, .newMaterial)
        let words = plan.items.compactMap { item -> String? in if case .wordCard(let u) = item.kind { return u } else { return nil } }
        XCTAssertEqual(Set(words), Set(engine.lesson("en.l01")!.introduces.filter { engine.unit($0)?.kind == .vocabulary }))
        let firstExercise = plan.items.firstIndex { $0.exerciseId != nil }!
        XCTAssertTrue(plan.items[..<firstExercise].allSatisfy { $0.exerciseId == nil })
        // exercises are those of the lesson, from the most guided to the most demanding, and cover the new units
        let exercises = exerciseIds(plan).compactMap { engine.exercise($0) }
        XCTAssertTrue(exercises.allSatisfy { $0.lessonId == "en.l01" })
        var covered = Set<String>()
        for e in exercises { covered.formUnion(e.unitIds) }
        XCTAssertTrue(Set(plan.newUnitIds).isSubset(of: covered), "uncovered: \(Set(plan.newUnitIds).subtracting(covered))")
        let rank: [ExerciseType: Int] = [.match: 0, .mcq: 1, .fillBlank: 2, .reorder: 3, .translation: 4, .freeAnswer: 5]
        let keys = exercises.map { (rank[$0.type]!, $0.difficulty) }
        XCTAssertEqual(keys.map { $0.0 }, keys.map { $0.0 }.sorted())
        // adaptive presentation: new notions are guided (word bank), with a hint available
        for item in plan.items where item.exerciseId != nil {
            XCTAssertTrue(item.hintAllowed || item.role == .activeRecall)
            if let ex = item.exerciseId.flatMap({ engine.exercise($0) }), ex.type == .fillBlank { XCTAssertEqual(item.presentation, .choices) }
        }
    }

    func testFirstSessionOfTheDayTeachesWhateverTheSlot() {
        for (type, slot) in [(SessionType.application, SessionSlot.afternoon), (.consolidation, .evening)] {
            let plan = engine.planSession(type: type, slot: slot, day: day0, learner: .empty, now: now, seed: 2)
            XCTAssertEqual(plan.type, .learning, "\(slot)")
            XCTAssertEqual(plan.lessonId, "en.l01")
            XCTAssertEqual(plan.slot, slot)
        }
    }

    func testPlanIsDeterministicPerSeed() {
        let a = engine.planSession(type: .learning, slot: .morning, day: day0, learner: .empty, now: now, seed: 99)
        let b = engine.planSession(type: .learning, slot: .morning, day: day0, learner: .empty, now: now, seed: 99)
        XCTAssertEqual(a, b)
        let c = engine.planSession(type: .learning, slot: .morning, day: day0, learner: .empty, now: now, seed: 100)
        XCTAssertNotEqual(a.id, c.id)
        assertWellFormed(c)
        // also after some history
        var sim = Simulator(engine: engine, base: 1, gain: 0)
        sim.run(day: 0, slot: .morning, answerAll: true)
        let d1 = engine.planSession(type: .application, slot: .afternoon, day: day0, learner: sim.learner, now: TestSupport.date(day: 0, hour: 14), seed: 5)
        let d2 = engine.planSession(type: .application, slot: .afternoon, day: day0, learner: sim.learner, now: TestSupport.date(day: 0, hour: 14), seed: 5)
        XCTAssertEqual(d1, d2)
    }

    func testSecondDayMixesReviewsRecentAndNewLesson() {
        var sim = Simulator(engine: engine, base: 1, gain: 0)
        sim.run(day: 0, slot: .morning, answerAll: true)
        sim.run(day: 0, slot: .afternoon, answerAll: true)
        sim.run(day: 0, slot: .evening, answerAll: true)
        let now1 = TestSupport.date(day: 1, hour: 9)
        let plan = engine.planSession(type: .learning, slot: .morning, day: TestSupport.day(1), learner: sim.learner, now: now1, seed: 3)
        XCTAssertEqual(plan.lessonId, "en.l02")
        assertWellFormed(plan)
        let roles = plan.items.filter { $0.exerciseId != nil }.map { $0.role }
        XCTAssertTrue(roles.contains(.oldReview) || roles.contains(.activeRecall), "\(roles)")
        XCTAssertTrue(roles.contains(.newMaterial))
        // reviewed exercises concern the previous lesson only
        for item in plan.items where item.role == .oldReview || item.role == .activeRecall {
            let ex = engine.exercise(item.exerciseId!)!
            XCTAssertTrue(ex.lessonId == "en.l01" || ex.lessonId == "en.l02")
        }
        // active recall is production without hint
        for item in plan.items where item.role == .activeRecall {
            XCTAssertFalse(item.hintAllowed)
            XCTAssertEqual(item.presentation, .typed)
        }
    }

    // MARK: Application / consolidation

    func testApplicationAndConsolidationDifferWithinADay() {
        var sim = Simulator(engine: engine, base: 1, gain: 0)
        sim.run(day: 0, slot: .morning, answerAll: true)
        let t = TestSupport.date(day: 0, hour: 14)
        let afternoon = engine.planSession(type: .application, slot: .afternoon, day: day0, learner: sim.learner, now: t, seed: 11)
        let evening = engine.planSession(type: .consolidation, slot: .evening, day: day0, learner: sim.learner,
                                         now: TestSupport.date(day: 0, hour: 20), seed: 11)
        XCTAssertEqual(afternoon.type, .application)
        XCTAssertEqual(evening.type, .consolidation)
        assertWellFormed(afternoon)
        assertWellFormed(evening)
        XCTAssertNil(afternoon.lessonId)
        XCTAssertTrue(afternoon.items.allSatisfy { $0.exerciseId != nil })
        // consolidation: no hint at all
        XCTAssertTrue(evening.items.allSatisfy { !$0.hintAllowed })
        XCTAssertNotEqual(afternoon.items.map { $0.hintAllowed }, evening.items.map { $0.hintAllowed })
        // exercises already answered in the morning are avoided as long as the pool allows it
        let morning = Set(sim.records[0].exerciseIds)
        let fresh = exerciseIds(afternoon).filter { !morning.contains($0) }
        XCTAssertGreaterThanOrEqual(fresh.count, engine.index.tables.exercisesByLesson["en.l01"]!.count - morning.count)
    }

    func testFocusedPractice() {
        var sim = Simulator(engine: engine, base: 1, gain: 0)
        for d in 0..<2 { sim.runDay(d) }
        let plan = engine.planFocusedPractice(unitId: "en.g01.be", day: TestSupport.day(2), learner: sim.learner,
                                              now: TestSupport.date(day: 2, hour: 11), seed: 4)
        XCTAssertEqual(plan.type, .extra)
        XCTAssertEqual(plan.items.first?.kind, .ruleCard(unitId: "en.g01.be"))
        let ids = exerciseIds(plan)
        XCTAssertTrue((6...8).contains(ids.count), "\(ids.count)")
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids.compactMap { engine.exercise($0) }.allSatisfy { $0.unitIds.contains("en.g01.be") })
        // a word: word card first
        let word = engine.planFocusedPractice(unitId: "en.v.teacher", day: TestSupport.day(2), learner: sim.learner,
                                              now: TestSupport.date(day: 2, hour: 11), seed: 4)
        XCTAssertEqual(word.items.first?.kind, .wordCard(unitId: "en.v.teacher"))
    }

    // MARK: Prerequisites and overdue flood

    private func state(_ unit: String, stability: Double = 2, firstSeen: Date, successes: Int = 0, next: Date? = nil,
                       production: Int = 0, delayed: Int = 0, results: [Bool] = []) -> MemoryState {
        MemoryState(unitId: unit, stability: stability, difficulty: 5, source: .lesson, firstSeenAt: firstSeen, nextReviewAt: next ?? firstSeen.addingTimeInterval(86_400),
                    reviewCount: successes, successCount: successes, noHintSuccessCount: successes, delayedSuccessCount: delayed,
                    productionSuccessCount: production, successfulExerciseTypes: production > 0 ? [.translation, .mcq, .fillBlank] : [.mcq],
                    recentResults: results, lastReviewAt: firstSeen)
    }

    func testPrerequisiteBlocksThenBypass() {
        var learner = LearnerSnapshot()
        learner.completedLessonIds = ["en.l01"]
        // g01 studied yesterday, weak -> lesson 2 (prerequisite g01) is blocked
        learner.memoryStates["en.g01.be"] = state("en.g01.be", firstSeen: now.addingTimeInterval(-86_400), successes: 1, results: [true, false, false])
        XCTAssertNil(engine.nextLesson(for: learner, now: now))
        // the planner inserts the remediation of the weak prerequisite instead of a new lesson
        let plan = engine.planSession(type: .learning, slot: .morning, day: day0, learner: learner, now: now, seed: 8)
        XCTAssertNil(plan.lessonId)
        XCTAssertTrue(plan.newUnitIds.isEmpty)
        XCTAssertEqual(plan.items.first?.kind, .ruleCard(unitId: "en.g01.be"))
        assertWellFormed(plan)
        XCTAssertTrue(exerciseIds(plan).compactMap { engine.exercise($0) }.allSatisfy { $0.unitIds.contains("en.g01.be") || $0.lessonId == "en.l01" })
        // mastered enough: lesson 2 is next
        var good = learner
        good.memoryStates["en.g01.be"] = state("en.g01.be", stability: 25, firstSeen: now.addingTimeInterval(-86_400), successes: 6, production: 2, delayed: 2, results: [true, true, true, true])
        XCTAssertEqual(engine.nextLesson(for: good, now: now)?.id, "en.l02")
        // bypass: still weak but studied for prerequisiteBypassDays
        var bypass = learner
        bypass.memoryStates["en.g01.be"] = state("en.g01.be", firstSeen: now.addingTimeInterval(-6 * 86_400), successes: 1, results: [true, false, false])
        XCTAssertEqual(engine.nextLesson(for: bypass, now: now)?.id, "en.l02")
        let planned = engine.planSession(type: .learning, slot: .morning, day: day0, learner: bypass, now: now, seed: 8)
        XCTAssertEqual(planned.lessonId, "en.l02")
        // presumed known by the diagnostic and not contradicted: no block either
        var placed = LearnerSnapshot()
        placed.placedLessonIds = ["en.l01"]
        var diag = state("en.g01.be", firstSeen: now.addingTimeInterval(-3600))
        diag.source = .diagnostic
        placed.memoryStates["en.g01.be"] = diag
        XCTAssertEqual(engine.nextLesson(for: placed, now: now)?.id, "en.l02")
        // ... until the unit fails a check
        diag.failureCount = 1
        placed.memoryStates["en.g01.be"] = diag
        XCTAssertNil(engine.nextLesson(for: placed, now: now))
        // a prerequisite never studied blocks (its lesson is not done)
        XCTAssertEqual(engine.nextLesson(for: .empty, now: now)?.id, "en.l01")
    }

    func testOverdueFloodPausesNewMaterial() {
        var config = EngineConfiguration.default
        config.overdueThresholdToPauseNewMaterial = 4
        let e = LearningEngine(index: engine.index, configuration: config)
        var learner = LearnerSnapshot()
        learner.completedLessonIds = ["en.l01", "en.l02"]
        let past = now.addingTimeInterval(-10 * 86_400)
        for u in ["en.g01.be", "en.g02.present_simple", "en.v.teacher", "en.v.student", "en.v.go", "en.v.eat"] {
            learner.memoryStates[u] = state(u, stability: 6, firstSeen: past, successes: 2, next: now.addingTimeInterval(-3 * 86_400), results: [true, true])
        }
        let plan = e.planSession(type: .learning, slot: .morning, day: day0, learner: learner, now: now, seed: 5)
        XCTAssertNil(plan.lessonId, "no new lesson while reviews are overdue")
        XCTAssertTrue(plan.newUnitIds.isEmpty)
        XCTAssertTrue(plan.items.allSatisfy { if case .wordCard = $0.kind { return false } else { return true } })
        XCTAssertFalse(plan.items.contains { $0.role == .newMaterial })
        let old = Double(plan.items.filter { $0.role == .oldReview }.count)
        let total = Double(plan.items.count)
        XCTAssertGreaterThanOrEqual(old, total * 0.3)
        XCTAssertLessThanOrEqual(old, total * 0.6)
        // with few overdue reviews the lesson is taught
        var calm = learner
        for u in Array(calm.memoryStates.keys) { calm.memoryStates[u]!.nextReviewAt = now.addingTimeInterval(86_400) }
        XCTAssertEqual(e.planSession(type: .learning, slot: .morning, day: day0, learner: calm, now: now, seed: 5).lessonId, "en.l03")
    }

    // MARK: Adaptation

    func testStrugglingLearnerGetsFewerNewWords() {
        var learner = LearnerSnapshot()
        let t = now.addingTimeInterval(-3600)
        var attempts: [AttemptRecord] = []
        for i in 0..<20 {
            let ok = i % 4 == 0
            let result: AttemptResult = ok ? .correct : .incorrect
            let category: ErrorCategory? = ok ? nil : .conjugation
            attempts.append(AttemptRecord(exerciseId: "en.l01.e05", sessionId: nil, unitIds: ["en.g01.be"], exerciseType: .translation,
                                          presentation: .typed, submittedAnswer: "x", result: result, errorCategory: category,
                                          hintUsed: false, isRemediation: false, durationSeconds: 5,
                                          answeredAt: t.addingTimeInterval(Double(i))))
        }
        learner.recentAttempts = attempts
        let plan = engine.planSession(type: .learning, slot: .morning, day: day0, learner: learner, now: now, seed: 6)
        let words = plan.items.filter { if case .wordCard = $0.kind { return true } else { return false } }.count
        XCTAssertEqual(words, 3)
        assertWellFormed(plan)
        // gaps: conjugation is a weak category in the progress report
        XCTAssertEqual(engine.progress(learner: learner, now: now).weakErrorCategories.first?.category, .conjugation)
    }

    // MARK: Assessment

    func testAssessmentPlanning() {
        var learner = LearnerSnapshot()
        XCTAssertFalse(engine.isAssessmentDue(learner: learner, now: now))
        var sim = Simulator(engine: engine, base: 1, gain: 0)
        for d in 0..<3 { sim.runDay(d, assessmentIfDue: false) }
        learner = sim.learner
        let t13 = TestSupport.date(day: 13, hour: 20)
        let t15 = TestSupport.date(day: 15, hour: 20)
        XCTAssertFalse(engine.isAssessmentDue(learner: learner, now: t13))
        XCTAssertTrue(engine.isAssessmentDue(learner: learner, now: t15))
        learner.lastAssessmentAt = TestSupport.date(day: 14, hour: 20)
        XCTAssertFalse(engine.isAssessmentDue(learner: learner, now: t15))
        let plan = engine.planAssessment(day: TestSupport.day(15), learner: learner, now: t15, seed: 3)
        XCTAssertEqual(plan.type, .assessment)
        let ids = exerciseIds(plan)
        XCTAssertEqual(ids.count, engine.configuration.assessmentQuestionCount)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(plan.items.allSatisfy { $0.role == .assessment && !$0.hintAllowed })
        XCTAssertTrue(ids.contains { engine.exercise($0)?.pool == .assessment })
        // planSession(.assessment) is the same thing
        XCTAssertEqual(engine.planSession(type: .assessment, slot: nil, day: TestSupport.day(15), learner: learner, now: t15, seed: 3), plan)
    }

    func testSimilarExercise() {
        let id = "en.l02.e01"
        var learner = LearnerSnapshot()
        learner.completedLessonIds = ["en.l01"]
        let similar = engine.similarExercise(to: id, learner: learner, excluding: [], seed: 1)!
        XCTAssertNotEqual(similar.id, id)
        XCTAssertEqual(similar.primaryUnitId, "en.g02.present_simple")
        XCTAssertEqual(similar.lessonId, "en.l02")
        var excluded = Set<String>()
        var seen = Set<String>()
        while let next = engine.similarExercise(to: id, learner: learner, excluding: excluded, seed: 1) {
            XCTAssertTrue(seen.insert(next.id).inserted)
            excluded.insert(next.id)
        }
        XCTAssertGreaterThanOrEqual(seen.count, 5)
        XCTAssertEqual(engine.similarExercise(to: id, learner: learner, excluding: [], seed: 1)?.id,
                       engine.similarExercise(to: id, learner: learner, excluding: [], seed: 1)?.id)
        XCTAssertNil(engine.similarExercise(to: "nope", learner: learner, excluding: [], seed: 1))
    }
}

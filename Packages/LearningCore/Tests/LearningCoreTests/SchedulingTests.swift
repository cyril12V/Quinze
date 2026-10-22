import XCTest
@testable import LearningCore

final class SchedulingTests: XCTestCase {
    var engine: LearningEngine!
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 86_400

    override func setUpWithError() throws { engine = try TestSupport.fixtureEngine() }

    private func attempt(_ id: String, _ result: AttemptResult, hint: Bool = false, remediation: Bool = false,
                         at: Date, sessionId: UUID? = nil) -> AttemptRecord {
        let ex = engine.exercise(id)!
        return AttemptRecord(exerciseId: id, sessionId: sessionId, unitIds: ex.unitIds, exerciseType: ex.type, presentation: .typed,
                             submittedAnswer: "x", result: result, errorCategory: result.countsAsSuccess ? nil : .grammar,
                             hintUsed: hint, isRemediation: remediation, durationSeconds: 10, answeredAt: at)
    }

    // MARK: FSRS numbers (computed independently with python3)

    func testFSRSFormulas() {
        let f = FSRS(configuration: .default)
        XCTAssertEqual(f.initialStability(.again), 0.4872, accuracy: 1e-9)
        XCTAssertEqual(f.initialStability(.good), 3.7145, accuracy: 1e-9)
        XCTAssertEqual(f.initialStability(.easy), 13.8206, accuracy: 1e-9)
        XCTAssertEqual(f.initialDifficulty(.again), 7.6214, accuracy: 1e-9)
        XCTAssertEqual(f.initialDifficulty(.good), 5.1618, accuracy: 1e-9)
        XCTAssertEqual(f.initialDifficulty(.easy), 3.932, accuracy: 1e-9)
        XCTAssertEqual(f.retrievability(elapsedDays: 10, stability: 10), 0.9, accuracy: 1e-12)
        XCTAssertEqual(f.retrievability(elapsedDays: 1, stability: 3.7145), 0.9698462273634281, accuracy: 1e-9)
        XCTAssertEqual(f.interval(stability: 3.7145), 3.7145, accuracy: 1e-9)
        var strict = EngineConfiguration.default
        strict.desiredRetention = 0.8
        XCTAssertEqual(FSRS(configuration: strict).interval(stability: 10), 23.98026315789473, accuracy: 1e-9)
        var capped = EngineConfiguration.default
        capped.maximumIntervalDays = 5
        XCTAssertEqual(FSRS(configuration: capped).interval(stability: 100), 5, accuracy: 1e-12)
        XCTAssertEqual(f.nextDifficulty(5.1618, .again), 6.901155, accuracy: 1e-9)
        XCTAssertEqual(f.nextDifficulty(5.1618, .good), 5.1618, accuracy: 1e-9)
        XCTAssertEqual(f.nextDifficulty(5.1618, .easy), 4.2921225, accuracy: 1e-9)
        XCTAssertEqual(f.nextDifficulty(8, .hard), 8.7816933, accuracy: 1e-9)
        XCTAssertEqual(f.successStability(d: 5.1618, s: 3.7145, r: 0.9, grade: .good), 14.094985421450287, accuracy: 1e-6)
        XCTAssertEqual(f.successStability(d: 5.1618, s: 3.7145, r: 0.9, grade: .hard), 6.072946287753505, accuracy: 1e-6)
        XCTAssertEqual(f.successStability(d: 5.1618, s: 3.7145, r: 0.9, grade: .easy), 33.5635858293803, accuracy: 1e-6)
        XCTAssertEqual(f.successStability(d: 5.1618, s: 3.7145, r: 0.5, grade: .good), 68.39779468577994, accuracy: 1e-6)
        XCTAssertEqual(f.failureStability(d: 5.1618, s: 3.7145, r: 0.9), 1.418524828653778, accuracy: 1e-6)
        XCTAssertEqual(f.failureStability(d: 5.1618, s: 3.7145, r: 0.5), 2.676252455858852, accuracy: 1e-6)
        XCTAssertEqual(f.failureStability(d: 5, s: 10, r: 0.7), 3.5168188990421068, accuracy: 1e-6)
    }

    // MARK: Memory updates

    func testFirstExposureCreatesState() {
        var learner = LearnerSnapshot()
        // translation (production), no hint, correct -> Good, weight 1
        let changed = engine.apply(attempt("en.l01.e05", .correct, at: t0), to: &learner, now: t0)
        let g = learner.memoryStates["en.g01.be"]!
        XCTAssertEqual(g.stability, 3.7145, accuracy: 1e-9)
        XCTAssertEqual(g.difficulty, 5.1618, accuracy: 1e-9)
        XCTAssertEqual(g.nextReviewAt.timeIntervalSince(t0), 3.7145 * day, accuracy: 1)
        XCTAssertEqual(g.reviewCount, 1); XCTAssertEqual(g.successCount, 1); XCTAssertEqual(g.productionSuccessCount, 1)
        XCTAssertEqual(g.noHintSuccessCount, 1); XCTAssertEqual(g.delayedSuccessCount, 0)
        XCTAssertEqual(g.successfulExerciseTypes, [.translation]); XCTAssertEqual(g.recentResults, [true])
        XCTAssertEqual(g.source, .lesson)
        // en.l01.e05 units: g01 + v.tired (introduced by lesson l01): created too, as a secondary unit
        XCTAssertNotNil(learner.memoryStates["en.v.tired"])
        XCTAssertEqual(Set(changed.map { $0.unitId }), ["en.g01.be", "en.v.tired"])
        XCTAssertEqual(learner.recentAttempts.count, 1)
    }

    func testGradesHintPartialFailureAndRemediation() {
        func fresh(_ r: AttemptResult, hint: Bool = false, remediation: Bool = false, id: String = "en.l01.e05") -> MemoryState {
            var l = LearnerSnapshot()
            engine.apply(attempt(id, r, hint: hint, remediation: remediation, at: t0), to: &l, now: t0)
            return l.memoryStates["en.g01.be"]!
        }
        // Again: S0(1)=0.4872, D0(1)=7.6214, 0 success
        let again = fresh(.incorrect)
        XCTAssertEqual(again.stability, 0.4872, accuracy: 1e-9)
        XCTAssertEqual(again.difficulty, 7.6214, accuracy: 1e-9)
        XCTAssertEqual(again.failureCount, 1); XCTAssertEqual(again.recentResults, [false])
        XCTAssertEqual(again.nextReviewAt.timeIntervalSince(t0), 0.4872 * day, accuracy: 1)
        // Hard (hint): S0(2)=1.4003
        let hard = fresh(.correct, hint: true)
        XCTAssertEqual(hard.stability, 1.4003, accuracy: 1e-9)
        XCTAssertEqual(hard.noHintSuccessCount, 0)
        // partial -> Hard but not a success
        let partial = fresh(.partial)
        XCTAssertEqual(partial.stability, 1.4003, accuracy: 1e-9)
        XCTAssertEqual(partial.successCount, 0); XCTAssertEqual(partial.failureCount, 1)
        // typo -> Good
        XCTAssertEqual(fresh(.correctWithTypo).stability, 3.7145, accuracy: 1e-9)
        // remediation capped at Hard
        XCTAssertEqual(fresh(.correct, remediation: true).stability, 1.4003, accuracy: 1e-9)
        // recognition weight 0.5: 0.4872 + (3.7145 - 0.4872) * 0.5 ; recall weight 0.8
        XCTAssertEqual(fresh(.correct, id: "en.l01.e01").stability, 0.4872 + (3.7145 - 0.4872) * 0.5, accuracy: 1e-9)
        XCTAssertEqual(fresh(.correct, id: "en.l01.e04").stability, 0.4872 + (3.7145 - 0.4872) * 0.8, accuracy: 1e-9)
        // pending: recorded, no scheduling
        var l = LearnerSnapshot()
        let changed = engine.apply(attempt("en.l01.e05", .pending, at: t0), to: &l, now: t0)
        XCTAssertTrue(changed.isEmpty); XCTAssertTrue(l.memoryStates.isEmpty); XCTAssertEqual(l.recentAttempts.count, 1)
    }

    func testSecondReviewFollowsFSRS() {
        var learner = LearnerSnapshot()
        engine.apply(attempt("en.l01.e05", .correct, at: t0), to: &learner, now: t0)
        let t1 = t0.addingTimeInterval(3.7145 * day)           // R = 0.9
        var good = learner
        engine.apply(attempt("en.l01.e05", .correctWithTypo, at: t1), to: &good, now: t1)   // Good, production weight 1
        XCTAssertEqual(good.memoryStates["en.g01.be"]!.stability, 14.094985421450287, accuracy: 1e-6)
        XCTAssertEqual(good.memoryStates["en.g01.be"]!.delayedSuccessCount, 1)
        XCTAssertEqual(good.memoryStates["en.g01.be"]!.lapseCount, 0)
        var easy = learner       // production, no hint, unit first seen on an earlier day -> Easy
        engine.apply(attempt("en.l01.e05", .correct, at: t1), to: &easy, now: t1)
        XCTAssertEqual(easy.memoryStates["en.g01.be"]!.stability, 33.5635858293803, accuracy: 1e-6)
        var recog = learner      // recognition weight 0.5
        engine.apply(attempt("en.l01.e01", .correct, at: t1), to: &recog, now: t1)
        XCTAssertEqual(recog.memoryStates["en.g01.be"]!.stability, 3.7145 + (14.094985421450287 - 3.7145) * 0.5, accuracy: 1e-6)
        var fail = learner
        engine.apply(attempt("en.l01.e05", .incorrect, at: t1), to: &fail, now: t1)
        let f = fail.memoryStates["en.g01.be"]!
        XCTAssertEqual(f.stability, 1.418524828653778, accuracy: 1e-6)
        XCTAssertEqual(f.difficulty, 6.901155, accuracy: 1e-6)
        XCTAssertEqual(f.lapseCount, 1); XCTAssertEqual(f.failureCount, 1)
    }

    func testRapidRepetitionDoesNotGrowStability() {
        var learner = LearnerSnapshot()
        engine.apply(attempt("en.l01.e05", .correct, at: t0), to: &learner, now: t0)
        let before = learner.memoryStates["en.g01.be"]!
        let t1 = t0.addingTimeInterval(5 * 60)
        engine.apply(attempt("en.l01.e06", .correct, at: t1), to: &learner, now: t1)
        let after = learner.memoryStates["en.g01.be"]!
        XCTAssertEqual(after.stability, before.stability, accuracy: 1e-12)
        XCTAssertEqual(after.nextReviewAt, before.nextReviewAt)
        XCTAssertEqual(after.reviewCount, 2); XCTAssertEqual(after.successCount, 2)
        XCTAssertEqual(after.delayedSuccessCount, 0)
        // a failure 5 minutes later applies normally
        let t2 = t1.addingTimeInterval(300)
        engine.apply(attempt("en.l01.e06", .incorrect, at: t2), to: &learner, now: t2)
        XCTAssertLessThan(learner.memoryStates["en.g01.be"]!.stability, before.stability)
    }

    func testMinimumIntervalsAndMaximum() {
        let u = MemoryUpdater(index: engine.index, configuration: .default)
        XCTAssertEqual(u.interval(for: 0.1, grade: .again), 4 * 3600, accuracy: 1e-6)
        XCTAssertEqual(u.interval(for: 0.1, grade: .good), 12 * 3600, accuracy: 1e-6)
        XCTAssertEqual(u.interval(for: 10_000, grade: .good), 180 * day, accuracy: 1e-6)
    }

    func testSecondaryUnitsOnlyOnSuccessAndOnlyIfTracked() {
        var learner = LearnerSnapshot()
        // en.l03.e02 practises g03 and v.go; v.go is taught by lesson 2: not created from lesson 3.
        engine.apply(attempt("en.l03.e02", .correct, at: t0), to: &learner, now: t0)
        XCTAssertNotNil(learner.memoryStates["en.g03.past_simple"])
        XCTAssertNil(learner.memoryStates["en.v.go"])
        // once tracked, a success updates it (grade capped at Good) ...
        learner.memoryStates["en.v.go"] = MemoryState(unitId: "en.v.go", stability: 2, difficulty: 5, source: .lesson, firstSeenAt: t0.addingTimeInterval(-3 * day), nextReviewAt: t0)
        let t1 = t0.addingTimeInterval(day)
        engine.apply(attempt("en.l03.e02", .correct, at: t1), to: &learner, now: t1)
        XCTAssertEqual(learner.memoryStates["en.v.go"]!.reviewCount, 1)
        // ... a failure does not
        let t2 = t1.addingTimeInterval(day)
        engine.apply(attempt("en.l03.e02", .incorrect, at: t2), to: &learner, now: t2)
        XCTAssertEqual(learner.memoryStates["en.v.go"]!.reviewCount, 1)
        XCTAssertEqual(learner.memoryStates["en.g03.past_simple"]!.failureCount, 1)
    }

    func testAttemptHistoryIsBounded() {
        var config = EngineConfiguration.default
        config.attemptHistoryLimit = 5
        let e = LearningEngine(index: engine.index, configuration: config)
        var learner = LearnerSnapshot()
        for i in 0..<12 { e.apply(attempt("en.l01.e05", .correct, at: t0.addingTimeInterval(Double(i) * 600)), to: &learner, now: t0.addingTimeInterval(Double(i) * 600)) }
        XCTAssertEqual(learner.recentAttempts.count, 5)
        XCTAssertEqual(learner.memoryStates["en.g01.be"]!.recentResults.count, 10)
    }

    func testResolvePendingAttempt() {
        var learner = LearnerSnapshot()
        let pending = attempt("en.l03.e03", .pending, at: t0)
        engine.apply(pending, to: &learner, now: t0)
        XCTAssertTrue(learner.memoryStates.isEmpty)
        let changed = engine.resolvePendingAttempt(id: pending.id, result: .correct, errorCategory: nil, learner: &learner, now: t0.addingTimeInterval(3600))
        XCTAssertFalse(changed.isEmpty)
        XCTAssertEqual(learner.recentAttempts[0].result, .correct)
        XCTAssertEqual(learner.memoryStates["en.g03.past_simple"]!.successCount, 1)
        // dated at the time of the answer
        XCTAssertEqual(learner.memoryStates["en.g03.past_simple"]!.lastReviewAt, t0)
        // a resolved attempt cannot be resolved twice; an unknown id does nothing
        XCTAssertTrue(engine.resolvePendingAttempt(id: pending.id, result: .incorrect, errorCategory: .grammar, learner: &learner, now: t0).isEmpty)
        XCTAssertTrue(engine.resolvePendingAttempt(id: UUID(), result: .correct, errorCategory: nil, learner: &learner, now: t0).isEmpty)
        // incorrect resolution keeps the category
        var l2 = LearnerSnapshot()
        let p2 = attempt("en.l03.e03", .pending, at: t0)
        engine.apply(p2, to: &l2, now: t0)
        engine.resolvePendingAttempt(id: p2.id, result: .incorrect, errorCategory: .verbTense, learner: &l2, now: t0)
        XCTAssertEqual(l2.recentAttempts[0].errorCategory, .verbTense)
        XCTAssertEqual(l2.memoryStates["en.g03.past_simple"]!.failureCount, 1)
    }

    // MARK: Mastery

    func testMasteryFormula() {
        let calc = MasteryCalculator(configuration: .default)
        var s = MemoryState(unitId: "u", stability: 21, difficulty: 5, source: .lesson, firstSeenAt: t0, nextReviewAt: t0,
                            noHintSuccessCount: 3, delayedSuccessCount: 2, productionSuccessCount: 1,
                            successfulExerciseTypes: [.mcq, .fillBlank, .translation], recentResults: [true, true], lastReviewAt: t0)
        XCTAssertEqual(calc.score(s), 1.0, accuracy: 1e-12)
        s.stability = 10.5; s.recentResults = [true, false]; s.delayedSuccessCount = 1; s.productionSuccessCount = 0
        s.successfulExerciseTypes = [.mcq]; s.noHintSuccessCount = 0
        XCTAssertEqual(calc.score(s), 0.35 * 0.5 + 0.2 * 0.5 + 0 + 0.15 * 0.5 + 0.1 / 3, accuracy: 1e-12)
        XCTAssertEqual(calc.score(MemoryState(unitId: "u", stability: 0, difficulty: 5, source: .lesson, firstSeenAt: t0, nextReviewAt: t0)), 0, accuracy: 1e-12)
    }

    func testMCQOnlyCanNeverBeMastered() {
        var learner = LearnerSnapshot()
        var t = t0
        for _ in 0..<40 {
            engine.apply(attempt("en.l01.e01", .correct, at: t), to: &learner, now: t)
            engine.apply(attempt("en.l01.e10", .correct, at: t.addingTimeInterval(700)), to: &learner, now: t.addingTimeInterval(700))
            t = t.addingTimeInterval(2 * day)
        }
        let st = learner.memoryStates["en.g01.be"]!
        XCTAssertEqual(st.productionSuccessCount, 0)
        let report = engine.mastery(of: "en.g01.be", learner: learner, now: t.addingTimeInterval(-2 * day + 800))
        XCTAssertNotEqual(report.level, .mastered)
        XCTAssertGreaterThan(report.score, 0.5)
    }

    func testProductionAndDelayedSuccessCanBeMastered() {
        var learner = LearnerSnapshot()
        var t = t0
        // production, recall and recognition successes on 6 successive review dates (each when due)
        let ids = ["en.l01.e05", "en.l01.e04", "en.l01.e06", "en.l01.e01", "en.l01.e05", "en.l01.e06"]
        for id in ids {
            engine.apply(attempt(id, .correct, at: t), to: &learner, now: t)
            t = learner.memoryStates["en.g01.be"]!.nextReviewAt
        }
        let last = learner.memoryStates["en.g01.be"]!.lastReviewAt!
        let report = engine.mastery(of: "en.g01.be", learner: learner, now: last)
        XCTAssertEqual(report.level, .mastered, "score \(report.score)")
        XCTAssertGreaterThanOrEqual(report.score, engine.configuration.masteredThreshold)
        // long after the due date, retrievability drops: fragile, not mastered
        let later = engine.mastery(of: "en.g01.be", learner: learner, now: last.addingTimeInterval(1000 * day))
        XCTAssertEqual(later.level, .fragile)
        XCTAssertLessThan(later.retrievability, 0.8)
        // not started
        XCTAssertEqual(engine.mastery(of: "en.g02.present_simple", learner: learner, now: last).level, .notStarted)
        // levels in between
        var weak = LearnerSnapshot()
        engine.apply(attempt("en.l01.e05", .incorrect, at: t0), to: &weak, now: t0)
        XCTAssertEqual(engine.mastery(of: "en.g01.be", learner: weak, now: t0).level, .learning)
    }

    // MARK: Progress, due reviews, streak

    func testProgressReport() throws {
        var learner = LearnerSnapshot()
        engine.apply(attempt("en.l01.e05", .correct, at: t0), to: &learner, now: t0)
        engine.apply(attempt("en.l01.e06", .incorrect, at: t0.addingTimeInterval(2 * day)), to: &learner, now: t0.addingTimeInterval(2 * day))
        learner.completedLessonIds = ["en.l01"]
        let p = engine.progress(learner: learner, now: t0.addingTimeInterval(2 * day))
        XCTAssertEqual(p.attemptCount, 2)
        XCTAssertEqual(p.successRate, 0.5, accuracy: 1e-12)
        XCTAssertEqual(p.rulesStudied, 1); XCTAssertEqual(p.wordsStudied, 1)   // be + tired (happy: secondary of a failed attempt)
        XCTAssertEqual(p.reviewsDone, 1)
        XCTAssertEqual(p.lessonsCompleted, 1); XCTAssertEqual(p.lessonsTotal, 3)
        XCTAssertEqual(p.categories.count, 3)   // only the categories present in the content (the fixture has no sentence building unit)
        let grammar = p.categories.first { $0.category == .grammar }!
        XCTAssertEqual(grammar.unitsTotal, 3); XCTAssertEqual(grammar.unitsStudied, 1)
        XCTAssertGreaterThan(grammar.averageMastery, 0)
        XCTAssertEqual(p.weakErrorCategories.first?.category, .grammar)
        XCTAssertEqual(p.weakErrorCategories.first?.errorCount, 1)
        XCTAssertEqual(engine.progress(learner: learner, now: t0.addingTimeInterval(60 * day)).dueReviewCount, 2)
        // module progress: mean mastery over all units of the module (not started = 0)
        let modules = engine.moduleProgress(learner: learner, now: t0)
        XCTAssertEqual(modules.map { $0.module }, [1, 2])
        XCTAssertEqual(modules[1].fraction, 0)
        XCTAssertGreaterThan(modules[0].fraction, 0); XCTAssertLessThan(modules[0].fraction, 1)
        XCTAssertGreaterThan(engine.overallProgress(learner: learner, now: t0), 0)
    }

    func testDueReviewsAreSortedByRetrievability() {
        var learner = LearnerSnapshot()
        learner.memoryStates["en.g01.be"] = MemoryState(unitId: "en.g01.be", stability: 2, difficulty: 5, source: .lesson, firstSeenAt: t0, nextReviewAt: t0.addingTimeInterval(2 * day), lastReviewAt: t0)
        learner.memoryStates["en.g02.present_simple"] = MemoryState(unitId: "en.g02.present_simple", stability: 2, difficulty: 5, source: .lesson, firstSeenAt: t0, nextReviewAt: t0.addingTimeInterval(day), lastReviewAt: t0.addingTimeInterval(-5 * day))
        learner.memoryStates["en.g03.past_simple"] = MemoryState(unitId: "en.g03.past_simple", stability: 2, difficulty: 5, source: .lesson, firstSeenAt: t0, nextReviewAt: t0.addingTimeInterval(10 * day), lastReviewAt: t0)
        let now = t0.addingTimeInterval(3 * day)
        let due = engine.dueReviews(learner: learner, now: now)
        XCTAssertEqual(due.map { $0.unitId }, ["en.g02.present_simple", "en.g01.be"])
    }

    func testStreak() {
        let today = TestSupport.day(10)
        func days(_ offsets: [Int]) -> Set<LocalDay> { Set(offsets.map { TestSupport.day($0) }) }
        XCTAssertEqual(LearningEngine.streak(completedDays: [], today: today), 0)
        XCTAssertEqual(LearningEngine.streak(completedDays: days([10]), today: today), 1)
        XCTAssertEqual(LearningEngine.streak(completedDays: days([8, 9, 10]), today: today), 3)
        // nothing yet today: the streak runs to yesterday
        XCTAssertEqual(LearningEngine.streak(completedDays: days([7, 8, 9]), today: today), 3)
        // a gap breaks it
        XCTAssertEqual(LearningEngine.streak(completedDays: days([5, 6, 8, 9, 10]), today: today), 3)
        XCTAssertEqual(LearningEngine.streak(completedDays: days([7, 8]), today: today), 0)
        // across a month boundary
        let first = LocalDay(year: 2026, month: 4, day: 1)
        XCTAssertEqual(LearningEngine.streak(completedDays: [first, LocalDay(year: 2026, month: 3, day: 31), LocalDay(year: 2026, month: 3, day: 30)], today: first), 3)
    }
}

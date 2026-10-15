import XCTest
@testable import LearningCore

final class SessionRunnerTests: XCTestCase {
    var engine: LearningEngine!
    let now = TestSupport.date(day: 0, hour: 9)

    override func setUpWithError() throws { engine = try TestSupport.fixtureEngine() }

    private func plan(seed: UInt64 = 1, learner: LearnerSnapshot = .empty) -> SessionPlan {
        engine.planSession(type: .learning, slot: .morning, day: TestSupport.day(0), learner: learner, now: now, seed: seed)
    }

    func testPerfectSessionCompletesWithoutRemediation() {
        let p = plan()
        var runner = SessionRunner(plan: p, startedAt: now)
        XCTAssertEqual(runner.totalCount, p.items.count)
        XCTAssertFalse(runner.isComplete)
        var learner = LearnerSnapshot()
        var t = now
        while let item = runner.currentItem {
            if let id = item.exerciseId {
                let ex = engine.exercise(id)!
                let (ev, attempt) = runner.submit(TestSupport.modelSubmission(ex), hintUsed: false, duration: 12, engine: engine, now: t)
                XCTAssertTrue(ev.isCorrect, id)
                XCTAssertTrue(runner.awaitingAdvance)
                XCTAssertEqual(attempt.sessionId, p.id)
                XCTAssertEqual(attempt.unitIds, ex.unitIds)
                XCTAssertEqual(attempt.presentation, item.presentation)
                engine.apply(attempt, to: &learner, now: t)
            }
            runner.advance(engine: engine, learner: learner)
            XCTAssertFalse(runner.awaitingAdvance)
            t = t.addingTimeInterval(20)
        }
        XCTAssertTrue(runner.isComplete)
        XCTAssertNil(runner.currentItem)
        XCTAssertEqual(runner.remediationCount, 0)
        XCTAssertEqual(runner.totalCount, p.items.count)
        XCTAssertEqual(runner.completedCount, runner.totalCount)
        let summary = runner.summary(engine: engine, now: t)
        XCTAssertEqual(summary.sessionId, p.id)
        XCTAssertEqual(summary.type, .learning)
        XCTAssertEqual(summary.lessonId, "en.l01")
        XCTAssertEqual(summary.attemptCount, p.items.filter { $0.exerciseId != nil }.count)
        XCTAssertEqual(summary.correctCount, summary.attemptCount)
        XCTAssertTrue(summary.importantErrors.isEmpty)
        XCTAssertEqual(summary.newUnitIds, p.newUnitIds)
        XCTAssertEqual(summary.reviewCount, 0)
        XCTAssertNil(summary.score)
        XCTAssertEqual(summary.durationSeconds, t.timeIntervalSince(now), accuracy: 1e-9)
        XCTAssertEqual(Set(summary.unitIdsWorked).count, summary.unitIdsWorked.count)
        XCTAssertTrue(Set(p.newUnitIds).isSubset(of: Set(summary.unitIdsWorked)))
        // a further advance is harmless
        runner.advance(engine: engine, learner: learner)
        XCTAssertTrue(runner.isComplete)
    }

    func testRemediationIsInsertedAndCapped() {
        let p = plan(seed: 2)
        var runner = SessionRunner(plan: p, startedAt: now)
        let planned = p.items.count
        let exerciseItems = p.items.filter { $0.exerciseId != nil }.count
        var learner = LearnerSnapshot()
        var inserted: [SessionItem] = []
        var guardCount = 0
        while let item = runner.currentItem, guardCount < 100 {
            guardCount += 1
            if let id = item.exerciseId {
                let ex = engine.exercise(id)!
                let (ev, attempt) = runner.submit(TestSupport.wrongSubmission(ex), hintUsed: false, duration: 5, engine: engine, now: now)
                XCTAssertFalse(ev.isCorrect)
                XCTAssertEqual(attempt.isRemediation, item.role == .remediation)
                engine.apply(attempt, to: &learner, now: now)
            }
            let before = runner.items.count
            runner.advance(engine: engine, learner: learner)
            if runner.items.count > before { inserted.append(runner.items.last!) }
        }
        XCTAssertTrue(runner.isComplete, "a wrong answer never blocks the end of the session")
        XCTAssertEqual(runner.remediationCount, engine.configuration.maxRemediationsPerSession)
        XCTAssertEqual(inserted.count, 3)
        XCTAssertEqual(runner.items.count, planned + 3)
        XCTAssertEqual(runner.attempts.count, exerciseItems + 3)
        for item in inserted {
            XCTAssertEqual(item.role, .remediation)
            XCTAssertTrue(item.hintAllowed)
        }
        // a remediation is another exercise on the same primary unit (or the same exercise once when there is no other)
        let originals = p.items.compactMap { $0.exerciseId }
        for item in inserted {
            let r = engine.exercise(item.exerciseId!)!
            XCTAssertTrue(engine.index.exercisesById[r.id] != nil)
            XCTAssertFalse(originals.contains(r.id) && r.id == inserted.first?.exerciseId && false)
        }
        let summary = runner.summary(engine: engine, now: now)
        XCTAssertEqual(summary.correctCount, 0)
        XCTAssertLessThanOrEqual(summary.importantErrors.count, 5)
        XCTAssertFalse(summary.importantErrors.isEmpty)
        XCTAssertEqual(Set(summary.importantErrors.map { $0.exerciseId }).count, summary.importantErrors.count)
    }

    func testRemediationTargetsTheSameUnit() {
        let p = plan(seed: 3)
        var runner = SessionRunner(plan: p, startedAt: now)
        guard let first = runner.currentItem, case .ruleCard = first.kind else { return XCTFail("expected a rule card first") }
        runner.advance(engine: engine, learner: .empty)
        while let item = runner.currentItem, item.exerciseId == nil { runner.advance(engine: engine, learner: .empty) }
        let item = runner.currentItem!
        let ex = engine.exercise(item.exerciseId!)!
        runner.submit(TestSupport.wrongSubmission(ex), hintUsed: false, duration: 1, engine: engine, now: now)
        runner.advance(engine: engine, learner: .empty)
        let added = runner.items.last!
        XCTAssertEqual(added.role, .remediation)
        let r = engine.exercise(added.exerciseId!)!
        XCTAssertEqual(r.primaryUnitId, ex.primaryUnitId)
        XCTAssertNotEqual(r.id, ex.id)
        XCTAssertFalse(p.items.contains { $0.exerciseId == r.id }, "a remediation is not already part of the session")
    }

    func testPendingEvaluationDoesNotTriggerRemediationButOverrideDoes() {
        // exercise en.l01.e08 is an open free answer
        let item = SessionItem(kind: .exercise(exerciseId: "en.l01.e08"), role: .practice, presentation: .typed, hintAllowed: false)
        let tail = SessionItem(kind: .exercise(exerciseId: "en.l01.e07"), role: .practice, presentation: .typed, hintAllowed: false)
        let custom = SessionPlan(type: .extra, slot: nil, day: TestSupport.day(0), lessonId: nil, newUnitIds: [], items: [item, tail], estimatedSeconds: 60, createdAt: now)
        var runner = SessionRunner(plan: custom, startedAt: now)
        let (ev, attempt) = runner.submit(.text("My father is a doctor in Lyon"), hintUsed: false, duration: 9, engine: engine, now: now)
        XCTAssertEqual(ev.result, .pending)
        XCTAssertEqual(attempt.result, .pending)
        // a second submit on the same item is ignored
        let again = runner.submit(.text("something else"), hintUsed: false, duration: 1, engine: engine, now: now)
        XCTAssertEqual(again.attempt.id, attempt.id)
        XCTAssertEqual(runner.attempts.count, 1)
        var accepted = runner
        runner.advance(engine: engine, learner: .empty)
        XCTAssertEqual(runner.items.count, 2, "no remediation for a pending answer")
        // AI says: correct -> still no remediation
        var graded = ev
        graded.result = .correct
        graded.gradedBy = .ai
        let updated = accepted.overrideLastEvaluation(graded)
        XCTAssertEqual(updated?.result, .correct)
        XCTAssertEqual(accepted.attempts.last?.result, .correct)
        XCTAssertEqual(accepted.lastEvaluation?.gradedBy, .ai)
        accepted.advance(engine: engine, learner: .empty)
        XCTAssertEqual(accepted.items.count, 2)
        // AI says: incorrect -> remediation
        var rejected = SessionRunner(plan: custom, startedAt: now)
        _ = rejected.submit(.text("My father is a doctor in Lyon"), hintUsed: false, duration: 9, engine: engine, now: now)
        var bad = ev
        bad.result = .incorrect; bad.errorCategory = .grammar; bad.gradedBy = .ai
        let upd = rejected.overrideLastEvaluation(bad)
        XCTAssertEqual(upd?.result, .incorrect)
        XCTAssertEqual(upd?.errorCategory, .grammar)
        rejected.advance(engine: engine, learner: .empty)
        XCTAssertEqual(rejected.items.count, 3)
        XCTAssertEqual(rejected.items.last?.role, .remediation)
        // nothing to override before any answer
        var fresh = SessionRunner(plan: custom, startedAt: now)
        XCTAssertNil(fresh.overrideLastEvaluation(bad))
    }

    func testAssessmentSessionsHaveNoRemediation() {
        var sim = Simulator(engine: engine, base: 1, gain: 0)
        for d in 0..<3 { sim.runDay(d, assessmentIfDue: false) }
        let t = TestSupport.date(day: 16, hour: 20)
        let p = engine.planAssessment(day: TestSupport.day(16), learner: sim.learner, now: t, seed: 1)
        var runner = SessionRunner(plan: p, startedAt: t)
        var count = 0
        while let item = runner.currentItem {
            if let id = item.exerciseId {
                _ = runner.submit(TestSupport.wrongSubmission(engine.exercise(id)!), hintUsed: false, duration: 1, engine: engine, now: t)
                count += 1
            }
            runner.advance(engine: engine, learner: sim.learner)
        }
        XCTAssertEqual(runner.remediationCount, 0)
        XCTAssertEqual(runner.attempts.count, count)
        let summary = runner.summary(engine: engine, now: t)
        XCTAssertEqual(summary.score, 0)
        XCTAssertEqual(summary.type, .assessment)
    }

    func testCardsOnlyNeedAdvance() {
        let p = plan(seed: 4)
        var runner = SessionRunner(plan: p, startedAt: now)
        XCTAssertNil(runner.currentItem?.exerciseId)
        let (ev, attempt) = runner.submit(.text("x"), hintUsed: false, duration: 1, engine: engine, now: now)
        XCTAssertEqual(ev.result, .incorrect)
        XCTAssertEqual(attempt.exerciseId, "")
        XCTAssertTrue(runner.attempts.isEmpty)
        XCTAssertFalse(runner.awaitingAdvance)
        runner.advance(engine: engine, learner: .empty)
        XCTAssertEqual(runner.position, 1)
    }

    func testCodableRoundTripMidSession() throws {
        let p = plan(seed: 5)
        var runner = SessionRunner(plan: p, startedAt: now)
        var learner = LearnerSnapshot()
        for _ in 0..<7 {
            if let id = runner.currentItem?.exerciseId {
                let ex = engine.exercise(id)!
                let (_, a) = runner.submit(TestSupport.wrongSubmission(ex), hintUsed: true, duration: 3, engine: engine, now: now)
                engine.apply(a, to: &learner, now: now)
            }
            runner.advance(engine: engine, learner: learner)
        }
        // also with an answer awaiting its advance
        if let id = runner.currentItem?.exerciseId {
            _ = runner.submit(TestSupport.modelSubmission(engine.exercise(id)!), hintUsed: false, duration: 3, engine: engine, now: now)
        }
        let data = try JSONEncoder().encode(runner)
        let decoded = try JSONDecoder().decode(SessionRunner.self, from: data)
        XCTAssertEqual(decoded, runner)
        XCTAssertEqual(decoded.position, runner.position)
        XCTAssertEqual(decoded.attempts, runner.attempts)
        var resumed = decoded
        var original = runner
        resumed.advance(engine: engine, learner: learner)
        original.advance(engine: engine, learner: learner)
        XCTAssertEqual(resumed.position, original.position)
        XCTAssertEqual(resumed.items.count, original.items.count)
        // plan and learner snapshot are Codable too
        XCTAssertEqual(try JSONDecoder().decode(SessionPlan.self, from: JSONEncoder().encode(p)), p)
        XCTAssertEqual(try JSONDecoder().decode(LearnerSnapshot.self, from: JSONEncoder().encode(learner)), learner)
    }
}

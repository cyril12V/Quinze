import XCTest
@testable import LearningCore

/// 30-day simulation on the real content: 3 sessions a day, learner whose success probability grows with mastery.
final class SimulationTests: XCTestCase {
    struct Metrics {
        var lessonsByDay: [Int] = []
        var due: [Int] = []
        var overdue: [Int] = []
        var sameDayRepeats = 0
        var sameDayRepeatsAfterDay5 = 0
        /// Duplicates between the plans of one day (planner only, runtime remediation excluded), after day 5.
        var plannedRepeatsAfterDay5 = 0
        var lessonIdsByDay: [[String]] = []
        var assessmentItemCounts: [Int] = []
        var exerciseCounts: [Int] = []
        var reviewAttemptsByDay: [Int] = []
        var remediationSessions = 0
        var pauseSessions = 0
        var assessments = 0
    }

    func simulate(base: Double, gain: Double, seed: UInt64, days: Int, config: EngineConfiguration = .default) throws -> (Simulator, Metrics) {
        let engine = LearningEngine(bundle: try TestSupport.realBundle(), configuration: config)
        var sim = Simulator(engine: engine, seed: seed, base: base, gain: gain)
        var m = Metrics()
        for d in 0..<days {
            sim.runDay(d)
            let end = TestSupport.date(day: d, hour: 21)
            m.lessonsByDay.append(sim.learner.completedLessonIds.count)
            m.due.append(engine.dueReviews(learner: sim.learner, now: end).count)
            let limit = end.addingTimeInterval(-EngineTuning.overdueGraceHours * 3600)
            m.overdue.append(sim.learner.memoryStates.values.filter { $0.nextReviewAt <= limit }.count)
            // reviews = attempts on units first seen on a previous day
            let todayRecords = sim.records.filter { $0.day == d }
            var seen = Set<String>()
            var reviews = 0
            for r in todayRecords {
                for id in r.exerciseIds {
                    if !seen.insert(id).inserted { m.sameDayRepeats += 1; if d >= 5 { m.sameDayRepeatsAfterDay5 += 1 } }
                }
                reviews += r.summary.reviewCount
            }
            m.reviewAttemptsByDay.append(reviews)
            var planned = Set<String>()
            for r in todayRecords {
                for item in r.plan.items {
                    guard let id = item.exerciseId else { continue }
                    if !planned.insert(id).inserted && d >= 5 { m.plannedRepeatsAfterDay5 += 1 }
                }
            }
            for r in todayRecords {
                m.exerciseCounts.append(r.plan.items.filter { $0.exerciseId != nil }.count)
                if r.plan.type == .learning && r.plan.lessonId == nil { m.remediationSessions += 1 }
                if r.plan.type == .assessment { m.assessments += 1; m.assessmentItemCounts.append(r.plan.items.filter { $0.exerciseId != nil }.count) }
            }
        }
        return (sim, m)
    }

    func printMetrics(_ title: String, _ sim: Simulator, _ m: Metrics) {
        guard ProcessInfo.processInfo.environment["QUINZE_PRINT_SIM"] != nil else { return }
        print("== \(title)")
        print("lessons by day:", m.lessonsByDay)
        print("due by day:    ", m.due)
        print("overdue by day:", m.overdue)
        print("reviews by day:", m.reviewAttemptsByDay)
        print("exercise counts min/max:", m.exerciseCounts.min() ?? 0, m.exerciseCounts.max() ?? 0, "repeats", m.sameDayRepeats, "after d5", m.sameDayRepeatsAfterDay5, "planned after d5", m.plannedRepeatsAfterDay5, "remediation sessions", m.remediationSessions, "assessments", m.assessments)
        let p = sim.engine.progress(learner: sim.learner, now: TestSupport.date(day: m.lessonsByDay.count - 1, hour: 21))
        print("success", p.successRate, "words", p.wordsStudied, p.wordsMastered, "rules", p.rulesStudied, p.rulesMastered, "attempts", sim.learner.recentAttempts.count)
    }

    /// Longest run of consecutive days without any lesson completed (ignoring day 0).
    func longestStall(_ lessonsByDay: [Int]) -> Int {
        var best = 0, run = 0
        for i in 1..<lessonsByDay.count {
            if lessonsByDay[i] == lessonsByDay[i - 1] { run += 1; best = max(best, run) } else { run = 0 }
        }
        return best
    }

    // Calibrated on the real content (60 lessons x 10 exercises): three virtual learners, 30 days, 3 sessions a day.
    // Measured with the default configuration: 21 to 27 lessons, longest stall 3 days, 10 to 15 remediation sessions.
    func testThirtyDaysOfRealLearning() throws {
        for (base, gain, seed) in [(0.55, 0.42, UInt64(7)), (0.45, 0.40, 11), (0.7, 0.3, 3)] {
            let (sim, m) = try simulate(base: base, gain: gain, seed: seed, days: 30)
            printMetrics("base \(base) gain \(gain) seed \(seed)", sim, m)
            let label = "learner base \(base) seed \(seed)"
            // steady lesson progression (a weak learner still advances, with remediation days)
            XCTAssertGreaterThanOrEqual(m.lessonsByDay.last ?? 0, 15, label)
            XCTAssertLessThanOrEqual(longestStall(m.lessonsByDay), 4, "\(label): nothing may block for more than 4 days")
            // the lessons completed are the first ones of the sequence (a bypass may skip, but never far ahead)
            let order = sim.engine.index.tables.lessonsInOrder.map { $0.id }
            let completed = sim.learner.completedLessonIds
            let furthest = order.lastIndex { completed.contains($0) } ?? -1
            XCTAssertLessThanOrEqual(furthest + 1 - completed.count, 3, "\(label): at most 3 lessons skipped")
            // reviews happen every day once material exists
            XCTAssertGreaterThanOrEqual(m.reviewAttemptsByDay.reduce(0, +), 150, label)
            for d in 3..<m.reviewAttemptsByDay.count { XCTAssertGreaterThan(m.reviewAttemptsByDay[d], 0, "\(label): reviews on day \(d)") }
            // sessions of 8 to 12 exercises
            XCTAssertGreaterThanOrEqual(m.exerciseCounts.min() ?? 0, 8, label)
            XCTAssertLessThanOrEqual(m.exerciseCounts.max() ?? 99, 12, label)
            XCTAssertEqual(m.exerciseCounts.count, 90, "\(label): 3 sessions a day")
            // the planner does not repeat an exercise on the same day once the pool is wide enough
            XCTAssertLessThanOrEqual(m.plannedRepeatsAfterDay5, 25, label)
            // the backlog stays under control
            XCTAssertLessThanOrEqual(m.due.max() ?? 0, 40, label)
            XCTAssertLessThanOrEqual(m.overdue.last ?? 0, 25, label)
            // a consolidation test is offered, with the planned size
            XCTAssertGreaterThanOrEqual(m.assessments, 1, label)
            XCTAssertTrue(m.assessmentItemCounts.allSatisfy { (8...12).contains($0) }, label)
            // the learner's success rate stays in a healthy range
            let p = sim.engine.progress(learner: sim.learner, now: TestSupport.date(day: 29, hour: 21))
            XCTAssertGreaterThan(p.successRate, 0.6, label)
            XCTAssertGreaterThan(p.wordsStudied, 60, label)
        }
    }

    /// On the real content, the three slots of a day are planned independently, with different exercises, and always the same way.
    func testThreeSlotsAreIndependentAndDifferent() throws {
        let engine = LearningEngine(bundle: try TestSupport.realBundle())
        var sim = Simulator(engine: engine, seed: 9, base: 0.6, gain: 0.4)
        for d in 0..<8 { sim.runDay(d) }
        let day = TestSupport.day(8)
        // Missed morning: the first session of the day teaches, whatever its slot (spec 5, "type effectif").
        let missed = engine.planSession(type: .application, slot: .afternoon, day: day, learner: sim.learner,
                                        now: TestSupport.date(day: 8, hour: 14), seed: 99)
        XCTAssertEqual(missed.type, .learning)
        // Morning done: the afternoon and the evening are planned from the same snapshot (same instant) and do not overlap.
        sim.run(day: 8, slot: .morning)
        let now = TestSupport.date(day: 8, hour: 14)
        func plan(_ slot: SessionSlot, seed: UInt64 = 99, learner: LearnerSnapshot? = nil, at: Date? = nil) -> SessionPlan {
            engine.planSession(type: slot.defaultSessionType, slot: slot, day: day, learner: learner ?? sim.learner, now: at ?? now, seed: seed)
        }
        func ids(_ p: SessionPlan) -> [String] { p.items.compactMap { $0.exerciseId } }
        let afternoon = plan(.afternoon), evening = plan(.evening)
        XCTAssertEqual(afternoon, plan(.afternoon), "deterministic for a given seed")
        XCTAssertEqual(afternoon.type, .application)
        XCTAssertEqual(evening.type, .consolidation)
        for p in [afternoon, evening] {
            XCTAssertTrue((8...12).contains(ids(p).count))
            XCTAssertEqual(Set(ids(p)).count, ids(p).count, "no duplicate exercise in a session")
        }
        XCTAssertTrue(Set(ids(afternoon)).isDisjoint(with: ids(evening)), "afternoon and evening share no exercise")
        XCTAssertNotEqual(ids(afternoon), ids(evening))
        XCTAssertTrue(evening.items.allSatisfy { !$0.hintAllowed }, "consolidation is without hints")
        // another seed gives another plan (the selection itself may be forced by a thin pool on day 8)
        XCTAssertNotEqual(plan(.afternoon, seed: 100), afternoon)
        // The afternoon is done, then the evening is planned for real: nothing done today comes back.
        let done = sim.run(day: 8, slot: .afternoon)
        let morningDone = Set(sim.records.first { $0.day == 8 && $0.slot == .morning }!.exerciseIds)
        let evening2 = plan(.evening, at: TestSupport.date(day: 8, hour: 20))
        XCTAssertEqual(evening2.type, .consolidation)
        XCTAssertTrue(Set(ids(evening2)).isDisjoint(with: Set(done.exerciseIds).union(morningDone)), "no exercise repeated within the day")
    }

    func testSimulationIsDeterministic() throws {
        let (a, ma) = try simulate(base: 0.55, gain: 0.42, seed: 7, days: 6)
        let (b, mb) = try simulate(base: 0.55, gain: 0.42, seed: 7, days: 6)
        XCTAssertEqual(ma.lessonsByDay, mb.lessonsByDay)
        XCTAssertEqual(a.records.map { $0.exerciseIds }, b.records.map { $0.exerciseIds })
        XCTAssertEqual(a.records.map { $0.plan }, b.records.map { $0.plan })
    }

    /// A learner who answers everything correctly moves forward at one lesson a day.
    func testPerfectLearnerProgressesDaily() throws {
        let engine = LearningEngine(bundle: try TestSupport.realBundle())
        var sim = Simulator(engine: engine, seed: 5, base: 1, gain: 0)
        for d in 0..<10 { sim.runDay(d) }
        XCTAssertGreaterThanOrEqual(sim.learner.completedLessonIds.count, 9)
    }

    /// A learner who fails almost everything is never stuck forever: the engine keeps giving material and bypasses the gates.
    func testStrugglingLearnerIsNeverBlockedForever() throws {
        let (sim, m) = try simulate(base: 0.08, gain: 0.0, seed: 21, days: 30)
        printMetrics("struggling", sim, m)
        XCTAssertGreaterThanOrEqual(m.lessonsByDay.last ?? 0, 6)
        XCTAssertLessThanOrEqual(longestStall(m.lessonsByDay), 8)
        XCTAssertGreaterThanOrEqual(m.exerciseCounts.min() ?? 0, 8)
        XCTAssertLessThanOrEqual(m.exerciseCounts.max() ?? 99, 12)
    }
}

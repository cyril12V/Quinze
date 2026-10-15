import XCTest
@testable import LearningCore

final class DiagnosticTests: XCTestCase {
    /// Answers every question correctly iff its level is <= ability.
    private func run(_ engine: LearningEngine, start: SelfAssessedLevel, ability: Int, seed: UInt64 = 1) -> (DiagnosticSession, [Exercise]) {
        var session = engine.makeDiagnostic(selfAssessed: start, seed: seed)
        var asked: [Exercise] = []
        var guardCount = 0
        while let ex = session.nextExercise(engine: engine), guardCount < 60 {
            guardCount += 1
            asked.append(ex)
            let ok = (ex.level ?? 0) <= ability
            let sub = ok ? TestSupport.modelSubmission(ex) : TestSupport.wrongSubmission(ex)
            session.record(exerciseId: ex.id, evaluation: engine.evaluate(ex, submission: sub), engine: engine)
        }
        return (session, asked)
    }

    func testStaircase() throws {
        let engine = try TestSupport.fixtureEngine()
        var session = engine.makeDiagnostic(selfAssessed: .someBasics, seed: 3)
        XCTAssertEqual(session.currentLevel, 1)
        XCTAssertEqual(session.maxQuestions, 20)
        func answer(_ ok: Bool) {
            let ex = session.nextExercise(engine: engine)!
            let sub = ok ? TestSupport.modelSubmission(ex) : TestSupport.wrongSubmission(ex)
            session.record(exerciseId: ex.id, evaluation: engine.evaluate(ex, submission: sub), engine: engine)
        }
        answer(true); XCTAssertEqual(session.currentLevel, 1)      // one correct answer: same level
        answer(true); XCTAssertEqual(session.currentLevel, 2)      // two in a row: up
        answer(true); XCTAssertEqual(session.currentLevel, 2)
        answer(false); XCTAssertEqual(session.currentLevel, 1)     // an error: down
        answer(false); XCTAssertEqual(session.currentLevel, 0)
        answer(false); XCTAssertEqual(session.currentLevel, 0)     // lower bound
        XCTAssertEqual(session.answeredCount, 6)
        XCTAssertEqual(session.askedIds.count, 6)
        XCTAssertEqual(Set(session.askedIds).count, 6)
        for (i, a) in session.answers.enumerated() { XCTAssertEqual(a.exerciseId, session.askedIds[i]) }
        // a pending question is asked again until it is recorded
        let q = session.nextExercise(engine: engine)!
        XCTAssertEqual(session.nextExercise(engine: engine)?.id, q.id)
        XCTAssertEqual(session.askedIds.count, 7)
        // the same question cannot be recorded twice
        let ev = engine.evaluate(q, submission: TestSupport.modelSubmission(q))
        session.record(exerciseId: q.id, evaluation: ev, engine: engine)
        session.record(exerciseId: q.id, evaluation: ev, engine: engine)
        XCTAssertEqual(session.answeredCount, 7)
        // upper bound
        var top = engine.makeDiagnostic(selfAssessed: .intermediate, seed: 1)
        for _ in 0..<4 {
            let ex = top.nextExercise(engine: engine)!
            top.record(exerciseId: ex.id, evaluation: engine.evaluate(ex, submission: TestSupport.modelSubmission(ex)), engine: engine)
        }
        XCTAssertEqual(top.currentLevel, 4)
    }

    func testStrongAndWeakLearners() throws {
        let engine = try TestSupport.fixtureEngine()
        let (strong, askedStrong) = run(engine, start: .understandsSentences, ability: 4)
        XCTAssertTrue(strong.isFinished)
        XCTAssertTrue((15...20).contains(strong.answeredCount), "\(strong.answeredCount)")
        XCTAssertEqual(Set(askedStrong.map { $0.id }).count, askedStrong.count, "a question is never asked twice")
        let rs = strong.result(engine: engine)
        XCTAssertEqual(rs.estimatedLevel, 4)
        XCTAssertEqual(rs.levelLabel, "Pré-intermédiaire")
        XCTAssertEqual(rs.startLessonId, "en.l03")
        XCTAssertEqual(rs.placedLessonIds, ["en.l01", "en.l02"])
        XCTAssertEqual(Set(rs.knownUnitIds), Set(engine.lesson("en.l01")!.introduces + engine.lesson("en.l02")!.introduces))
        XCTAssertEqual(rs.answers.count, strong.answeredCount)
        XCTAssertFalse(rs.topicScores.isEmpty)
        XCTAssertTrue(rs.topicScores.values.allSatisfy { $0 == 1 })

        let (weak, _) = run(engine, start: .intermediate, ability: -1)
        XCTAssertTrue((15...20).contains(weak.answeredCount), "\(weak.answeredCount)")
        let rw = weak.result(engine: engine)
        XCTAssertEqual(rw.estimatedLevel, 0)
        XCTAssertEqual(rw.levelLabel, "Débutant")
        XCTAssertEqual(rw.startLessonId, "en.l01")
        XCTAssertTrue(rw.placedLessonIds.isEmpty)
        XCTAssertTrue(rw.knownUnitIds.isEmpty)

        let (mid, _) = run(engine, start: .beginner, ability: 2)
        XCTAssertEqual(mid.result(engine: engine).estimatedLevel, 2)
        XCTAssertEqual(mid.result(engine: engine).levelLabel, "Bases acquises")
    }

    func testVarietyDeterminismAndCodable() throws {
        let engine = try TestSupport.fixtureEngine()
        let (a, askedA) = run(engine, start: .someBasics, ability: 2, seed: 9)
        let (b, askedB) = run(engine, start: .someBasics, ability: 2, seed: 9)
        XCTAssertEqual(askedA.map { $0.id }, askedB.map { $0.id })
        XCTAssertEqual(a, b)
        let topics = askedA.prefix(8).map { $0.topic ?? "" }
        XCTAssertGreaterThanOrEqual(Set(topics).count, 4, "\(topics)")
        for i in 3..<topics.count { XCTAssertFalse(topics[i - 1] == topics[i] && topics[i] == topics[i - 2] && topics[i] == topics[i - 3]) }
        var half = engine.makeDiagnostic(selfAssessed: .beginner, seed: 4)
        for _ in 0..<5 { let ex = half.nextExercise(engine: engine)!; half.record(exerciseId: ex.id, evaluation: engine.evaluate(ex, submission: TestSupport.modelSubmission(ex)), engine: engine) }
        let decoded = try JSONDecoder().decode(DiagnosticSession.self, from: JSONEncoder().encode(half))
        XCTAssertEqual(decoded, half)
        var d1 = decoded, h1 = half
        XCTAssertEqual(d1.nextExercise(engine: engine)?.id, h1.nextExercise(engine: engine)?.id)
        // finished sessions return no question
        var done = a
        XCTAssertNil(done.nextExercise(engine: engine))
        let r = a.result(engine: engine)
        XCTAssertEqual(try JSONDecoder().decode(DiagnosticResult.self, from: JSONEncoder().encode(r)), r)
    }

    func testBankExhaustionEndsTheTest() throws {
        let engine = try TestSupport.fixtureEngine()
        var s = DiagnosticSession(startLevel: 2, maxQuestions: 100, minQuestions: 100, seed: 1)
        var n = 0
        while let ex = s.nextExercise(engine: engine) {
            s.record(exerciseId: ex.id, evaluation: engine.evaluate(ex, submission: TestSupport.modelSubmission(ex)), engine: engine)
            n += 1
        }
        XCTAssertEqual(n, 20)
        XCTAssertTrue(s.isFinished)
        XCTAssertTrue(s.bankExhausted)
    }

    func testPlacementOnTheFixture() throws {
        let engine = try TestSupport.fixtureEngine()
        let (session, _) = run(engine, start: .intermediate, ability: 4)
        let result = session.result(engine: engine)
        var learner = LearnerSnapshot()
        let now = TestSupport.date(day: 0, hour: 9)
        let states = engine.applyPlacement(result, to: &learner, now: now)
        XCTAssertEqual(states.count, result.knownUnitIds.count)
        XCTAssertEqual(learner.placedLessonIds, Set(result.placedLessonIds))
        XCTAssertEqual(learner.estimatedLevel, 4)
        XCTAssertEqual(learner.startedAt, now)
        for st in states {
            XCTAssertEqual(st.source, .diagnostic)
            XCTAssertEqual(st.stability, 2); XCTAssertEqual(st.difficulty, 5)
            XCTAssertEqual(st.successCount, 0); XCTAssertEqual(st.reviewCount, 0)
            XCTAssertGreaterThanOrEqual(st.nextReviewAt.timeIntervalSince(now), 86_400)
        }
        // presumed-known prerequisites do not block the next lesson; seeded units are never "mastered"
        XCTAssertEqual(engine.nextLesson(for: learner, now: now)?.id, "en.l03")
        XCTAssertTrue(learner.memoryStates.keys.allSatisfy { engine.mastery(of: $0, learner: learner, now: now).level != .mastered })
        // applying twice does not duplicate or reset states
        XCTAssertTrue(engine.applyPlacement(result, to: &learner, now: now.addingTimeInterval(3600)).isEmpty)
    }

    // MARK: Real diagnostic bank

    func testRealBankEstimatesTheAbilityAndStaggersPlacement() throws {
        let bundle = try TestSupport.realBundle()
        let engine = LearningEngine(bundle: bundle)
        let starts: [SelfAssessedLevel] = [.beginner, .someBasics, .understandsSentences, .intermediate]
        let expectedStart = [0: "en.l01", 1: "en.l10", 2: "en.l18", 3: "en.l27", 4: "en.l35"]
        for ability in 0...4 {
            for start in starts {
                let (session, asked) = run(engine, start: start, ability: ability, seed: UInt64(ability * 10 + start.rawValue))
                XCTAssertTrue((15...20).contains(session.answeredCount), "ability \(ability) start \(start): \(session.answeredCount) questions")
                XCTAssertEqual(Set(asked.map { $0.id }).count, asked.count)
                let r = session.result(engine: engine)
                XCTAssertTrue(abs(r.estimatedLevel - ability) <= 1, "ability \(ability) start \(start) -> \(r.estimatedLevel)")
                XCTAssertEqual(r.startLessonId, expectedStart[r.estimatedLevel], "level \(r.estimatedLevel)")
            }
            // the exact ability is found from the matching self-assessment
            let start = starts[min(ability, 3)]
            let (s, _) = run(engine, start: start, ability: ability, seed: 5)
            XCTAssertEqual(s.result(engine: engine).estimatedLevel, ability, "ability \(ability)")
        }
        // placement at level 4: ~200 units, at most 15 checks per day
        let (session, _) = run(engine, start: .intermediate, ability: 4)
        let result = session.result(engine: engine)
        XCTAssertEqual(result.startLessonId, "en.l35")
        XCTAssertEqual(result.placedLessonIds.count, 34)
        XCTAssertGreaterThan(result.knownUnitIds.count, 150)
        var learner = LearnerSnapshot()
        let now = TestSupport.date(day: 0, hour: 9)
        let states = engine.applyPlacement(result, to: &learner, now: now)
        XCTAssertEqual(states.count, result.knownUnitIds.count)
        var perDay: [Int: Int] = [:]
        for st in states { perDay[Int(st.nextReviewAt.timeIntervalSince(now) / 86_400), default: 0] += 1 }
        XCTAssertTrue(perDay.values.allSatisfy { $0 <= 15 }, "\(perDay)")
        XCTAssertEqual(perDay.keys.min(), 1)
        XCTAssertEqual(perDay.count, Int((Double(states.count) / 15).rounded(.up)))
        // the most advanced placed content is checked first
        let first = states.sorted { $0.nextReviewAt < $1.nextReviewAt }.first!
        XCTAssertTrue(engine.lesson("en.l34")!.introduces.contains(first.unitId))
        XCTAssertEqual(engine.nextLesson(for: learner, now: now)?.id, "en.l35")
        // due reviews on the first check day stay within the budget
        XCTAssertLessThanOrEqual(engine.dueReviews(learner: learner, now: now.addingTimeInterval(1.5 * 86_400)).count, 15)
        // the first session is a normal learning session of the start lesson
        let plan = engine.planSession(type: .learning, slot: .morning, day: TestSupport.day(0), learner: learner, now: now, seed: 1)
        XCTAssertEqual(plan.lessonId, "en.l35")
        XCTAssertTrue((8...12).contains(plan.items.filter { $0.exerciseId != nil }.count))
    }
}

final class DictionaryTests: XCTestCase {
    var engine: LearningEngine!
    override func setUpWithError() throws { engine = try TestSupport.fixtureEngine() }

    func testLookupFindsInflectionsAndContractions() {
        XCTAssertEqual(engine.lookup("go")?.word, "go")
        XCTAssertEqual(engine.lookup("went")?.word, "go")
        XCTAssertEqual(engine.lookup("Went.")?.word, "go")
        XCTAssertEqual(engine.lookup("goes")?.word, "go")
        XCTAssertEqual(engine.lookup("gone")?.word, "go")
        XCTAssertEqual(engine.lookup("children")?.word, "child")
        XCTAssertEqual(engine.lookup("happier")?.word, "happy")
        XCTAssertEqual(engine.lookup("watches")?.word, "watch")
        XCTAssertEqual(engine.lookup("was")?.word, "be")
        XCTAssertEqual(engine.lookup("doesn’t")?.word, "doesn't")      // own entry, curly apostrophe
        XCTAssertEqual(engine.lookup("DOESN'T")?.word, "doesn't")
        XCTAssertEqual(engine.lookup("Thank you")?.word, "thank you")
        // contractions without an entry: the auxiliary
        XCTAssertEqual(engine.lookup("isn't")?.word, "be")
        XCTAssertEqual(engine.lookup("wasn't")?.word, "be")
        // regular inflections
        XCTAssertEqual(engine.lookup("working")?.word, "work")
        XCTAssertEqual(engine.lookup("liked")?.word, "like")
        XCTAssertEqual(engine.lookup("teachers")?.word, "teacher")
        XCTAssertEqual(engine.lookup("living")?.word, "live")
        XCTAssertEqual(engine.lookup("teacher's")?.word, "teacher")
        XCTAssertNil(engine.lookup("xylophone"))
        XCTAssertNil(engine.lookup(""))
        XCTAssertNil(engine.lookup("  ...  "))
    }

    func testSearch() {
        XCTAssertEqual(engine.searchDictionary("wor").first?.word, "work")
        XCTAssertEqual(engine.searchDictionary("fatigue").first?.word, "tired")          // French translation, accent-insensitive
        XCTAssertEqual(engine.searchDictionary("FATIGUÉ").first?.word, "tired")
        XCTAssertEqual(engine.searchDictionary("aller").first?.word, "go")
        let sub = engine.searchDictionary("ceiv").map { $0.word }
        XCTAssertEqual(sub, ["receive"])                                                  // substring
        let ord = engine.searchDictionary("t").map { $0.word }
        XCTAssertEqual(ord.first, "teacher")                                              // prefix matches first
        XCTAssertEqual(engine.searchDictionary("t", limit: 3).count, 3)
        XCTAssertTrue(engine.searchDictionary("zzzz").isEmpty)
        XCTAssertEqual(Set(ord).count, ord.count)
    }

    func testTrackWord() {
        var learner = LearnerSnapshot()
        let now = TestSupport.date(day: 0, hour: 10)
        let state = engine.trackWord(dictionaryItemId: "en.d.go", learner: &learner, now: now)
        XCTAssertEqual(state?.unitId, "en.v.go")
        XCTAssertEqual(state?.source, .dictionary)
        XCTAssertEqual(state?.stability, 0.5)
        XCTAssertEqual(state?.nextReviewAt.timeIntervalSince(now), 4 * 3600)
        XCTAssertEqual(learner.memoryStates["en.v.go"], state)
        XCTAssertNotEqual(engine.mastery(of: "en.v.go", learner: learner, now: now).level, .mastered)
        XCTAssertEqual(engine.mastery(of: "en.v.go", learner: learner, now: now).level, .learning)
        // tracking again keeps the existing state
        let later = engine.trackWord(dictionaryItemId: "en.d.go", learner: &learner, now: now.addingTimeInterval(100))
        XCTAssertEqual(later, state)
        // no unit: nil and nothing created
        XCTAssertNil(engine.trackWord(dictionaryItemId: "en.d.child", learner: &learner, now: now))
        XCTAssertNil(engine.trackWord(dictionaryItemId: "unknown", learner: &learner, now: now))
        XCTAssertEqual(learner.memoryStates.count, 1)
        // the tracked word is reviewed after ~4 h
        XCTAssertEqual(engine.dueReviews(learner: learner, now: now.addingTimeInterval(5 * 3600)).map { $0.unitId }, ["en.v.go"])
    }

    func testRealDictionary() throws {
        let engine = LearningEngine(bundle: try TestSupport.realBundle())
        XCTAssertEqual(engine.lookup("went")?.word, "go")
        XCTAssertNotNil(engine.lookup("doesn't"))
        XCTAssertNotNil(engine.lookup("children"))
        // every dictionary word and every listed form is found again
        var failures: [String] = []
        for item in engine.index.bundle.dictionary {
            if engine.lookup(item.word) == nil { failures.append(item.word) }
            for (_, form) in item.forms ?? [:] { for f in form.split(separator: "/") where engine.lookup(String(f)) == nil { failures.append(String(f)) } }
        }
        XCTAssertEqual(failures, [])
    }
}

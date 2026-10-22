import XCTest
@testable import LearningCore

/// Checks every subject bundle shipped in the app (App/Resources/Content/en.json, ar.json, cg.json) against the engine:
/// references resolve, model answers are accepted, anticipated mistakes are not, and two weeks of
/// three sessions a day run without getting stuck.
final class SubjectBundlesTests: XCTestCase {
    private static let subjects = ["en", "ar", "cg"]

    private func bundles() throws -> [(String, ContentBundle)] {
        var out: [(String, ContentBundle)] = []
        for code in Self.subjects {
            let url = TestSupport.repoRoot.appendingPathComponent("App/Resources/Content/\(code).json")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            out.append((code, try ContentBundle.decode(from: Data(contentsOf: url))))
        }
        if out.isEmpty { throw XCTSkip("no bundle in App/Resources/Content") }
        return out
    }

    func testReferencesResolveInEverySubject() throws {
        for (code, bundle) in try bundles() {
            let engine = LearningEngine(bundle: bundle)
            var missing: [String] = []
            for e in bundle.exercises + bundle.diagnostic + bundle.assessment {
                for u in e.unitIds where engine.unit(u) == nil { missing.append("\(e.id): unit \(u)") }
                if let l = e.lessonId, engine.lesson(l) == nil { missing.append("\(e.id): lesson \(l)") }
            }
            for l in bundle.lessons {
                for u in l.introduces + l.reviews + [l.grammarUnitId] where engine.unit(u) == nil { missing.append("\(l.id): unit \(u)") }
            }
            for u in bundle.units {
                for p in u.prerequisites where engine.unit(p) == nil { missing.append("\(u.id): prerequisite \(p)") }
            }
            for d in bundle.dictionary { if let u = d.unitId, engine.unit(u) == nil { missing.append("\(d.id): unit \(u)") } }
            XCTAssertEqual(missing, [], "\(code): unresolved references")
            print("\(code): \(bundle.lessons.count) lessons, \(bundle.exercises.count) exercises, \(bundle.dictionary.count) dictionary entries")
        }
    }

    /// New subjects only (the English corpus has its own report): every model and accepted answer is
    /// accepted, and no `equals` error pattern is.
    func testModelAnswersAcceptedInNewSubjects() throws {
        for (code, bundle) in try bundles() where code != "en" {
            let engine = LearningEngine(bundle: bundle)
            var problems: [String] = []
            for e in bundle.exercises {
                for sub in submissions(e) {
                    let ev = engine.evaluate(e, submission: sub)
                    if ev.isCorrect || (e.requirements != nil && ev.result == .pending) { continue }
                    problems.append("\(e.id): « \(sub.displayText) » → \(ev.result.rawValue)")
                }
                for p in e.errorPatterns ?? [] {
                    guard let eq = p.equals else { continue }
                    let sub: AnswerSubmission
                    switch e.type {
                    case .mcq: sub = .choice(eq)
                    case .reorder: sub = .ordering(eq.split(separator: " ").map(String.init))
                    case .match: continue
                    default: sub = .text(eq)
                    }
                    if engine.evaluate(e, submission: sub).isCorrect { problems.append("\(e.id): mistake « \(eq) » accepted") }
                }
            }
            for p in problems.prefix(80) { print("  \(code) \(p)") }
            XCTAssertEqual(problems.count, 0, "\(code): \(problems.count) answer problems")
        }
    }

    /// Two weeks, three sessions a day, up to three new lessons a day as in the app.
    func testTwoWeeksOfSessionsProgress() throws {
        for (code, bundle) in try bundles() {
            var config = EngineConfiguration.default
            config.maxNewLessonsPerDay = 3
            let engine = LearningEngine(bundle: bundle, configuration: config)
            var sim = Simulator(engine: engine, seed: 11)
            for d in 0..<14 { sim.runDay(d, assessmentIfDue: code == "en") }
            let empty = sim.records.filter { $0.plan.items.isEmpty }.count
            let learned = sim.learner.completedLessonIds.count
            print("\(code): \(learned) lessons completed in 14 days, \(sim.records.count) sessions, \(empty) empty")
            XCTAssertGreaterThanOrEqual(learned, min(10, bundle.lessons.count), "\(code): progression stuck")
            XCTAssertEqual(empty, 0, "\(code): empty sessions")
        }
    }

    private func submissions(_ e: Exercise) -> [AnswerSubmission] {
        switch e.type {
        case .mcq: return ([e.answer] + e.acceptedAnswers).map { .choice($0) }
        case .reorder: return ([e.answer] + e.acceptedAnswers).map { .ordering($0.split(separator: " ").map(String.init)) }
        case .match: return [.matches(e.pairs ?? [])]
        default: return ([e.answer] + e.acceptedAnswers).map { .text($0) }
        }
    }
}

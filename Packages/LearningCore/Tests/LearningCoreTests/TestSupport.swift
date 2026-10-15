import XCTest
@testable import LearningCore

/// Shared helpers of the test suite.
enum TestSupport {
    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static func realBundle() throws -> ContentBundle {
        let url = repoRoot.appendingPathComponent("Content/build/en.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("Content/build/en.json not built") }
        return try ContentBundle.decode(from: Data(contentsOf: url))
    }

    static func fixtureBundle() throws -> ContentBundle {
        guard let url = Bundle.module.url(forResource: "fixture-bundle", withExtension: "json", subdirectory: "Fixtures") else {
            throw XCTSkip("fixture missing")
        }
        return try ContentBundle.decode(from: Data(contentsOf: url))
    }

    static func fixtureEngine() throws -> LearningEngine { LearningEngine(bundle: try fixtureBundle()) }

    static var calendar: Calendar { Calendar.current }

    /// 09:00, 14:00 or 20:00 of the given day offset from a fixed start day.
    static let startDay = LocalDay(year: 2026, month: 3, day: 2)

    static func date(day offset: Int, hour: Int, minute: Int = 0) -> Date {
        let d = startDay.adding(days: offset, calendar: calendar)
        return d.date(at: TimeOfDay(hour: hour, minute: minute), calendar: calendar)!
    }

    static func day(_ offset: Int) -> LocalDay { startDay.adding(days: offset, calendar: calendar) }

    /// Correct submission for an exercise (model answer).
    static func modelSubmission(_ ex: Exercise) -> AnswerSubmission {
        switch ex.type {
        case .mcq: return .choice(ex.answer)
        case .reorder: return .ordering(TextNormalizer.tokens(ex.answer).isEmpty ? [] : ex.answer.split(separator: " ").map(String.init))
        case .match: return .matches(ex.pairs ?? [])
        default: return .text(ex.answer)
        }
    }

    static func wrongSubmission(_ ex: Exercise) -> AnswerSubmission {
        switch ex.type {
        case .mcq: return .choice((ex.options ?? []).first { $0 != ex.answer } ?? "zzz")
        case .reorder: return .ordering(ex.answer.split(separator: " ").map(String.init).reversed())
        case .match: return .matches((ex.pairs ?? []).map { MatchPair(left: $0.left, right: "xx") })
        default: return .text("zzz")
        }
    }
}

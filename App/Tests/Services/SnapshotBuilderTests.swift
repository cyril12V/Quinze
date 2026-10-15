import XCTest
import LearningCore
@testable import Quinze

/// LearnerSnapshot built from local storage rows (no database involved).
final class SnapshotBuilderTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_790_000_000)
    private let day = LocalDay(year: 2026, month: 10, day: 14)

    private func attempt(_ n: Int, result: AttemptResult = .correct) -> AttemptRecord {
        AttemptRecord(id: UUID(), exerciseId: "ex\(n)", sessionId: nil, unitIds: ["u\(n % 5)"], exerciseType: .mcq,
                      presentation: .choices, submittedAnswer: "a", result: result, errorCategory: nil, hintUsed: false,
                      isRemediation: false, durationSeconds: 3, answeredAt: origin.addingTimeInterval(Double(n) * 60))
    }

    private func memory(_ unit: String) -> MemoryState {
        MemoryState(unitId: unit, stability: 2, difficulty: 5, source: .lesson, firstSeenAt: origin,
                    nextReviewAt: origin.addingTimeInterval(86_400))
    }

    private func session(_ status: SessionStatus, lesson: String? = nil, type: SessionType = .learning,
                         completedAt: Date? = nil) -> SessionRecord {
        SessionRecord(id: UUID(), type: type, slot: type == .learning ? .morning : nil, day: day,
                      completedAt: completedAt, status: status, lessonId: lesson, updatedAt: origin)
    }

    private func placement(level: Int, placed: [String]) throws -> DiagnosticResult {
        let list = placed.map { "\"\($0)\"" }.joined(separator: ",")
        let json = """
        {"estimatedLevel": \(level), "levelLabel": "Bases acquises", "startLessonId": "en.l05", "placedLessonIds": [\(list)],
         "knownUnitIds": ["en.v.hello"], "answers": [], "topicScores": {"grammar": 0.5}}
        """
        return try JSONDecoder().decode(DiagnosticResult.self, from: Data(json.utf8))
    }

    func testEmptyStorageGivesEmptyLearner() {
        let snapshot = SnapshotBuilder.build(memoryStates: [], attempts: [], sessions: [], profile: .empty)
        XCTAssertEqual(snapshot, .empty)
    }

    func testKeepsTheMostRecentAttemptsOldestFirst() {
        let shuffled = (0..<700).map { attempt($0) }.shuffled()
        let snapshot = SnapshotBuilder.build(memoryStates: [], attempts: shuffled, sessions: [], profile: .empty, attemptLimit: 500)
        XCTAssertEqual(snapshot.recentAttempts.count, 500)
        XCTAssertEqual(snapshot.recentAttempts.first?.exerciseId, "ex200")
        XCTAssertEqual(snapshot.recentAttempts.last?.exerciseId, "ex699")
        XCTAssertEqual(snapshot.recentAttempts.map(\.answeredAt), snapshot.recentAttempts.map(\.answeredAt).sorted())
    }

    func testMemoryStatesAreIndexedByUnit() {
        let snapshot = SnapshotBuilder.build(memoryStates: [memory("en.g1"), memory("en.v.cat")], attempts: [], sessions: [], profile: .empty)
        XCTAssertEqual(Set(snapshot.memoryStates.keys), ["en.g1", "en.v.cat"])
        XCTAssertEqual(snapshot.memoryStates["en.g1"]?.unitId, "en.g1")
    }

    func testCompletedLessonsComeOnlyFromCompletedSessions() {
        let snapshot = SnapshotBuilder.build(memoryStates: [], attempts: [], sessions: [
            session(.completed, lesson: "en.l01"), session(.inProgress, lesson: "en.l02"),
            session(.expired, lesson: "en.l03"), session(.completed, lesson: nil)
        ], profile: .empty)
        XCTAssertEqual(snapshot.completedLessonIds, ["en.l01"])
    }

    func testLastAssessmentIsTheLatestCompletedAssessment() {
        let early = origin
        let late = origin.addingTimeInterval(86_400 * 3)
        let snapshot = SnapshotBuilder.build(memoryStates: [], attempts: [], sessions: [
            session(.completed, type: .assessment, completedAt: early), session(.completed, type: .assessment, completedAt: late),
            session(.inProgress, type: .assessment, completedAt: late.addingTimeInterval(1000)),
            session(.completed, type: .learning, completedAt: late.addingTimeInterval(5000))
        ], profile: .empty)
        XCTAssertEqual(snapshot.lastAssessmentAt, late)
    }

    func testPlacementFeedsPlacedLessonsLevelAndStartDate() throws {
        var profile = UserProfileRecord.empty
        profile.placement = try placement(level: 2, placed: ["en.l01", "en.l02"])
        profile.estimatedLevel = 1
        profile.startedAt = origin
        let snapshot = SnapshotBuilder.build(memoryStates: [], attempts: [], sessions: [], profile: profile)
        XCTAssertEqual(snapshot.placedLessonIds, ["en.l01", "en.l02"])
        XCTAssertEqual(snapshot.estimatedLevel, 2, "the diagnostic outcome wins over the self-assessment")
        XCTAssertEqual(snapshot.startedAt, origin)
    }

    func testSelfAssessedLevelIsUsedWhenTheDiagnosticWasSkipped() {
        var profile = UserProfileRecord.empty
        profile.estimatedLevel = 1
        let snapshot = SnapshotBuilder.build(memoryStates: [], attempts: [], sessions: [], profile: profile)
        XCTAssertEqual(snapshot.estimatedLevel, 1)
        XCTAssertTrue(snapshot.placedLessonIds.isEmpty)
    }

    func testProfileRecordDecodesOlderDataAndKeepsPlacement() throws {
        let json = #"{"languageId": "en", "onboardingCompleted": true}"#
        let profile = try JSONDecoder().decode(UserProfileRecord.self, from: Data(json.utf8))
        XCTAssertTrue(profile.onboardingCompleted)
        XCTAssertEqual(profile.onboardingStep, 0)
        XCTAssertNil(profile.placement)

        var full = UserProfileRecord.empty
        full.placement = try placement(level: 3, placed: ["en.l01"])
        let back = try JSONDecoder().decode(UserProfileRecord.self, from: JSONEncoder().encode(full))
        XCTAssertEqual(back, full)
    }
}

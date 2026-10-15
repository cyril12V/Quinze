import XCTest
import LearningCore
@testable import Quinze

/// Wire format of docs/contracts/backend.md: snake_case keys, ISO 8601 UTC dates, explicit nulls.
final class SyncDTOTests: XCTestCase {
    // 2026-10-13T07:12:44.120Z
    private let reference = Date(timeIntervalSince1970: 1_791_875_564.12)

    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    private func attempt(session: UUID? = UUID(), category: ErrorCategory? = nil,
                         result: AttemptResult = .correct) -> AttemptRecord {
        AttemptRecord(id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                      exerciseId: "en.l20.e03", sessionId: session, unitIds: ["en.g15.present_simple_negative"],
                      exerciseType: .fillBlank, presentation: .choices, submittedAnswer: "go", result: result,
                      errorCategory: category, hintUsed: false, isRemediation: true, durationSeconds: 8.2,
                      answeredAt: reference)
    }

    // MARK: Dates

    func testISODateFormatsMillisecondsInUTC() {
        XCTAssertEqual(ISODate.string(from: reference), "2026-10-13T07:12:44.120Z")
        XCTAssertEqual(ISODate.string(from: Date(timeIntervalSince1970: 0)), "1970-01-01T00:00:00.000Z")
        XCTAssertEqual(ISODate.string(from: Date(timeIntervalSince1970: 951_782_400)), "2000-02-29T00:00:00.000Z")
        XCTAssertEqual(ISODate.string(from: Date(timeIntervalSince1970: -86_400.5)), "1969-12-30T23:59:59.500Z")
    }

    func testISODateParsesServerVariants() throws {
        let expected = reference.timeIntervalSince1970
        let variants = ["2026-10-13T07:12:44.120Z", "2026-10-13T09:12:44.120+02:00",
                        "2026-10-13T07:12:44.120123+00:00", "2026-10-13T07:12:44.12+0000",
                        "2026-10-13T06:12:44.120-01:00"]
        for text in variants {
            let parsed = try XCTUnwrap(ISODate.date(from: text), text)
            XCTAssertEqual(parsed.timeIntervalSince1970, expected, accuracy: 0.001, text)
        }
        XCTAssertEqual(try XCTUnwrap(ISODate.date(from: "2026-10-13T07:12:44Z")).timeIntervalSince1970, 1_791_875_564, accuracy: 0.001)
        XCTAssertNil(ISODate.date(from: "13/10/2026"))
        XCTAssertNil(ISODate.date(from: "2026-13-45T00:00:00Z"))
        XCTAssertNil(ISODate.date(from: ""))
    }

    func testISODateRoundTrip() throws {
        for seconds in [0.0, 1.5, 1_791_875_564.12, 4_102_444_800.999, 951_868_799.001] {
            let date = Date(timeIntervalSince1970: seconds)
            let back = try XCTUnwrap(ISODate.date(from: ISODate.string(from: date)))
            XCTAssertEqual(back.timeIntervalSince1970, seconds, accuracy: 0.0006)
        }
    }

    // MARK: Attempts

    func testAttemptEncodesContractKeysWithExplicitNulls() throws {
        let dto = AttemptDTO(record: attempt(session: nil), updatedAt: reference)
        let json = try jsonObject(dto)
        XCTAssertEqual(Set(json.keys), ["id", "exercise_id", "session_id", "unit_ids", "exercise_type", "presentation",
                                        "submitted_answer", "result", "error_category", "hint_used", "is_remediation",
                                        "duration_ms", "answered_at", "updated_at"])
        XCTAssertTrue(json["session_id"] is NSNull)
        XCTAssertTrue(json["error_category"] is NSNull)
        XCTAssertEqual(json["id"] as? String, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(json["exercise_type"] as? String, "fill_blank")
        XCTAssertEqual(json["presentation"] as? String, "choices")
        XCTAssertEqual(json["duration_ms"] as? Int, 8200)
        XCTAssertEqual(json["answered_at"] as? String, "2026-10-13T07:12:44.120Z")
        XCTAssertEqual(json["is_remediation"] as? Bool, true)
    }

    func testAttemptResultsUseContractVocabulary() throws {
        let typo = AttemptDTO(record: attempt(category: .spelling, result: .correctWithTypo), updatedAt: reference)
        XCTAssertEqual(typo.result, "correct_typo")
        XCTAssertEqual(typo.errorCategory, "spelling")
        XCTAssertEqual(AttemptDTO(record: attempt(category: .verbTense, result: .pending), updatedAt: reference).errorCategory, "verb_tense")
        XCTAssertEqual(AttemptDTO(record: attempt(result: .pending), updatedAt: reference).result, "pending")
    }

    func testAttemptDecodesContractExampleAndMapsToRecord() throws {
        let text = """
        {"id": "11111111-2222-3333-4444-555555555555", "exercise_id": "en.l20.e03", "session_id": null,
         "unit_ids": ["en.g15.present_simple_negative"], "exercise_type": "fill_blank", "presentation": "choices",
         "submitted_answer": "go", "result": "correct", "error_category": null, "hint_used": false,
         "is_remediation": false, "duration_ms": 8200, "answered_at": "2026-10-13T07:12:44.120Z",
         "updated_at": "2026-10-13T07:12:44.120Z", "server_updated_at": "2026-10-13T07:12:45.000Z", "user_id": "x"}
        """
        let dto = try JSONDecoder().decode(AttemptDTO.self, from: Data(text.utf8))
        let stamped = try XCTUnwrap(dto.toRecord())
        XCTAssertEqual(stamped.value.exerciseId, "en.l20.e03")
        XCTAssertNil(stamped.value.sessionId)
        XCTAssertEqual(stamped.value.durationSeconds, 8.2, accuracy: 0.0001)
        XCTAssertEqual(stamped.value.answeredAt.timeIntervalSince1970, reference.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(stamped.value.exerciseType, .fillBlank)
        XCTAssertEqual(stamped.value.result, .correct)
    }

    func testAttemptWithUnknownEnumValueIsRejectedNotCrashing() {
        var dto = AttemptDTO(record: attempt(), updatedAt: reference)
        dto.exerciseType = "hologram"
        XCTAssertNil(dto.toRecord())
    }

    // MARK: Sessions

    func testSessionRoundTripAndNeverSendsValidated() throws {
        let id = UUID()
        let record = SessionRecord(id: id, type: .learning, slot: .morning, day: LocalDay(year: 2026, month: 10, day: 13),
                                   scheduledAt: reference, startedAt: reference, completedAt: nil, status: .inProgress,
                                   lessonId: "en.l20", itemCount: 11, correctCount: 8, durationSeconds: 312,
                                   score: nil, emergencyUnlocked: false, updatedAt: reference)
        let dto = SessionDTO(record: record)
        let json = try jsonObject(dto)
        XCTAssertEqual(Set(json.keys), ["id", "session_type", "slot", "local_date", "scheduled_at", "started_at",
                                        "completed_at", "status", "lesson_id", "item_count", "correct_count",
                                        "duration_seconds", "score", "emergency_unlocked", "updated_at"])
        XCTAssertEqual(json["status"] as? String, "in_progress")
        XCTAssertEqual(json["local_date"] as? String, "2026-10-13")
        XCTAssertTrue(json["completed_at"] is NSNull)
        XCTAssertTrue(json["score"] is NSNull)
        let decoded = try JSONDecoder().decode(SessionDTO.self, from: JSONEncoder().encode(dto))
        let back = try XCTUnwrap(decoded.toRecord())
        XCTAssertEqual(back.id, id)
        XCTAssertEqual(back.status, .inProgress)
        XCTAssertEqual(back.slot, .morning)
        XCTAssertEqual(back.day, record.day)
        XCTAssertEqual(back.itemCount, 11)
    }

    func testSessionDecodesServerRowWithNullCounters() throws {
        let text = """
        {"id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", "session_type": "assessment", "slot": null,
         "local_date": "2026-10-13", "scheduled_at": null, "started_at": "2026-10-13T07:00:00.000000+00:00",
         "completed_at": "2026-10-13T07:05:00+00:00", "status": "completed", "lesson_id": null,
         "item_count": null, "correct_count": null, "duration_seconds": 300, "score": 0.75,
         "emergency_unlocked": null, "updated_at": "2026-10-13T07:05:00Z", "validated": true}
        """
        let dto = try JSONDecoder().decode(SessionDTO.self, from: Data(text.utf8))
        XCTAssertEqual(dto.validated, true)
        let record = try XCTUnwrap(dto.toRecord())
        XCTAssertEqual(record.type, .assessment)
        XCTAssertNil(record.slot)
        XCTAssertEqual(record.itemCount, 0)
        XCTAssertEqual(record.score, 0.75)
        XCTAssertEqual(record.durationSeconds, 300)
    }

    // MARK: Memory states, vocabulary, schedule

    func testMemoryStateRoundTripKeepsEverything() throws {
        let state = MemoryState(unitId: "en.g15.present_simple_negative", stability: 3.7, difficulty: 5.2, source: .lesson,
                                firstSeenAt: reference, nextReviewAt: reference.addingTimeInterval(86_400),
                                reviewCount: 4, lapseCount: 1, successCount: 3, failureCount: 1, noHintSuccessCount: 3,
                                delayedSuccessCount: 1, productionSuccessCount: 1,
                                successfulExerciseTypes: [.mcq, .fillBlank], recentResults: [true, false, true],
                                lastReviewAt: reference, updatedAt: reference)
        let dto = MemoryStateDTO(state: state)
        let json = try jsonObject(dto)
        XCTAssertEqual(json["learning_unit_id"] as? String, "en.g15.present_simple_negative")
        XCTAssertEqual(json["successful_exercise_types"] as? [String], ["fill_blank", "mcq"])
        XCTAssertEqual(json["recent_results"] as? [Bool], [true, false, true])
        XCTAssertEqual(json["no_hint_success_count"] as? Int, 3)
        XCTAssertEqual(json["source"] as? String, "lesson")
        let decoded = try JSONDecoder().decode(MemoryStateDTO.self, from: JSONEncoder().encode(dto))
        let back = try XCTUnwrap(decoded.toState())
        XCTAssertEqual(back.unitId, state.unitId)
        XCTAssertEqual(back.successfulExerciseTypes, state.successfulExerciseTypes)
        XCTAssertEqual(back.reviewCount, 4)
        XCTAssertEqual(back.nextReviewAt.timeIntervalSince1970, state.nextReviewAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testVocabularyDTO() throws {
        let record = VocabularyRecord(dictionaryItemId: "en.d.through", addedAt: reference, status: .learning, updatedAt: reference)
        let json = try jsonObject(VocabularyDTO(record: record))
        XCTAssertEqual(Set(json.keys), ["dictionary_item_id", "added_at", "learning_status", "updated_at"])
        XCTAssertEqual(VocabularyDTO(record: record).toRecord(), record.withTimestampsRounded())
    }

    func testScheduleDTOUsesHHmmAndParsesPostgresTime() throws {
        let schedule = DailySchedule(morning: TimeOfDay(hour: 9, minute: 5), afternoon: TimeOfDay(hour: 14, minute: 0),
                                     evening: TimeOfDay(hour: 20, minute: 30), timeZoneIdentifier: "Europe/Paris",
                                     enabled: true, safetyWindowMinutes: 90, earlyStartMinutes: 45)
        let dto = ScheduleDTO(schedule: schedule, updatedAt: reference, userId: "u1")
        let json = try jsonObject(dto)
        XCTAssertEqual(json["morning_time"] as? String, "09:05")
        XCTAssertEqual(json["evening_time"] as? String, "20:30")
        XCTAssertEqual(json["safety_window_minutes"] as? Int, 90)
        XCTAssertEqual(json["user_id"] as? String, "u1")
        XCTAssertEqual(dto.toSchedule(), schedule)

        let server = """
        {"morning_time": "09:00:00", "afternoon_time": "14:00:00", "evening_time": "20:00:00", "timezone": "Europe/Paris",
         "enabled": true, "safety_window_minutes": 120, "early_start_minutes": 60, "updated_at": "2026-10-13T07:00:00Z"}
        """
        let decoded = try JSONDecoder().decode(ScheduleDTO.self, from: Data(server.utf8))
        XCTAssertEqual(decoded.toSchedule()?.morning, TimeOfDay(hour: 9, minute: 0))
        XCTAssertNil(decoded.userId)
    }

    // MARK: sync_push / sync_pull

    func testPushParamsShape() throws {
        var payload = SyncPushPayload(languageId: "en")
        payload.attempts = [AttemptDTO(record: attempt(), updatedAt: reference)]
        let json = try jsonObject(SyncPushParams(payload: payload))
        XCTAssertEqual(Set(json.keys), ["payload"])
        let inner = try XCTUnwrap(json["payload"] as? [String: Any])
        XCTAssertEqual(Set(inner.keys), ["language_id", "attempts", "sessions", "memory_states", "vocabulary"])
        XCTAssertEqual(inner["language_id"] as? String, "en")
        XCTAssertEqual((inner["attempts"] as? [Any])?.count, 1)
        XCTAssertEqual((inner["sessions"] as? [Any])?.count, 0)
        XCTAssertFalse(payload.isEmpty)
        XCTAssertTrue(SyncPushPayload(languageId: "en").isEmpty)
    }

    func testPullParamsUseSQLArgumentNames() throws {
        let json = try jsonObject(SyncPullParams(languageId: "en", since: SyncCursor.epoch))
        XCTAssertEqual(json["p_language_id"] as? String, "en")
        XCTAssertEqual(json["p_since"] as? String, "1970-01-01T00:00:00Z")
        XCTAssertEqual(try jsonObject(ManifestParams(languageId: "en"))["p_language_id"] as? String, "en")
    }

    func testPullResponseDecodesContractAndDropsBrokenRows() throws {
        let text = """
        {"server_time": "2026-10-13T07:12:45.500Z",
         "user_language": {"estimated_level": 1, "start_lesson_sequence": 10, "placement": {"garbage": true},
                           "started_at": "2026-10-01T08:00:00Z", "updated_at": "2026-10-01T08:00:00Z"},
         "schedule": {"morning_time": "09:00", "afternoon_time": "14:00", "evening_time": "20:00",
                      "timezone": "Europe/Paris", "enabled": true, "safety_window_minutes": 120,
                      "early_start_minutes": 60, "updated_at": "2026-10-01T08:00:00Z"},
         "sessions": [{"id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", "session_type": "learning", "slot": "morning",
                       "local_date": "2026-10-13", "status": "completed", "updated_at": "2026-10-13T07:05:00Z"},
                      {"session_type": "learning"}],
         "memory_states": [], "vocabulary": [], "attempts": []}
        """
        let response = try JSONDecoder().decode(SyncPullResponse.self, from: Data(text.utf8))
        XCTAssertEqual(response.serverTime, "2026-10-13T07:12:45.500Z")
        XCTAssertEqual(response.sessions.count, 1)
        XCTAssertEqual(response.droppedRows, 1)
        XCTAssertEqual(response.userLanguage?.estimatedLevel, 1)
        XCTAssertNil(response.userLanguage?.placement, "a malformed placement must not fail the pull")
        XCTAssertEqual(response.schedule?.toSchedule()?.evening, TimeOfDay(hour: 20, minute: 0))
    }

    func testPullResponseAcceptsNullUserLanguageAndMissingArrays() throws {
        let text = #"{"server_time": "2026-10-13T07:12:45Z", "user_language": null, "schedule": null}"#
        let response = try JSONDecoder().decode(SyncPullResponse.self, from: Data(text.utf8))
        XCTAssertNil(response.userLanguage)
        XCTAssertNil(response.schedule)
        XCTAssertTrue(response.attempts.isEmpty && response.sessions.isEmpty && response.memoryStates.isEmpty)
    }

    func testPushResponseToleratesMissingCounters() throws {
        let text = #"{"server_time": "2026-10-13T07:12:45Z", "accepted": {"attempts": 12, "sessions": 1}, "rejected": {"attempts": 2}}"#
        let response = try JSONDecoder().decode(SyncPushResponse.self, from: Data(text.utf8))
        XCTAssertEqual(response.accepted["attempts"], 12)
        XCTAssertEqual(response.rejected.values.reduce(0, +), 2)
    }
}

private extension VocabularyRecord {
    /// The wire format keeps millisecond precision only.
    func withTimestampsRounded() -> VocabularyRecord {
        func round(_ d: Date) -> Date { Date(timeIntervalSince1970: (d.timeIntervalSince1970 * 1000).rounded() / 1000) }
        return VocabularyRecord(dictionaryItemId: dictionaryItemId, addedAt: round(addedAt), status: status, updatedAt: round(updatedAt))
    }
}

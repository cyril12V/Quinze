import Foundation
import LearningCore

// Wire formats of docs/contracts/backend.md (client side). Explicit snake_case CodingKeys; every date is an
// ISO 8601 UTC string handled here, so nothing depends on the SDK's encoder/decoder settings.

// MARK: - Cursor

enum SyncCursor {
    /// `p_since` of a full restore (new iPhone).
    static let epoch = "1970-01-01T00:00:00Z"
}

// MARK: - Dates

enum ISODate {
    /// "2026-10-13T07:12:44.120Z"
    static func string(from date: Date) -> String {
        let totalMs = Int((date.timeIntervalSince1970 * 1000).rounded())
        let secs = floorDiv(totalMs, 1000)
        let ms = totalMs - secs * 1000
        let days = floorDiv(secs, 86_400)
        let secondOfDay = secs - days * 86_400
        let (y, m, d) = civilFromDays(days)
        return "\(pad(y, 4))-\(pad(m, 2))-\(pad(d, 2))T\(pad(secondOfDay / 3600, 2)):\(pad((secondOfDay % 3600) / 60, 2)):\(pad(secondOfDay % 60, 2)).\(pad(ms, 3))Z"
    }

    /// Accepts "…Z", "…+00:00", "…+0000", "…+01", with or without fractional seconds (Postgres emits microseconds).
    static func date(from string: String) -> Date? {
        let u = Array(string.utf8)
        let n = u.count
        guard n >= 19 else { return nil }
        func num(_ a: Int, _ b: Int) -> Int? {
            guard b <= n else { return nil }
            var v = 0
            for i in a..<b {
                let c = Int(u[i]) - 48
                guard c >= 0, c <= 9 else { return nil }
                v = v * 10 + c
            }
            return v
        }
        guard let y = num(0, 4), let mo = num(5, 7), let d = num(8, 10),
              let h = num(11, 13), let mi = num(14, 16), let s = num(17, 19),
              u[4] == 45, u[7] == 45, u[10] == 84 || u[10] == 32, u[13] == 58, u[16] == 58,
              (1...12).contains(mo), (1...31).contains(d), h < 24, mi < 60, s < 61 else { return nil }
        var i = 19
        var fraction = 0.0
        if i < n, u[i] == 46 {
            i += 1
            var scale = 0.1
            while i < n, u[i] >= 48, u[i] <= 57 {
                fraction += Double(u[i] - 48) * scale
                scale /= 10
                i += 1
            }
        }
        var offset = 0
        if i < n {
            switch u[i] {
            case 90, 122:
                break
            case 43, 45:
                let sign = u[i] == 43 ? 1 : -1
                i += 1
                guard let oh = num(i, i + 2) else { return nil }
                i += 2
                if i < n, u[i] == 58 { i += 1 }
                var om = 0
                if i < n {
                    guard let m = num(i, i + 2) else { return nil }
                    om = m
                }
                offset = sign * (oh * 3600 + om * 60)
            default:
                return nil
            }
        }
        let seconds = daysFromCivil(y, mo, d) * 86_400 + h * 3600 + mi * 60 + s - offset
        return Date(timeIntervalSince1970: Double(seconds) + fraction)
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let s = String(value)
        return String(repeating: "0", count: max(0, width - s.count)) + s
    }

    private static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }

    /// Days since 1970-01-01 of a proleptic Gregorian date.
    private static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    private static func civilFromDays(_ days: Int) -> (Int, Int, Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }
}

// MARK: - Attempts

struct AttemptDTO: Codable, Sendable, Equatable {
    var id: String
    var exerciseId: String
    var sessionId: String?
    var unitIds: [String]
    var exerciseType: String
    var presentation: String
    var submittedAnswer: String
    var result: String
    var errorCategory: String?
    var hintUsed: Bool
    var isRemediation: Bool
    var durationMs: Int
    var answeredAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case exerciseId = "exercise_id"
        case sessionId = "session_id"
        case unitIds = "unit_ids"
        case exerciseType = "exercise_type"
        case presentation
        case submittedAnswer = "submitted_answer"
        case result
        case errorCategory = "error_category"
        case hintUsed = "hint_used"
        case isRemediation = "is_remediation"
        case durationMs = "duration_ms"
        case answeredAt = "answered_at"
        case updatedAt = "updated_at"
    }

    /// Nullable fields are sent as explicit `null` (as in the contract examples).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(exerciseId, forKey: .exerciseId)
        try c.encode(sessionId, forKey: .sessionId)
        try c.encode(unitIds, forKey: .unitIds)
        try c.encode(exerciseType, forKey: .exerciseType)
        try c.encode(presentation, forKey: .presentation)
        try c.encode(submittedAnswer, forKey: .submittedAnswer)
        try c.encode(result, forKey: .result)
        try c.encode(errorCategory, forKey: .errorCategory)
        try c.encode(hintUsed, forKey: .hintUsed)
        try c.encode(isRemediation, forKey: .isRemediation)
        try c.encode(durationMs, forKey: .durationMs)
        try c.encode(answeredAt, forKey: .answeredAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

extension AttemptDTO {
    init(record r: AttemptRecord, updatedAt: Date) {
        self.init(id: r.id.uuidString.lowercased(),
                  exerciseId: r.exerciseId,
                  sessionId: r.sessionId?.uuidString.lowercased(),
                  unitIds: r.unitIds,
                  exerciseType: r.exerciseType.rawValue,
                  presentation: r.presentation.rawValue,
                  submittedAnswer: r.submittedAnswer,
                  result: r.result.rawValue,
                  errorCategory: r.errorCategory?.rawValue,
                  hintUsed: r.hintUsed,
                  isRemediation: r.isRemediation,
                  durationMs: Int((r.durationSeconds * 1000).rounded()),
                  answeredAt: ISODate.string(from: r.answeredAt),
                  updatedAt: ISODate.string(from: updatedAt))
    }

    func toRecord() -> Stamped<AttemptRecord>? {
        guard let uuid = UUID(uuidString: id),
              let type = ExerciseType(rawValue: exerciseType),
              let mode = PresentationMode(rawValue: presentation),
              let outcome = AttemptResult(rawValue: result),
              let answered = ISODate.date(from: answeredAt) else { return nil }
        let record = AttemptRecord(id: uuid, exerciseId: exerciseId,
                                   sessionId: sessionId.flatMap { UUID(uuidString: $0) },
                                   unitIds: unitIds, exerciseType: type, presentation: mode,
                                   submittedAnswer: submittedAnswer, result: outcome,
                                   errorCategory: errorCategory.flatMap { ErrorCategory(rawValue: $0) },
                                   hintUsed: hintUsed, isRemediation: isRemediation,
                                   durationSeconds: Double(durationMs) / 1000, answeredAt: answered)
        return Stamped(value: record, updatedAt: ISODate.date(from: updatedAt) ?? answered)
    }
}

// MARK: - Sessions

struct SessionDTO: Codable, Sendable, Equatable {
    var id: String
    var sessionType: String
    var slot: String?
    var localDate: String
    var scheduledAt: String?
    var startedAt: String?
    var completedAt: String?
    var status: String
    var lessonId: String?
    var itemCount: Int
    var correctCount: Int
    var durationSeconds: Int
    var score: Double?
    var emergencyUnlocked: Bool
    var updatedAt: String
    /// Set by the server (pull only, never sent).
    var validated: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case sessionType = "session_type"
        case slot
        case localDate = "local_date"
        case scheduledAt = "scheduled_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case status
        case lessonId = "lesson_id"
        case itemCount = "item_count"
        case correctCount = "correct_count"
        case durationSeconds = "duration_seconds"
        case score
        case emergencyUnlocked = "emergency_unlocked"
        case updatedAt = "updated_at"
        case validated
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sessionType, forKey: .sessionType)
        try c.encode(slot, forKey: .slot)
        try c.encode(localDate, forKey: .localDate)
        try c.encode(scheduledAt, forKey: .scheduledAt)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(completedAt, forKey: .completedAt)
        try c.encode(status, forKey: .status)
        try c.encode(lessonId, forKey: .lessonId)
        try c.encode(itemCount, forKey: .itemCount)
        try c.encode(correctCount, forKey: .correctCount)
        try c.encode(durationSeconds, forKey: .durationSeconds)
        try c.encode(score, forKey: .score)
        try c.encode(emergencyUnlocked, forKey: .emergencyUnlocked)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

extension SessionDTO {
    /// Tolerant decoding of server rows (counters may be null on old rows).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  sessionType: try c.decode(String.self, forKey: .sessionType),
                  slot: try c.decodeIfPresent(String.self, forKey: .slot),
                  localDate: try c.decode(String.self, forKey: .localDate),
                  scheduledAt: try c.decodeIfPresent(String.self, forKey: .scheduledAt),
                  startedAt: try c.decodeIfPresent(String.self, forKey: .startedAt),
                  completedAt: try c.decodeIfPresent(String.self, forKey: .completedAt),
                  status: try c.decode(String.self, forKey: .status),
                  lessonId: try c.decodeIfPresent(String.self, forKey: .lessonId),
                  itemCount: try c.decodeIfPresent(Int.self, forKey: .itemCount) ?? 0,
                  correctCount: try c.decodeIfPresent(Int.self, forKey: .correctCount) ?? 0,
                  durationSeconds: try c.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 0,
                  score: try c.decodeIfPresent(Double.self, forKey: .score),
                  emergencyUnlocked: try c.decodeIfPresent(Bool.self, forKey: .emergencyUnlocked) ?? false,
                  updatedAt: try c.decode(String.self, forKey: .updatedAt),
                  validated: try c.decodeIfPresent(Bool.self, forKey: .validated))
    }

    init(record s: SessionRecord) {
        self.init(id: s.id.uuidString.lowercased(),
                  sessionType: s.type.rawValue,
                  slot: s.slot?.rawValue,
                  localDate: s.day.isoString,
                  scheduledAt: s.scheduledAt.map(ISODate.string(from:)),
                  startedAt: s.startedAt.map(ISODate.string(from:)),
                  completedAt: s.completedAt.map(ISODate.string(from:)),
                  status: s.status.rawValue,
                  lessonId: s.lessonId,
                  itemCount: s.itemCount,
                  correctCount: s.correctCount,
                  durationSeconds: s.durationSeconds,
                  score: s.score,
                  emergencyUnlocked: s.emergencyUnlocked,
                  updatedAt: ISODate.string(from: s.updatedAt),
                  validated: nil)
    }

    func toRecord() -> SessionRecord? {
        guard let uuid = UUID(uuidString: id),
              let type = SessionType(rawValue: sessionType),
              let day = LocalDay(isoString: localDate),
              let state = SessionStatus(rawValue: status),
              let updated = ISODate.date(from: updatedAt) else { return nil }
        return SessionRecord(id: uuid, type: type, slot: slot.flatMap { SessionSlot(rawValue: $0) }, day: day,
                             scheduledAt: scheduledAt.flatMap(ISODate.date(from:)),
                             startedAt: startedAt.flatMap(ISODate.date(from:)),
                             completedAt: completedAt.flatMap(ISODate.date(from:)),
                             status: state, lessonId: lessonId, itemCount: itemCount, correctCount: correctCount,
                             durationSeconds: durationSeconds, score: score, emergencyUnlocked: emergencyUnlocked,
                             updatedAt: updated)
    }
}

// MARK: - Memory states

struct MemoryStateDTO: Codable, Sendable, Equatable {
    var learningUnitId: String
    var stability: Double
    var difficulty: Double
    var reviewCount: Int
    var lapseCount: Int
    var successCount: Int
    var failureCount: Int
    var noHintSuccessCount: Int
    var delayedSuccessCount: Int
    var productionSuccessCount: Int
    var successfulExerciseTypes: [String]
    var recentResults: [Bool]
    var source: String
    var firstSeenAt: String
    var lastReviewAt: String?
    var nextReviewAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case learningUnitId = "learning_unit_id"
        case stability, difficulty
        case reviewCount = "review_count"
        case lapseCount = "lapse_count"
        case successCount = "success_count"
        case failureCount = "failure_count"
        case noHintSuccessCount = "no_hint_success_count"
        case delayedSuccessCount = "delayed_success_count"
        case productionSuccessCount = "production_success_count"
        case successfulExerciseTypes = "successful_exercise_types"
        case recentResults = "recent_results"
        case source
        case firstSeenAt = "first_seen_at"
        case lastReviewAt = "last_review_at"
        case nextReviewAt = "next_review_at"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(learningUnitId, forKey: .learningUnitId)
        try c.encode(stability, forKey: .stability)
        try c.encode(difficulty, forKey: .difficulty)
        try c.encode(reviewCount, forKey: .reviewCount)
        try c.encode(lapseCount, forKey: .lapseCount)
        try c.encode(successCount, forKey: .successCount)
        try c.encode(failureCount, forKey: .failureCount)
        try c.encode(noHintSuccessCount, forKey: .noHintSuccessCount)
        try c.encode(delayedSuccessCount, forKey: .delayedSuccessCount)
        try c.encode(productionSuccessCount, forKey: .productionSuccessCount)
        try c.encode(successfulExerciseTypes, forKey: .successfulExerciseTypes)
        try c.encode(recentResults, forKey: .recentResults)
        try c.encode(source, forKey: .source)
        try c.encode(firstSeenAt, forKey: .firstSeenAt)
        try c.encode(lastReviewAt, forKey: .lastReviewAt)
        try c.encode(nextReviewAt, forKey: .nextReviewAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

extension MemoryStateDTO {
    init(state s: MemoryState) {
        self.init(learningUnitId: s.unitId, stability: s.stability, difficulty: s.difficulty,
                  reviewCount: s.reviewCount, lapseCount: s.lapseCount, successCount: s.successCount,
                  failureCount: s.failureCount, noHintSuccessCount: s.noHintSuccessCount,
                  delayedSuccessCount: s.delayedSuccessCount, productionSuccessCount: s.productionSuccessCount,
                  successfulExerciseTypes: s.successfulExerciseTypes.map(\.rawValue).sorted(),
                  recentResults: s.recentResults, source: s.source.rawValue,
                  firstSeenAt: ISODate.string(from: s.firstSeenAt),
                  lastReviewAt: s.lastReviewAt.map(ISODate.string(from:)),
                  nextReviewAt: ISODate.string(from: s.nextReviewAt),
                  updatedAt: ISODate.string(from: s.updatedAt))
    }

    func toState() -> MemoryState? {
        guard let first = ISODate.date(from: firstSeenAt),
              let next = ISODate.date(from: nextReviewAt),
              let updated = ISODate.date(from: updatedAt) else { return nil }
        return MemoryState(unitId: learningUnitId, stability: stability, difficulty: difficulty,
                           source: MemorySource(rawValue: source) ?? .lesson, firstSeenAt: first, nextReviewAt: next,
                           reviewCount: reviewCount, lapseCount: lapseCount, successCount: successCount,
                           failureCount: failureCount, noHintSuccessCount: noHintSuccessCount,
                           delayedSuccessCount: delayedSuccessCount, productionSuccessCount: productionSuccessCount,
                           successfulExerciseTypes: Set(successfulExerciseTypes.compactMap { ExerciseType(rawValue: $0) }),
                           recentResults: recentResults, lastReviewAt: lastReviewAt.flatMap(ISODate.date(from:)),
                           updatedAt: updated)
    }
}

// MARK: - Vocabulary

struct VocabularyDTO: Codable, Sendable, Equatable {
    var dictionaryItemId: String
    var addedAt: String
    var learningStatus: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case dictionaryItemId = "dictionary_item_id"
        case addedAt = "added_at"
        case learningStatus = "learning_status"
        case updatedAt = "updated_at"
    }
}

extension VocabularyDTO {
    init(record v: VocabularyRecord) {
        self.init(dictionaryItemId: v.dictionaryItemId, addedAt: ISODate.string(from: v.addedAt),
                  learningStatus: v.status.rawValue, updatedAt: ISODate.string(from: v.updatedAt))
    }

    func toRecord() -> VocabularyRecord? {
        guard let added = ISODate.date(from: addedAt), let updated = ISODate.date(from: updatedAt) else { return nil }
        return VocabularyRecord(dictionaryItemId: dictionaryItemId, addedAt: added,
                                status: VocabularyStatus(rawValue: learningStatus) ?? .learning, updatedAt: updated)
    }
}

// MARK: - user_languages / daily_schedules (PostgREST upsert rows, also embedded in sync_pull)

struct UserLanguageDTO: Codable, Sendable, Equatable {
    var userId: String?
    var languageId: String?
    var estimatedLevel: Int?
    var startLessonSequence: Int?
    var placement: DiagnosticResult?
    var startedAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case languageId = "language_id"
        case estimatedLevel = "estimated_level"
        case startLessonSequence = "start_lesson_sequence"
        case placement
        case startedAt = "started_at"
        case updatedAt = "updated_at"
    }
}

extension UserLanguageDTO {
    /// A malformed `placement` never makes the whole pull fail.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(userId: try c.decodeIfPresent(String.self, forKey: .userId),
                  languageId: try c.decodeIfPresent(String.self, forKey: .languageId),
                  estimatedLevel: try c.decodeIfPresent(Int.self, forKey: .estimatedLevel),
                  startLessonSequence: try c.decodeIfPresent(Int.self, forKey: .startLessonSequence),
                  placement: try? c.decodeIfPresent(DiagnosticResult.self, forKey: .placement),
                  startedAt: try c.decodeIfPresent(String.self, forKey: .startedAt),
                  updatedAt: try c.decodeIfPresent(String.self, forKey: .updatedAt))
    }

    init(profile p: UserProfileRecord, userId: String) {
        self.init(userId: userId, languageId: p.languageId, estimatedLevel: p.estimatedLevel,
                  startLessonSequence: p.startLessonSequence, placement: p.placement,
                  startedAt: p.startedAt.map(ISODate.string(from:)),
                  updatedAt: ISODate.string(from: p.userLanguageUpdatedAt ?? p.startedAt ?? Date()))
    }
}

struct ScheduleDTO: Codable, Sendable, Equatable {
    var userId: String?
    var morningTime: String
    var afternoonTime: String
    var eveningTime: String
    var timezone: String?
    var enabled: Bool?
    var safetyWindowMinutes: Int?
    var earlyStartMinutes: Int?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case morningTime = "morning_time"
        case afternoonTime = "afternoon_time"
        case eveningTime = "evening_time"
        case timezone, enabled
        case safetyWindowMinutes = "safety_window_minutes"
        case earlyStartMinutes = "early_start_minutes"
        case updatedAt = "updated_at"
    }
}

extension ScheduleDTO {
    init(schedule s: DailySchedule, updatedAt: Date, userId: String?) {
        self.init(userId: userId, morningTime: s.morning.description, afternoonTime: s.afternoon.description,
                  eveningTime: s.evening.description, timezone: s.timeZoneIdentifier, enabled: s.enabled,
                  safetyWindowMinutes: s.safetyWindowMinutes, earlyStartMinutes: s.earlyStartMinutes,
                  updatedAt: ISODate.string(from: updatedAt))
    }

    /// Times may come back as "09:00:00" (Postgres `time`).
    func toSchedule() -> DailySchedule? {
        guard let m = TimeOfDay(string: morningTime), let a = TimeOfDay(string: afternoonTime),
              let e = TimeOfDay(string: eveningTime) else { return nil }
        return DailySchedule(morning: m, afternoon: a, evening: e,
                             timeZoneIdentifier: timezone ?? TimeZone.current.identifier,
                             enabled: enabled ?? true,
                             safetyWindowMinutes: safetyWindowMinutes ?? 120,
                             earlyStartMinutes: earlyStartMinutes ?? 60)
    }
}

// MARK: - sync_push / sync_pull / content_manifest

struct SyncPushPayload: Encodable, Sendable, Equatable {
    var languageId: String
    var attempts: [AttemptDTO] = []
    var sessions: [SessionDTO] = []
    var memoryStates: [MemoryStateDTO] = []
    var vocabulary: [VocabularyDTO] = []

    var isEmpty: Bool { attempts.isEmpty && sessions.isEmpty && memoryStates.isEmpty && vocabulary.isEmpty }

    enum CodingKeys: String, CodingKey {
        case languageId = "language_id"
        case attempts, sessions
        case memoryStates = "memory_states"
        case vocabulary
    }
}

/// RPC arguments: keys are the SQL argument names.
struct SyncPushParams: Encodable, Sendable, Equatable {
    var payload: SyncPushPayload
}

struct SyncPullParams: Encodable, Sendable, Equatable {
    var languageId: String
    var since: String

    enum CodingKeys: String, CodingKey {
        case languageId = "p_language_id"
        case since = "p_since"
    }
}

struct ManifestParams: Encodable, Sendable, Equatable {
    var languageId: String

    enum CodingKeys: String, CodingKey { case languageId = "p_language_id" }
}

struct ContentManifest: Decodable, Sendable, Equatable {
    var version: String
    var bundlePath: String
    var sha256: String
    var publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case version
        case bundlePath = "bundle_path"
        case sha256
        case publishedAt = "published_at"
    }
}

struct SyncPushResponse: Decodable, Sendable, Equatable {
    var serverTime: String?
    var accepted: [String: Int]
    var rejected: [String: Int]

    enum CodingKeys: String, CodingKey {
        case serverTime = "server_time"
        case accepted, rejected
    }

    init(serverTime: String?, accepted: [String: Int], rejected: [String: Int]) {
        self.serverTime = serverTime
        self.accepted = accepted
        self.rejected = rejected
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        serverTime = try c.decodeIfPresent(String.self, forKey: .serverTime)
        accepted = (try? c.decodeIfPresent([String: Int].self, forKey: .accepted)) ?? [:]
        rejected = (try? c.decodeIfPresent([String: Int].self, forKey: .rejected)) ?? [:]
    }
}

/// Decodes an element or yields nil instead of failing the whole array.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

struct SyncPullResponse: Decodable, Sendable {
    var serverTime: String
    var userLanguage: UserLanguageDTO?
    var schedule: ScheduleDTO?
    var sessions: [SessionDTO]
    var memoryStates: [MemoryStateDTO]
    var vocabulary: [VocabularyDTO]
    var attempts: [AttemptDTO]
    /// Rows the client could not decode (logged, never fatal).
    var droppedRows: Int

    enum CodingKeys: String, CodingKey {
        case serverTime = "server_time"
        case userLanguage = "user_language"
        case schedule, sessions
        case memoryStates = "memory_states"
        case vocabulary, attempts
    }

    init(serverTime: String, userLanguage: UserLanguageDTO? = nil, schedule: ScheduleDTO? = nil,
         sessions: [SessionDTO] = [], memoryStates: [MemoryStateDTO] = [], vocabulary: [VocabularyDTO] = [],
         attempts: [AttemptDTO] = [], droppedRows: Int = 0) {
        self.serverTime = serverTime
        self.userLanguage = userLanguage
        self.schedule = schedule
        self.sessions = sessions
        self.memoryStates = memoryStates
        self.vocabulary = vocabulary
        self.attempts = attempts
        self.droppedRows = droppedRows
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        serverTime = try c.decode(String.self, forKey: .serverTime)
        userLanguage = (try? c.decodeIfPresent(UserLanguageDTO.self, forKey: .userLanguage)) ?? nil
        schedule = (try? c.decodeIfPresent(ScheduleDTO.self, forKey: .schedule)) ?? nil
        var dropped = 0
        func rows<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> [T] {
            guard let lossy = try? c.decodeIfPresent([Lossy<T>].self, forKey: key) else { return [] }
            let good = lossy.compactMap(\.value)
            dropped += lossy.count - good.count
            return good
        }
        sessions = rows(SessionDTO.self, .sessions)
        memoryStates = rows(MemoryStateDTO.self, .memoryStates)
        vocabulary = rows(VocabularyDTO.self, .vocabulary)
        attempts = rows(AttemptDTO.self, .attempts)
        droppedRows = dropped
    }
}

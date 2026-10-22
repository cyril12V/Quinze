import Foundation
import LearningCore

// Value types persisted locally (JSON blobs in SwiftData) and exchanged with the sync layer.
// This file only depends on Foundation + LearningCore so that it stays easy to unit test.

enum SessionStatus: String, Codable, Sendable, Equatable {
    case scheduled
    case inProgress = "in_progress"
    case completed
    case expired
    case skipped
}

/// One learning session (a slot lesson, an assessment, an extra practice…).
struct SessionRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var type: SessionType
    var slot: SessionSlot?
    var day: LocalDay
    var scheduledAt: Date?
    var startedAt: Date?
    var completedAt: Date?
    var status: SessionStatus
    var lessonId: String?
    var itemCount: Int
    var correctCount: Int
    var durationSeconds: Int
    var score: Double?
    var emergencyUnlocked: Bool
    var updatedAt: Date
    /// Subject code ("en", "ar", "cg"). Nil in sessions saved before the v2: they are English.
    var subject: String?
    /// Learning sessions: false when the lesson was not validated (it will be retaken). Nil before v3.
    var lessonPassed: Bool?
    /// End-of-module exams: the module and whether the exam was passed.
    var examModule: Int?
    var examPassed: Bool?

    var subjectCode: String { subject ?? "en" }

    init(id: UUID, type: SessionType, slot: SessionSlot?, day: LocalDay, scheduledAt: Date? = nil,
         startedAt: Date? = nil, completedAt: Date? = nil, status: SessionStatus, lessonId: String? = nil,
         itemCount: Int = 0, correctCount: Int = 0, durationSeconds: Int = 0, score: Double? = nil,
         emergencyUnlocked: Bool = false, updatedAt: Date, subject: String? = nil) {
        self.subject = subject
        self.id = id
        self.type = type
        self.slot = slot
        self.day = day
        self.scheduledAt = scheduledAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.status = status
        self.lessonId = lessonId
        self.itemCount = itemCount
        self.correctCount = correctCount
        self.durationSeconds = durationSeconds
        self.score = score
        self.emergencyUnlocked = emergencyUnlocked
        self.updatedAt = updatedAt
    }
}

enum VocabularyStatus: String, Codable, Sendable, Equatable {
    case learning, known, mastered
}

/// A dictionary word the learner chose to learn ("Apprendre ce mot").
struct VocabularyRecord: Codable, Equatable, Sendable, Identifiable {
    var dictionaryItemId: String
    var addedAt: Date
    var status: VocabularyStatus
    var updatedAt: Date
    var id: String { dictionaryItemId }
}

/// A value together with the local `updatedAt` stamp of the row it comes from.
struct Stamped<Value: Sendable>: Sendable {
    let value: Value
    let updatedAt: Date
}

/// Profile, placement and onboarding progress of the signed-in learner (one row, JSON blob).
struct UserProfileRecord: Codable, Equatable, Sendable {
    /// Supabase user id owning the local data (lowercased UUID).
    var userId: String?
    var displayName: String?
    var languageId: String
    var selfAssessedLevel: Int?
    var estimatedLevel: Int?
    var startLessonSequence: Int?
    var placement: DiagnosticResult?
    var startedAt: Date?
    var onboardingCompleted: Bool
    var onboardingStep: Int
    /// `updated_at` of the `user_languages` row (client clock).
    var userLanguageUpdatedAt: Date?
    var userLanguageDirty: Bool
    /// `profiles.display_name` / notification prefs waiting to be pushed.
    var profileDirty: Bool

    static let empty = UserProfileRecord(userId: nil, displayName: nil, languageId: "en", selfAssessedLevel: nil,
                                         estimatedLevel: nil, startLessonSequence: nil, placement: nil, startedAt: nil,
                                         onboardingCompleted: false, onboardingStep: 0, userLanguageUpdatedAt: nil,
                                         userLanguageDirty: false, profileDirty: false)

    init(userId: String?, displayName: String?, languageId: String, selfAssessedLevel: Int?, estimatedLevel: Int?,
         startLessonSequence: Int?, placement: DiagnosticResult?, startedAt: Date?, onboardingCompleted: Bool,
         onboardingStep: Int, userLanguageUpdatedAt: Date?, userLanguageDirty: Bool, profileDirty: Bool) {
        self.userId = userId
        self.displayName = displayName
        self.languageId = languageId
        self.selfAssessedLevel = selfAssessedLevel
        self.estimatedLevel = estimatedLevel
        self.startLessonSequence = startLessonSequence
        self.placement = placement
        self.startedAt = startedAt
        self.onboardingCompleted = onboardingCompleted
        self.onboardingStep = onboardingStep
        self.userLanguageUpdatedAt = userLanguageUpdatedAt
        self.userLanguageDirty = userLanguageDirty
        self.profileDirty = profileDirty
    }

    /// Tolerant decoding: a field added later never invalidates data saved by an older version.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decodeIfPresent(String.self, forKey: .userId)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        languageId = try c.decodeIfPresent(String.self, forKey: .languageId) ?? "en"
        selfAssessedLevel = try c.decodeIfPresent(Int.self, forKey: .selfAssessedLevel)
        estimatedLevel = try c.decodeIfPresent(Int.self, forKey: .estimatedLevel)
        startLessonSequence = try c.decodeIfPresent(Int.self, forKey: .startLessonSequence)
        placement = try? c.decodeIfPresent(DiagnosticResult.self, forKey: .placement)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        onboardingStep = try c.decodeIfPresent(Int.self, forKey: .onboardingStep) ?? 0
        userLanguageUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .userLanguageUpdatedAt)
        userLanguageDirty = try c.decodeIfPresent(Bool.self, forKey: .userLanguageDirty) ?? false
        profileDirty = try c.decodeIfPresent(Bool.self, forKey: .profileDirty) ?? false
    }
}

/// Dotted numeric version comparison ("1.10.0" > "1.9.3").
enum ContentVersion {
    static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { part in
            Int(part.prefix(while: { $0.isNumber })) ?? 0
        }
    }

    static func isNewer(_ candidate: String, than current: String?) -> Bool {
        guard let current else { return true }
        let a = components(candidate)
        let b = components(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

extension UUID {
    /// Deterministic planner seed derived from a session id.
    var planSeed: UInt64 {
        let b = uuid
        let bytes: [UInt8] = [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7]
        return bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}

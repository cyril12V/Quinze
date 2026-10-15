import Foundation

// Learner-side state. All types are Codable value types so the app can persist them
// (SwiftData) and sync them (Supabase) without the engine knowing about either.

/// FSRS rating.
public enum ReviewGrade: Int, Codable, Sendable, Comparable {
    case again = 1, hard = 2, good = 3, easy = 4
    public static func < (lhs: ReviewGrade, rhs: ReviewGrade) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum MemorySource: String, Codable, Sendable {
    /// Taught in a lesson.
    case lesson
    /// Placed as probably known by the initial diagnostic (to be verified by early reviews).
    case diagnostic
    /// Added by the learner from the dictionary ("Apprendre ce mot").
    case dictionary
}

/// Spaced-repetition and mastery evidence for one learning unit (§12.2).
public struct MemoryState: Codable, Hashable, Sendable, Identifiable {
    public var id: String { unitId }
    public let unitId: String
    /// FSRS stability in days.
    public var stability: Double
    /// FSRS difficulty, 1 (easy) ... 10 (hard).
    public var difficulty: Double
    public var reviewCount: Int
    public var lapseCount: Int
    public var successCount: Int
    public var failureCount: Int
    public var noHintSuccessCount: Int
    /// Successes obtained at least `EngineConfiguration.delayedSuccessHours` after the previous review.
    public var delayedSuccessCount: Int
    /// Successes on production exercises (translation, free answer).
    public var productionSuccessCount: Int
    public var successfulExerciseTypes: Set<ExerciseType>
    /// Last results, oldest first (bounded by `EngineConfiguration.recentResultsLimit`).
    public var recentResults: [Bool]
    public var source: MemorySource
    public var firstSeenAt: Date
    public var lastReviewAt: Date?
    public var nextReviewAt: Date
    public var updatedAt: Date

    public init(unitId: String, stability: Double, difficulty: Double, source: MemorySource,
                firstSeenAt: Date, nextReviewAt: Date, reviewCount: Int = 0, lapseCount: Int = 0,
                successCount: Int = 0, failureCount: Int = 0, noHintSuccessCount: Int = 0,
                delayedSuccessCount: Int = 0, productionSuccessCount: Int = 0,
                successfulExerciseTypes: Set<ExerciseType> = [], recentResults: [Bool] = [],
                lastReviewAt: Date? = nil, updatedAt: Date? = nil) {
        self.unitId = unitId
        self.stability = stability
        self.difficulty = difficulty
        self.source = source
        self.firstSeenAt = firstSeenAt
        self.nextReviewAt = nextReviewAt
        self.reviewCount = reviewCount
        self.lapseCount = lapseCount
        self.successCount = successCount
        self.failureCount = failureCount
        self.noHintSuccessCount = noHintSuccessCount
        self.delayedSuccessCount = delayedSuccessCount
        self.productionSuccessCount = productionSuccessCount
        self.successfulExerciseTypes = successfulExerciseTypes
        self.recentResults = recentResults
        self.lastReviewAt = lastReviewAt
        self.updatedAt = updatedAt ?? firstSeenAt
    }
}

public enum AttemptResult: String, Codable, Sendable {
    case correct
    /// Accepted, with a spelling slip pointed out.
    case correctWithTypo = "correct_typo"
    case partial
    case incorrect
    /// Uncertain deterministic verdict waiting for AI grading (level 2). Ignored by scheduling until resolved.
    case pending

    public var countsAsSuccess: Bool { self == .correct || self == .correctWithTypo }
}

/// How an exercise is shown, decided by the planner (adaptive scaffolding, §13.1).
public enum PresentationMode: String, Codable, Sendable {
    /// Options are shown (mcq, or fill_blank with its word bank).
    case choices
    /// Free typing (fill_blank without word bank, translation, free_answer).
    case typed
    /// Tokens to drag into order (reorder).
    case tokens
    /// Pairs to associate (match).
    case pairs
}

/// The learner's answer.
public enum AnswerSubmission: Codable, Hashable, Sendable {
    case text(String)
    case choice(String)
    case ordering([String])
    case matches([MatchPair])

    /// Human-readable form stored in attempts.
    public var displayText: String {
        switch self {
        case .text(let s), .choice(let s): return s
        case .ordering(let tokens): return tokens.joined(separator: " ")
        case .matches(let pairs): return pairs.map { "\($0.left) = \($0.right)" }.joined(separator: " ; ")
        }
    }
}

/// Token-level comparison used to show precisely which part of the answer is wrong (§9.1-1).
public struct TokenDiff: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable {
        case same, wrong, missing, extra, typo
    }
    /// Token as typed by the learner (empty for `.missing`).
    public let text: String
    /// Expected token (nil for `.same` and `.extra`).
    public let expected: String?
    public let status: Status

    public init(text: String, expected: String?, status: Status) {
        self.text = text
        self.expected = expected
        self.status = status
    }
}

/// Result of the deterministic evaluator (level 1), possibly overridden by AI grading (level 2).
public struct Evaluation: Codable, Hashable, Sendable {
    public var result: AttemptResult
    /// Reference answer to display.
    public var expectedAnswer: String
    public var userAnswer: String
    public var errorCategory: ErrorCategory?
    /// Targeted feedback (from an error pattern, a detected error type or the AI).
    public var feedback: String?
    /// Spelling remark when the answer was accepted with a typo.
    public var typoNote: String?
    public var diff: [TokenDiff]
    /// Match exercises: pairs that were wrong.
    public var wrongPairs: [MatchPair]
    /// True when the deterministic engine is unsure: the app should ask the AI to grade (level 2),
    /// and flag the case if it stays uncertain (level 3).
    public var needsAIReview: Bool
    /// Where the verdict comes from.
    public var gradedBy: Grader

    public enum Grader: String, Codable, Sendable { case deterministic, ai, localFallback }

    public var isCorrect: Bool { result.countsAsSuccess }

    public init(result: AttemptResult, expectedAnswer: String, userAnswer: String,
                errorCategory: ErrorCategory? = nil, feedback: String? = nil, typoNote: String? = nil,
                diff: [TokenDiff] = [], wrongPairs: [MatchPair] = [], needsAIReview: Bool = false,
                gradedBy: Grader = .deterministic) {
        self.result = result
        self.expectedAnswer = expectedAnswer
        self.userAnswer = userAnswer
        self.errorCategory = errorCategory
        self.feedback = feedback
        self.typoNote = typoNote
        self.diff = diff
        self.wrongPairs = wrongPairs
        self.needsAIReview = needsAIReview
        self.gradedBy = gradedBy
    }
}

/// One answered exercise (§17 attempts).
public struct AttemptRecord: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let exerciseId: String
    public let sessionId: UUID?
    public let unitIds: [String]
    public let exerciseType: ExerciseType
    public let presentation: PresentationMode
    public let submittedAnswer: String
    public var result: AttemptResult
    public var errorCategory: ErrorCategory?
    public let hintUsed: Bool
    public let isRemediation: Bool
    public let durationSeconds: Double
    public let answeredAt: Date

    public init(id: UUID = UUID(), exerciseId: String, sessionId: UUID?, unitIds: [String],
                exerciseType: ExerciseType, presentation: PresentationMode, submittedAnswer: String,
                result: AttemptResult, errorCategory: ErrorCategory?, hintUsed: Bool, isRemediation: Bool,
                durationSeconds: Double, answeredAt: Date) {
        self.id = id
        self.exerciseId = exerciseId
        self.sessionId = sessionId
        self.unitIds = unitIds
        self.exerciseType = exerciseType
        self.presentation = presentation
        self.submittedAnswer = submittedAnswer
        self.result = result
        self.errorCategory = errorCategory
        self.hintUsed = hintUsed
        self.isRemediation = isRemediation
        self.durationSeconds = durationSeconds
        self.answeredAt = answeredAt
    }
}

/// Everything the engine needs to know about a learner. Built by the app from local storage.
public struct LearnerSnapshot: Codable, Hashable, Sendable {
    public var memoryStates: [String: MemoryState]
    /// Most recent attempts, oldest first (the app passes at least the last 500).
    public var recentAttempts: [AttemptRecord]
    public var completedLessonIds: Set<String>
    /// Lessons skipped thanks to the initial diagnostic.
    public var placedLessonIds: Set<String>
    /// 0...4, from the diagnostic.
    public var estimatedLevel: Int?
    public var lastAssessmentAt: Date?
    public var startedAt: Date?

    public init(memoryStates: [String: MemoryState] = [:], recentAttempts: [AttemptRecord] = [],
                completedLessonIds: Set<String> = [], placedLessonIds: Set<String> = [],
                estimatedLevel: Int? = nil, lastAssessmentAt: Date? = nil, startedAt: Date? = nil) {
        self.memoryStates = memoryStates
        self.recentAttempts = recentAttempts
        self.completedLessonIds = completedLessonIds
        self.placedLessonIds = placedLessonIds
        self.estimatedLevel = estimatedLevel
        self.lastAssessmentAt = lastAssessmentAt
        self.startedAt = startedAt
    }

    public static let empty = LearnerSnapshot()
}

/// Why an item is in a session (§5.2 mix).
public enum ItemRole: String, Codable, Sendable {
    case newMaterial
    case oldReview
    case recentReview
    case practice
    case activeRecall
    case remediation
    case assessment
}

public struct SessionItem: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: Codable, Hashable, Sendable {
        /// Show the rule of a grammar unit before exercising it.
        case ruleCard(unitId: String)
        /// Introduce a new word (with audio).
        case wordCard(unitId: String)
        case exercise(exerciseId: String)
    }

    public let id: UUID
    public let kind: Kind
    public let role: ItemRole
    public let presentation: PresentationMode
    public let hintAllowed: Bool

    public init(id: UUID = UUID(), kind: Kind, role: ItemRole, presentation: PresentationMode, hintAllowed: Bool) {
        self.id = id
        self.kind = kind
        self.role = role
        self.presentation = presentation
        self.hintAllowed = hintAllowed
    }

    public var exerciseId: String? {
        if case .exercise(let id) = kind { return id }
        return nil
    }
}

public struct SessionPlan: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let type: SessionType
    public let slot: SessionSlot?
    public let day: LocalDay
    /// Lesson whose new material is introduced in this session, if any.
    public let lessonId: String?
    public let newUnitIds: [String]
    public let items: [SessionItem]
    public let estimatedSeconds: Int
    public let createdAt: Date

    public init(id: UUID = UUID(), type: SessionType, slot: SessionSlot?, day: LocalDay, lessonId: String?,
                newUnitIds: [String], items: [SessionItem], estimatedSeconds: Int, createdAt: Date) {
        self.id = id
        self.type = type
        self.slot = slot
        self.day = day
        self.lessonId = lessonId
        self.newUnitIds = newUnitIds
        self.items = items
        self.estimatedSeconds = estimatedSeconds
        self.createdAt = createdAt
    }
}

public struct ImportantError: Codable, Hashable, Sendable {
    public let exerciseId: String
    public let unitId: String
    public let prompt: String
    public let expected: String
    public let given: String
    public let category: ErrorCategory?
}

/// End-of-session screen data (§14.5).
public struct SessionSummary: Codable, Hashable, Sendable {
    public let sessionId: UUID
    public let type: SessionType
    public let slot: SessionSlot?
    public let lessonId: String?
    public let unitIdsWorked: [String]
    public let newUnitIds: [String]
    public let reviewCount: Int
    public let attemptCount: Int
    public let correctCount: Int
    public let importantErrors: [ImportantError]
    public let durationSeconds: Double
    /// Assessment sessions only: share of correct answers, 0...1.
    public let score: Double?
}

public enum MasteryLevel: String, Codable, Sendable, Comparable {
    case notStarted, learning, fragile, mastered

    private var rank: Int {
        switch self {
        case .notStarted: return 0
        case .learning: return 1
        case .fragile: return 2
        case .mastered: return 3
        }
    }

    public static func < (lhs: MasteryLevel, rhs: MasteryLevel) -> Bool { lhs.rank < rhs.rank }

    public var displayName: String {
        switch self {
        case .notStarted: return "Pas encore vu"
        case .learning: return "En apprentissage"
        case .fragile: return "Fragile"
        case .mastered: return "Maîtrisé"
        }
    }
}

public struct MasteryReport: Codable, Hashable, Sendable {
    public let unitId: String
    /// 0...1, see docs/05-moteur-pedagogique.md for the formula.
    public let score: Double
    public let level: MasteryLevel
    /// Current FSRS recall probability, 0...1.
    public let retrievability: Double
    public let nextReviewAt: Date?
}

public struct CategoryProgress: Codable, Hashable, Sendable {
    public let category: ProgressCategory
    public let unitsTotal: Int
    public let unitsStudied: Int
    public let unitsMastered: Int
    /// Mean mastery score of the studied units of the category, 0...1.
    public let averageMastery: Double
}

public struct ErrorCategoryStat: Codable, Hashable, Sendable {
    public let category: ErrorCategory
    public let errorCount: Int
    /// Share of recent attempts with this error category, 0...1.
    public let rate: Double
}

/// Progress dashboard data computed by the engine (§15).
public struct ProgressReport: Codable, Hashable, Sendable {
    public let wordsStudied: Int
    public let wordsMastered: Int
    public let rulesStudied: Int
    public let rulesMastered: Int
    public let attemptCount: Int
    /// Successes / graded attempts (pending excluded), 0...1.
    public let successRate: Double
    /// Attempts made on units that had been seen on a previous day.
    public let reviewsDone: Int
    public let dueReviewCount: Int
    public let lessonsCompleted: Int
    public let lessonsTotal: Int
    public let categories: [CategoryProgress]
    /// Error categories sorted by decreasing rate over recent attempts.
    public let weakErrorCategories: [ErrorCategoryStat]
}

/// Answer to the onboarding question "Quel est ton niveau ?" (§4 step 4). Only seeds the diagnostic.
public enum SelfAssessedLevel: Int, Codable, CaseIterable, Sendable {
    case beginner = 0
    case someBasics = 1
    case understandsSentences = 2
    case intermediate = 3

    public var displayName: String {
        switch self {
        case .beginner: return "Je débute"
        case .someBasics: return "Je connais quelques bases"
        case .understandsSentences: return "Je comprends déjà des phrases"
        case .intermediate: return "J'ai un niveau intermédiaire"
        }
    }
}

public struct DiagnosticAnswer: Codable, Hashable, Sendable {
    public let exerciseId: String
    public let level: Int
    public let topic: String
    public let correct: Bool
}

/// Outcome of the adaptive placement test. No CEFR certification is claimed.
public struct DiagnosticResult: Codable, Hashable, Sendable {
    /// 0...4
    public let estimatedLevel: Int
    /// e.g. "Débutant", "Bases acquises" — never a certified CEFR level.
    public let levelLabel: String
    public let startLessonId: String
    public let placedLessonIds: [String]
    /// Units presumed known: seeded with short intervals so that they are verified quickly.
    public let knownUnitIds: [String]
    public let answers: [DiagnosticAnswer]
    /// Share of correct answers per topic.
    public let topicScores: [String: Double]
}

/// Tunable engine parameters (§12.3: to be adjusted with real data).
public struct EngineConfiguration: Codable, Hashable, Sendable {
    /// FSRS-4.5 weights (17 values).
    public var fsrsWeights: [Double]
    /// Target probability of recall when a review is scheduled.
    public var desiredRetention: Double
    public var maximumIntervalDays: Double
    public var minInteractions: Int
    public var maxInteractions: Int
    public var targetSessionSeconds: Int
    /// Estimated seconds per item kind, used to calibrate session length.
    public var estimatedSeconds: [String: Int]
    /// Above this number of overdue reviews, no new lesson is introduced (§5.2).
    public var overdueThresholdToPauseNewMaterial: Int
    public var maxRemediationsPerSession: Int
    /// A prerequisite counts as sufficiently mastered above this mastery score.
    public var prerequisiteMasteryThreshold: Double
    /// After this many days stuck on a prerequisite, progression is allowed anyway (§13.3).
    public var prerequisiteBypassDays: Int
    public var masteredThreshold: Double
    public var fragileThreshold: Double
    public var delayedSuccessHours: Double
    public var recentResultsLimit: Int
    public var attemptHistoryLimit: Int
    public var assessmentIntervalDays: Int
    public var assessmentQuestionCount: Int
    public var diagnosticMinQuestions: Int
    public var diagnosticMaxQuestions: Int

    public init(fsrsWeights: [Double], desiredRetention: Double, maximumIntervalDays: Double,
                minInteractions: Int, maxInteractions: Int, targetSessionSeconds: Int,
                estimatedSeconds: [String: Int], overdueThresholdToPauseNewMaterial: Int,
                maxRemediationsPerSession: Int, prerequisiteMasteryThreshold: Double,
                prerequisiteBypassDays: Int, masteredThreshold: Double, fragileThreshold: Double,
                delayedSuccessHours: Double, recentResultsLimit: Int, attemptHistoryLimit: Int,
                assessmentIntervalDays: Int, assessmentQuestionCount: Int,
                diagnosticMinQuestions: Int, diagnosticMaxQuestions: Int) {
        self.fsrsWeights = fsrsWeights
        self.desiredRetention = desiredRetention
        self.maximumIntervalDays = maximumIntervalDays
        self.minInteractions = minInteractions
        self.maxInteractions = maxInteractions
        self.targetSessionSeconds = targetSessionSeconds
        self.estimatedSeconds = estimatedSeconds
        self.overdueThresholdToPauseNewMaterial = overdueThresholdToPauseNewMaterial
        self.maxRemediationsPerSession = maxRemediationsPerSession
        self.prerequisiteMasteryThreshold = prerequisiteMasteryThreshold
        self.prerequisiteBypassDays = prerequisiteBypassDays
        self.masteredThreshold = masteredThreshold
        self.fragileThreshold = fragileThreshold
        self.delayedSuccessHours = delayedSuccessHours
        self.recentResultsLimit = recentResultsLimit
        self.attemptHistoryLimit = attemptHistoryLimit
        self.assessmentIntervalDays = assessmentIntervalDays
        self.assessmentQuestionCount = assessmentQuestionCount
        self.diagnosticMinQuestions = diagnosticMinQuestions
        self.diagnosticMaxQuestions = diagnosticMaxQuestions
    }

    public static let `default` = EngineConfiguration(
        fsrsWeights: [0.4872, 1.4003, 3.7145, 13.8206, 5.1618, 1.2298, 0.8975, 0.031, 1.6474,
                      0.1367, 1.0461, 2.1072, 0.0793, 0.3246, 1.587, 0.2272, 2.8755],
        desiredRetention: 0.9,
        maximumIntervalDays: 180,
        minInteractions: 8,
        maxInteractions: 12,
        targetSessionSeconds: 300,
        estimatedSeconds: [
            "ruleCard": 45, "wordCard": 12,
            "mcq": 15, "match": 25, "fill_blank": 20, "reorder": 25, "translation": 35, "free_answer": 40,
        ],
        overdueThresholdToPauseNewMaterial: 15,
        maxRemediationsPerSession: 3,
        prerequisiteMasteryThreshold: 0.5,
        prerequisiteBypassDays: 5,
        masteredThreshold: 0.8,
        fragileThreshold: 0.45,
        delayedSuccessHours: 20,
        recentResultsLimit: 10,
        attemptHistoryLimit: 500,
        assessmentIntervalDays: 14,
        assessmentQuestionCount: 12,
        diagnosticMinQuestions: 15,
        diagnosticMaxQuestions: 20)
}

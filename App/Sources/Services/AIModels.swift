import Foundation
import LearningCore

// Wire types of the `ai` Edge Function (docs/contracts/backend.md, camelCase JSON).
// Only contract fields exist here: never the e-mail address, the name or any other personal data.

struct AIHistoryMessage: Encodable, Sendable, Equatable {
    var role: String
    var text: String
}

struct AIExplainAnswerRequest: Encodable, Sendable, Equatable {
    var languageCode: String
    var level: Int
    var exerciseId: String
    var userAnswer: String
    var detail: String
    var previousErrorCategories: [String]
}

struct AIExplainWordRequest: Encodable, Sendable, Equatable {
    var languageCode: String
    var level: Int
    var word: String
    var sentence: String?
    var detail: String
}

struct AIExplainRuleRequest: Encodable, Sendable, Equatable {
    var languageCode: String
    var level: Int
    var unitId: String
    var detail: String
}

struct AIFollowUpRequest: Encodable, Sendable, Equatable {
    var languageCode: String
    var level: Int
    var exerciseId: String?
    var unitId: String?
    var word: String?
    var userAnswer: String?
    var previousExplanation: String
    var history: [AIHistoryMessage]
    var question: String
}

struct AIGradeRequest: Encodable, Sendable, Equatable {
    var languageCode: String
    var level: Int
    var exerciseId: String
    var userAnswer: String
}

struct AIExampleDTO: Decodable, Sendable, Equatable {
    var text: String
    var translation: String?
}

struct AIExplainResponse: Decodable, Sendable, Equatable {
    var text: String
    var examples: [AIExampleDTO]?
    var source: String?
    var remainingQuota: Int?
}

struct AIGradeResponse: Decodable, Sendable, Equatable {
    var verdict: String
    var errorCategory: String?
    var explanation: String?
    var correctedAnswer: String?
    var source: String?
    var remainingQuota: Int?
}

struct AIErrorBody: Decodable {
    var error: String?
    var message: String?
    var resetAt: String?
}

/// Result of an AI grading, already mapped to the engine's vocabulary.
struct AIGradeOutcome: Sendable, Equatable {
    var result: AttemptResult
    var errorCategory: ErrorCategory?
    var explanation: String?
    var correctedAnswer: String?
    var remainingQuota: Int?

    /// nil for "uncertain" or unknown verdicts: the attempt stays pending.
    init?(response: AIGradeResponse) {
        switch response.verdict.lowercased() {
        case "correct": result = .correct
        case "partial": result = .partial
        case "incorrect": result = .incorrect
        default: return nil
        }
        errorCategory = response.errorCategory.flatMap { ErrorCategory(rawValue: $0) }
        explanation = response.explanation
        correctedAnswer = response.correctedAnswer
        remainingQuota = response.remainingQuota
    }
}

extension String {
    /// First `maxLength` characters (contract limits: answer 300, question 500).
    func truncated(to maxLength: Int) -> String {
        count <= maxLength ? self : String(prefix(maxLength))
    }
}


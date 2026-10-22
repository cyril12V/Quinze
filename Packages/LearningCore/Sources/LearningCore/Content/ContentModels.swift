import Foundation
@_exported import LearningPrimitives

// Content model. Mirrors Content/SCHEMA.md and the bundle produced by tools/build_content.py.
// All content types are immutable value types decoded from JSON (camelCase keys).

public enum WritingDirection: String, Codable, Sendable {
    case ltr, rtl
}

public struct LanguageInfo: Codable, Hashable, Sendable {
    public let code: String
    public let name: String
    public let nativeName: String
    public let writingDirection: WritingDirection
    /// BCP-47 locale for AVSpeechSynthesizer, e.g. "en-GB".
    public let ttsLocale: String
}

public struct ModuleInfo: Codable, Hashable, Sendable, Identifiable {
    public let id: Int
    public let title: String
    public let description: String
}

public enum UnitKind: String, Codable, Sendable {
    case grammar, vocabulary
}

/// Categories shown on the progress dashboard (§15.2).
public enum ProgressCategory: String, Codable, CaseIterable, Sendable {
    case vocabulary
    case verbs
    case grammar
    case sentenceBuilding = "sentence_building"
    /// Arabic: letters, vowel signs and reading.
    case reading
    /// General knowledge topics.
    case knowledge

    public var displayName: String {
        switch self {
        case .vocabulary: return "Vocabulaire"
        case .verbs: return "Verbes"
        case .grammar: return "Grammaire"
        case .sentenceBuilding: return "Construction de phrases"
        case .reading: return "Lecture"
        case .knowledge: return "Connaissances"
        }
    }
}

/// A sentence in the studied language with its French translation.
public struct Example: Codable, Hashable, Sendable {
    public let text: String
    public let translation: String
    /// Latin transcription of `text` (Arabic), shown under it.
    public let transliteration: String?

    public init(text: String, translation: String, transliteration: String? = nil) {
        self.text = text
        self.translation = translation
        self.transliteration = transliteration
    }
}

public struct CommonError: Codable, Hashable, Sendable {
    public let wrong: String
    public let right: String
    public let why: String
}

public struct GrammarRule: Codable, Hashable, Sendable {
    public let summary: String
    public let explanation: String
    public let pattern: String?
    public let examples: [Example]
    public let commonErrors: [CommonError]
    public let tip: String?
}

/// A unit of knowledge tracked by spaced repetition: a grammar notion or a word/expression.
public struct LearningUnit: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let kind: UnitKind
    public let category: ProgressCategory
    /// Grammar: French title of the notion. Vocabulary: the word or expression itself.
    public let title: String
    public let difficulty: Int
    public let prerequisites: [String]
    public let module: Int
    // Grammar only
    public let rule: GrammarRule?
    public let functionWords: [String]?
    // Vocabulary only
    public let translation: String?
    public let partOfSpeech: String?
    public let lessonId: String?
    public let dictionaryItemId: String?
    public let deprecated: Bool?
}

public struct Lesson: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let module: Int
    public let sequence: Int
    public let title: String
    public let description: String
    public let difficulty: Int
    /// Main grammar notion of the lesson (introduced or practised).
    public let grammarUnitId: String
    public let introducesGrammar: Bool
    /// Units first taught in this lesson (grammar notion if new, then vocabulary).
    public let introduces: [String]
    /// Units reinforced by this lesson without being new.
    public let reviews: [String]
}

public enum ExerciseType: String, Codable, CaseIterable, Sendable {
    case mcq
    case fillBlank = "fill_blank"
    case translation
    case reorder
    case match
    case freeAnswer = "free_answer"

    public var displayName: String {
        switch self {
        case .mcq: return "QCM"
        case .fillBlank: return "Phrase à compléter"
        case .translation: return "Traduction"
        case .reorder: return "Remise en ordre"
        case .match: return "Association"
        case .freeAnswer: return "Réponse libre"
        }
    }

    /// Default memory skill exercised by this type.
    public var defaultSkill: ExerciseSkill {
        switch self {
        case .mcq, .match: return .recognition
        case .fillBlank, .reorder: return .recall
        case .translation, .freeAnswer: return .production
        }
    }
}

/// Recognition < recall < production: used to grade evidence of mastery (§12.5).
public enum ExerciseSkill: String, Codable, Sendable, Comparable {
    case recognition, recall, production

    private var rank: Int {
        switch self {
        case .recognition: return 0
        case .recall: return 1
        case .production: return 2
        }
    }

    public static func < (lhs: ExerciseSkill, rhs: ExerciseSkill) -> Bool { lhs.rank < rhs.rank }
}

/// Error categories (§9.3). They feed the review engine.
public enum ErrorCategory: String, Codable, CaseIterable, Sendable {
    case vocabulary
    case grammar
    case conjugation
    case verbTense = "verb_tense"
    case wordOrder = "word_order"
    case spelling
    case preposition
    case wordConfusion = "word_confusion"
    case instruction

    public var displayName: String {
        switch self {
        case .vocabulary: return "Vocabulaire"
        case .grammar: return "Grammaire"
        case .conjugation: return "Conjugaison"
        case .verbTense: return "Temps verbal"
        case .wordOrder: return "Ordre des mots"
        case .spelling: return "Orthographe"
        case .preposition: return "Préposition"
        case .wordConfusion: return "Confusion entre mots"
        case .instruction: return "Compréhension de la consigne"
        }
    }
}

public struct MatchPair: Codable, Hashable, Sendable {
    public let left: String
    public let right: String

    public init(left: String, right: String) {
        self.left = left
        self.right = right
    }
}

/// An anticipated wrong answer with targeted feedback.
public struct ErrorPattern: Codable, Hashable, Sendable {
    /// The normalized answer equals this value.
    public let equals: String?
    /// The normalized answer contains this word sequence.
    public let contains: String?
    public let category: ErrorCategory
    public let feedback: String
}

/// Constraints for open free-answer production ("Écris une phrase au passé avec go").
public struct AnswerRequirements: Codable, Hashable, Sendable {
    /// Each inner list is a set of alternatives; every inner list must be satisfied.
    public let mustInclude: [[String]]?
    public let mustNotInclude: [String]?
    public let minWords: Int?
}

public enum ExercisePool: String, Codable, Sendable {
    case lesson, diagnostic, assessment
}

public struct Exercise: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let pool: ExercisePool
    public let lessonId: String?
    /// First element = primary unit.
    public let unitIds: [String]
    public let type: ExerciseType
    public let skill: ExerciseSkill
    public let difficulty: Int
    public let instruction: String
    public let prompt: String
    /// Language of `prompt`: "fr" or the studied language code.
    public let promptLanguage: String
    public let context: String?
    public let options: [String]?
    public let answer: String
    public let acceptedAnswers: [String]
    public let tokens: [String]?
    public let pairs: [MatchPair]?
    public let requirements: AnswerRequirements?
    public let hint: String?
    public let explanation: String
    public let tip: String?
    public let extraExample: Example?
    public let errorPatterns: [ErrorPattern]?
    /// Diagnostic only: difficulty level 0...4 and topic.
    public let level: Int?
    public let topic: String?
    public let deprecated: Bool?

    public var primaryUnitId: String { unitIds.first ?? "" }

    /// Language the learner must answer in.
    public func answerLanguage(studied: String) -> String {
        // General knowledge ("cg") is studied in French.
        let studied = studied == "cg" ? "fr" : studied
        switch type {
        case .translation, .freeAnswer:
            return promptLanguage == "fr" ? studied : "fr"
        default:
            return studied
        }
    }
}

public struct Confusion: Codable, Hashable, Sendable {
    public let word: String
    public let note: String
}

public struct DictionaryItem: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let word: String
    public let translation: String
    public let otherTranslations: [String]?
    public let partOfSpeech: String
    public let ipa: String?
    /// Latin transcription (Arabic words).
    public let transliteration: String?
    public let explanation: String
    public let examples: [Example]
    public let confusions: [Confusion]?
    /// thirdPerson, past, pastParticiple, ing, plural, comparative, superlative
    public let forms: [String: String]?
    /// Vocabulary unit (en.v.…), nil for function words.
    public let unitId: String?
}

/// The whole content of one language, as produced by tools/build_content.py.
public struct ContentBundle: Codable, Sendable {
    public let formatVersion: Int
    public let contentVersion: String
    public let language: LanguageInfo
    public let modules: [ModuleInfo]
    public let units: [LearningUnit]
    public let lessons: [Lesson]
    /// Lesson exercises only.
    public let exercises: [Exercise]
    public let diagnostic: [Exercise]
    public let assessment: [Exercise]
    public let dictionary: [DictionaryItem]

    public static func decode(from data: Data) throws -> ContentBundle {
        try JSONDecoder().decode(ContentBundle.self, from: data)
    }
}

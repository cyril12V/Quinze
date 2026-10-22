import Foundation
import Observation
import LearningCore

// CONTRACT FILE — owned by the "services" workstream (B1).
// Goes through AIClient: straight to Claude with the learner's own key, else the `ai` Edge Function.
// Never throws: on error, offline or quota exhausted it returns a fallback reply built from local content.

enum TutorDetail: String, Sendable {
    case short, detailed
}

struct TutorMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Sendable { case user, tutor }
    let id: UUID
    let role: Role
    let text: String

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

/// What the explanation is about.
enum TutorSubject: Equatable, Sendable {
    /// A corrected answer (correction screen).
    case answer(exerciseId: String, userAnswer: String)
    /// A grammar rule (rule card, correction screen).
    case rule(unitId: String)
    /// A word (dictionary sheet, tapped word), with the sentence it appeared in.
    case word(String, sentence: String?)
    /// A pedagogical example sentence.
    case example(text: String, unitId: String?)
}

enum TutorReplySource: String, Sendable {
    case ai, cache, fallback, offline
}

struct TutorReply: Equatable, Sendable {
    var text: String
    var examples: [Example]
    var source: TutorReplySource
    var remainingQuota: Int?
}

@MainActor
@Observable
final class TutorService {
    var isOnline: Bool { network.isOnline }
    private(set) var remainingQuota: Int?

    private let ai: AIClient
    private let network: NetworkMonitor
    /// Store of the subject being studied (the tutor follows the lesson or screen in front of the user).
    @ObservationIgnored private let storeProvider: @MainActor () -> LearningStore
    private var store: LearningStore { storeProvider() }

    init(ai: AIClient, network: NetworkMonitor, store: @escaping @MainActor () -> LearningStore) {
        self.ai = ai
        self.network = network
        self.storeProvider = store
    }

    /// First explanation ("Explique-moi") or deeper one ("Plus de détails").
    func explain(_ subject: TutorSubject, detail: TutorDetail) async -> TutorReply {
        let engine = store.engine
        guard let engine, network.isOnline else {
            return TutorFallback.reply(for: subject, detail: detail, engine: engine, cause: .offline)
        }
        do {
            let response = try await requestExplanation(subject, detail: detail, engine: engine)
            return makeReply(response)
        } catch {
            return fallback(after: error, subject: subject, detail: detail, engine: engine)
        }
    }

    /// Follow-up question in the tutor conversation ("Donne-moi un autre exemple", free text…).
    func followUp(about subject: TutorSubject, history: [TutorMessage], question: String) async -> TutorReply {
        let engine = store.engine
        guard let engine, network.isOnline else {
            return TutorFallback.reply(for: subject, detail: .short, engine: engine, cause: .offline,
                                       question: question, history: history)
        }
        let code = engine.language.code
        let level = store.learner.estimatedLevel ?? 1
        var request = AIFollowUpRequest(
            languageCode: code, level: level, exerciseId: nil, unitId: nil, word: nil, userAnswer: nil,
            previousExplanation: (history.last { $0.role == .tutor }?.text ?? "").truncated(to: 2000),
            history: history.suffix(6).map { AIHistoryMessage(role: $0.role.rawValue, text: $0.text.truncated(to: 1000)) },
            question: question.truncated(to: 500))
        switch subject {
        case .answer(let exerciseId, let answer):
            request.exerciseId = exerciseId
            request.userAnswer = answer.truncated(to: 300)
        case .rule(let unitId):
            request.unitId = unitId
        case .word(let word, _):
            request.word = word
        case .example(_, let unitId):
            request.unitId = unitId
        }
        do {
            let response = try await ai.followUp(request, engine: engine)
            return makeReply(response)
        } catch {
            return fallback(after: error, subject: subject, detail: .short, engine: engine,
                            question: question, history: history)
        }
    }

    // MARK: Requests

    private func requestExplanation(_ subject: TutorSubject, detail: TutorDetail, engine: LearningEngine) async throws -> AIExplainResponse {
        let code = engine.language.code
        let level = store.learner.estimatedLevel ?? 1
        switch subject {
        case .answer(let exerciseId, let answer):
            return try await ai.explainAnswer(AIExplainAnswerRequest(
                languageCode: code, level: level, exerciseId: exerciseId, userAnswer: answer.truncated(to: 300),
                detail: detail.rawValue, previousErrorCategories: previousErrorCategories(exerciseId: exerciseId, engine: engine)),
                engine: engine)
        case .rule(let unitId):
            return try await ai.explainRule(AIExplainRuleRequest(
                languageCode: code, level: level, unitId: unitId, detail: detail.rawValue), engine: engine)
        case .word(let word, let sentence):
            return try await ai.explainWord(AIExplainWordRequest(
                languageCode: code, level: level, word: word, sentence: sentence?.truncated(to: 300), detail: detail.rawValue),
                engine: engine)
        case .example(let text, let unitId):
            if let unitId {
                return try await ai.explainRule(AIExplainRuleRequest(
                    languageCode: code, level: level, unitId: unitId, detail: detail.rawValue), engine: engine)
            }
            return try await ai.followUp(AIFollowUpRequest(
                languageCode: code, level: level, exerciseId: nil, unitId: nil, word: nil, userAnswer: nil,
                previousExplanation: "", history: [], question: "Explique cette phrase : \(text)".truncated(to: 500)),
                engine: engine)
        }
    }

    /// Error categories of the learner's recent attempts on the same unit (category names only).
    private func previousErrorCategories(exerciseId: String, engine: LearningEngine) -> [String] {
        guard let unitId = engine.exercise(exerciseId)?.primaryUnitId else { return [] }
        var result: [String] = []
        for attempt in store.learner.recentAttempts.reversed() where attempt.unitIds.contains(unitId) {
            guard let category = attempt.errorCategory?.rawValue, !result.contains(category) else { continue }
            result.append(category)
            if result.count == 5 { break }
        }
        return result
    }

    // MARK: Replies

    private func makeReply(_ response: AIExplainResponse) -> TutorReply {
        if let quota = response.remainingQuota { remainingQuota = quota }
        let source = TutorReplySource(rawValue: response.source ?? "ai") ?? .ai
        let examples = (response.examples ?? []).map { Example(text: $0.text, translation: $0.translation ?? "") }
        return TutorReply(text: response.text, examples: examples, source: source, remainingQuota: response.remainingQuota)
    }

    private func fallback(after error: Error, subject: TutorSubject, detail: TutorDetail, engine: LearningEngine?,
                          question: String? = nil, history: [TutorMessage] = []) -> TutorReply {
        let cause: TutorFallback.Cause
        switch error as? AIClient.Failure {
        case .rateLimited?:
            cause = .quotaReached
            remainingQuota = 0
        case .offline?:
            cause = .offline
        default:
            cause = .unavailable
        }
        Log.tutor.notice("tutor fallback used")
        return TutorFallback.reply(for: subject, detail: detail, engine: engine, cause: cause,
                                   question: question, history: history)
    }
}

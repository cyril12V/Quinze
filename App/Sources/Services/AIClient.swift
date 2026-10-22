import Foundation
import Supabase
import LearningCore

// AI tutor and AI grading. With the learner's own Anthropic key (Keychain, set in the settings) every
// call goes straight to Claude (ClaudeDirectClient, no backend); otherwise to the `ai` Edge Function
// (docs/contracts/backend.md). Only the contract fields are sent: never the e-mail address, the name
// or any other personal data. `engine` is the subject's engine: the direct path reads the validated
// content from it (the Edge Function reloads it from its database).

// MARK: - Client

struct AIClient: Sendable {
    enum Failure: Error, Sendable, Equatable {
        case notConfigured
        case offline
        case unauthorized
        case rateLimited
        case unavailable
        case badRequest
        case server
    }

    let backend: BackendClient

    /// The learner's own Anthropic API key, if one is saved in the Keychain.
    var personalKey: String? { KeychainStore.apiKey() }

    /// False without a personal key and without a backend: answers are then graded by the learner.
    var isConfigured: Bool { personalKey != nil || backend.client != nil }

    private var direct: ClaudeDirectClient? { personalKey.map { ClaudeDirectClient(apiKey: $0) } }

    // MARK: Operations

    func explainAnswer(_ request: AIExplainAnswerRequest, engine: LearningEngine) async throws -> AIExplainResponse {
        if let client = direct { return try await client.explainAnswer(request, engine: engine) }
        return try await call("explain-answer", body: request)
    }

    func explainWord(_ request: AIExplainWordRequest, engine: LearningEngine) async throws -> AIExplainResponse {
        if let client = direct { return try await client.explainWord(request, engine: engine) }
        return try await call("explain-word", body: request)
    }

    func explainRule(_ request: AIExplainRuleRequest, engine: LearningEngine) async throws -> AIExplainResponse {
        if let client = direct { return try await client.explainRule(request, engine: engine) }
        return try await call("explain-rule", body: request)
    }

    func followUp(_ request: AIFollowUpRequest, engine: LearningEngine) async throws -> AIExplainResponse {
        if let client = direct { return try await client.followUp(request, engine: engine) }
        return try await call("follow-up", body: request)
    }

    func grade(languageCode: String, level: Int, exerciseId: String, userAnswer: String,
               engine: LearningEngine) async throws -> AIGradeResponse {
        let request = AIGradeRequest(languageCode: languageCode, level: level, exerciseId: exerciseId,
                                     userAnswer: userAnswer.truncated(to: 300))
        if let client = direct { return try await client.grade(request, engine: engine) }
        return try await call("grade-answer", body: request)
    }

    // MARK: Backend (Edge Function)

    func call<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ action: String, body: Body
    ) async throws -> Response {
        guard let client = backend.client else { throw Failure.notConfigured }
        do {
            let response: Response = try await client.functions.invoke(
                "ai/\(action)", options: FunctionInvokeOptions(method: .post, body: body))
            return response
        } catch let error as FunctionsError {
            throw Self.map(error)
        } catch is CancellationError {
            throw CancellationError()
        } catch is URLError {
            throw Failure.offline
        } catch {
            throw Failure.server
        }
    }

    static func map(_ error: FunctionsError) -> Failure {
        guard case .httpError(let code, let data) = error else { return .unavailable }
        let body = try? JSONDecoder().decode(AIErrorBody.self, from: data)
        switch code {
        case 401: return .unauthorized
        case 400: return .badRequest
        case 429: return .rateLimited
        case 503: return .unavailable
        default: return body?.error == "rate_limited" ? .rateLimited : .server
        }
    }
}

// MARK: - Timeout helper

struct OperationTimedOut: Error {}

/// Runs `operation`, giving up after `seconds`.
func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw OperationTimedOut()
        }
        guard let first = try await group.next() else { throw OperationTimedOut() }
        group.cancelAll()
        return first
    }
}

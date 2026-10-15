import Foundation
import Supabase

// Client of the `ai` Edge Function (docs/contracts/backend.md). Only the contract fields are sent:
// never the e-mail address, the name or any other personal data.

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

    /// False in local mode (no backend): answers are then graded by the learner.
    var isConfigured: Bool { backend.client != nil }

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

    func grade(languageCode: String, level: Int, exerciseId: String, userAnswer: String) async throws -> AIGradeResponse {
        try await call("grade-answer", body: AIGradeRequest(languageCode: languageCode, level: level,
                                                            exerciseId: exerciseId,
                                                            userAnswer: userAnswer.truncated(to: 300)))
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

import Foundation
import Observation
import AuthenticationServices
import CryptoKit
import Security
import Supabase

/// Nonce helpers for Sign in with Apple: the raw nonce goes to Supabase, its SHA-256 to Apple.
enum AppleNonce {
    static func random(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        while result.count < length {
            var bytes = [UInt8](repeating: 0, count: 16)
            if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
                bytes = bytes.map { _ in UInt8.random(in: 0...255) }
            }
            for byte in bytes where result.count < length {
                result.append(charset[Int(byte) % charset.count])
            }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum AuthFailure: Error, Equatable {
    case notConfigured
    case offline
    case message(String)
}

/// Account: Sign in with Apple, e-mail/password with verification, recovery, logout, deletion, export.
/// Tokens live in the Keychain (managed by the SDK); the app never stores a password.
@MainActor
@Observable
final class AuthService {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn
        /// A recovery link was opened: the user must choose a new password.
        case passwordRecovery
    }

    enum SignUpOutcome: Equatable {
        case signedIn
        case verificationRequired
    }

    private(set) var state: State = .loading
    /// Personal "local mode": no Supabase configured (SUPABASE_URL empty). No account, no sync,
    /// progress stays on this iPhone, the AI tutor answers from local content.
    private(set) var isLocalMode = false
    /// Lowercased Supabase user id (or a stable `local-…` id in local mode).
    private(set) var userId: String?
    private(set) var email: String?
    private(set) var isWorking = false
    /// French message to show on the current auth screen.
    var errorMessage: String?
    var infoMessage: String?
    /// Name collected at sign-up (or by Apple) waiting to be saved in the profile once signed in.
    private var pendingDisplayName: String?
    /// Called when the user goes from signed out to signed in (after launch).
    var onSignedIn: (@MainActor () async -> Void)?
    var onSignedOut: (@MainActor () -> Void)?

    private let backend: BackendClient
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var recoveryLinkInProgress = false
    @ObservationIgnored private var recoveryStartedSignedOut = false
    @ObservationIgnored private var hooksEnabled = false

    init(backend: BackendClient) {
        self.backend = backend
    }

    // MARK: Lifecycle

    /// Reads the stored session synchronously (offline-first: an expired token never blocks the app)
    /// and then follows the SDK's auth events.
    func start() {
        guard let client = backend.client else {
            // No backend: local mode, signed in with a stable on-device identity.
            isLocalMode = true
            userId = Self.localUserId()
            email = nil
            state = .signedIn
            hooksEnabled = true
            return
        }
        if let session = client.auth.currentSession {
            apply(session: session)
            state = .signedIn
        } else {
            state = .signedOut
        }
        hooksEnabled = true
        listenTask?.cancel()
        listenTask = Task { [weak self] in
            for await (event, session) in client.auth.authStateChanges {
                self?.handle(event: event, session: session)
            }
        }
    }

    /// Stable id of the local profile ("local-<uuid>"), kept in UserDefaults.
    static func localUserId() -> String {
        let key = "quinze.localUserId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = "local-" + UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    private func apply(session: Session?) {
        userId = session?.user.id.uuidString.lowercased()
        email = session?.user.email
    }

    private func handle(event: AuthChangeEvent, session: Session?) {
        switch event {
        case .initialSession:
            if let session {
                apply(session: session)
                if state == .loading || state == .signedOut { transition(to: .signedIn) }
            } else if state == .loading {
                transition(to: .signedOut)
            }
        case .signedIn, .tokenRefreshed, .userUpdated:
            apply(session: session)
            if recoveryLinkInProgress || state == .passwordRecovery {
                state = .passwordRecovery
            } else if session != nil {
                transition(to: .signedIn)
            }
        case .passwordRecovery:
            apply(session: session)
            state = .passwordRecovery
        case .signedOut:
            apply(session: nil)
            transition(to: .signedOut)
        default:
            break
        }
    }

    private func transition(to new: State) {
        let old = state
        guard old != new else { return }
        state = new
        guard hooksEnabled else { return }
        if new == .signedIn, old != .passwordRecovery || recoveryStartedSignedOut {
            recoveryStartedSignedOut = false
            let hook = onSignedIn
            Task { await hook?() }
        } else if new == .signedOut {
            onSignedOut?()
        }
    }

    func consumePendingDisplayName() -> String? {
        defer { pendingDisplayName = nil }
        return pendingDisplayName
    }

    // MARK: Sign in

    func signInWithApple(_ authorization: ASAuthorization, rawNonce: String) async {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            errorMessage = "La connexion avec Apple a échoué. Réessaie."
            return
        }
        // Apple only provides the name the very first time.
        let given = credential.fullName?.givenName?.trimmingCharacters(in: .whitespaces)
        if let given, !given.isEmpty { pendingDisplayName = given }
        await run {
            let client = try self.requireClient()
            _ = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: rawNonce))
        }
    }

    func signIn(email: String, password: String) async {
        await run {
            let client = try self.requireClient()
            _ = try await client.auth.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
        }
    }

    func signUp(email: String, password: String, displayName: String?) async -> SignUpOutcome? {
        errorMessage = nil
        infoMessage = nil
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty { pendingDisplayName = name }
        isWorking = true
        defer { isWorking = false }
        do {
            let client = try requireClient()
            let response = try await client.auth.signUp(email: email.trimmingCharacters(in: .whitespaces),
                                                        password: password, redirectTo: AppConfig.authCallbackURL)
            return response.session != nil ? .signedIn : .verificationRequired
        } catch {
            errorMessage = Self.frenchMessage(for: error)
            return nil
        }
    }

    func sendPasswordReset(email: String) async -> Bool {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let client = try requireClient()
            try await client.auth.resetPasswordForEmail(email.trimmingCharacters(in: .whitespaces),
                                                        redirectTo: AppConfig.resetPasswordURL)
            return true
        } catch {
            errorMessage = Self.frenchMessage(for: error)
            return false
        }
    }

    /// Handles `quinze://auth-callback` (e-mail verification) and `quinze://reset-password`.
    func handle(url: URL) async {
        guard url.scheme == "quinze", let client = backend.client else { return }
        let isRecovery = url.host == "reset-password"
        if isRecovery { recoveryStartedSignedOut = state == .signedOut || state == .loading }
        recoveryLinkInProgress = isRecovery
        do {
            let session = try await client.auth.session(from: url)
            apply(session: session)
            if isRecovery {
                state = .passwordRecovery
            } else {
                infoMessage = "Ton adresse e-mail est confirmée."
                transition(to: .signedIn)
            }
        } catch {
            recoveryLinkInProgress = false
            Log.auth.error("deep link rejected")
            errorMessage = "Ce lien n'est plus valide. Demande-en un nouveau."
        }
    }

    func updatePassword(_ newPassword: String) async -> Bool {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let client = try requireClient()
            _ = try await client.auth.update(user: UserAttributes(password: newPassword))
            recoveryLinkInProgress = false
            infoMessage = "Ton mot de passe a été modifié."
            transition(to: .signedIn)
            return true
        } catch {
            errorMessage = Self.frenchMessage(for: error)
            return false
        }
    }

    /// Leaves the recovery screen without changing the password (the user stays signed in).
    func cancelRecovery() {
        recoveryLinkInProgress = false
        if state == .passwordRecovery { transition(to: userId == nil ? .signedOut : .signedIn) }
    }

    // MARK: Sign out, deletion, export

    /// Returns false (with a message) when the sign-out could not reach the server.
    func signOut() async -> Bool {
        errorMessage = nil
        guard let client = backend.client else { transition(to: .signedOut); return true }
        do {
            try await client.auth.signOut(scope: .local)
            apply(session: nil)
            transition(to: .signedOut)
            return true
        } catch {
            errorMessage = Self.frenchMessage(for: error)
            return false
        }
    }

    /// `DELETE /functions/v1/account`. Throws an `AuthFailure` carrying a French message.
    func deleteAccountOnServer() async throws {
        let client = try requireClientOrFailure()
        do {
            try await client.functions.invoke("account", options: FunctionInvokeOptions(method: .delete))
        } catch {
            throw AuthFailure.message(Self.frenchMessage(for: error))
        }
    }

    /// After a successful deletion: drops the local session without calling the (now unknown) user.
    func finishDeletion() async {
        if let client = backend.client { try? await client.auth.signOut(scope: .local) }
        apply(session: nil)
        transition(to: .signedOut)
    }

    /// `GET /functions/v1/account/export` → a JSON file in the temporary directory.
    func exportData() async throws -> URL {
        let client = try requireClientOrFailure()
        do {
            let data = try await Self.downloadRaw("account/export", client: client)
            let stamp = Date().formatted(.iso8601.year().month().day())
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("quinze-donnees-\(stamp).json")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch let failure as AuthFailure {
            throw failure
        } catch {
            throw AuthFailure.message(Self.frenchMessage(for: error))
        }
    }

    // MARK: Helpers

    /// Raw body of a GET Edge Function call. Nonisolated so the `decode` closure is not main-actor-isolated
    /// (a main-actor closure cannot be sent to the SDK's nonisolated `invoke`).
    nonisolated private static func downloadRaw(_ name: String, client: SupabaseClient) async throws -> Data {
        try await client.functions.invoke(name, options: FunctionInvokeOptions(method: .get)) { data, _ in data }
    }

    private func requireClient() throws -> SupabaseClient {
        guard let client = backend.client else { throw AuthFailure.notConfigured }
        return client
    }

    private func requireClientOrFailure() throws -> SupabaseClient {
        guard let client = backend.client else {
            throw AuthFailure.message("L'application n'est pas configurée correctement.")
        }
        return client
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) async {
        errorMessage = nil
        infoMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await operation()
        } catch {
            if let asError = error as? ASAuthorizationError, asError.code == .canceled { return }
            errorMessage = Self.frenchMessage(for: error)
        }
    }

    /// Maps SDK/network errors to French messages by inspecting their text, so it does not depend on the
    /// shape of the SDK's error enums.
    static func frenchMessage(for error: Error) -> String {
        if error is URLError { return "Pas de connexion Internet. Vérifie ton réseau et réessaie." }
        if let failure = error as? AuthFailure {
            switch failure {
            case .notConfigured: return "L'application n'est pas configurée correctement."
            case .offline: return "Pas de connexion Internet. Vérifie ton réseau et réessaie."
            case .message(let text): return text
            }
        }
        if let asError = error as? ASAuthorizationError, asError.code == .canceled {
            return "Connexion annulée."
        }
        let text = String(describing: error).lowercased() + " " + error.localizedDescription.lowercased()
        if text.contains("invalid login") || text.contains("invalid_credentials") || text.contains("invalid credentials") {
            return "E-mail ou mot de passe incorrect."
        }
        if text.contains("email not confirmed") || text.contains("email_not_confirmed") {
            return "Confirme d'abord ton adresse e-mail grâce au lien que nous t'avons envoyé."
        }
        if text.contains("already registered") || text.contains("user_already_exists") || text.contains("already been registered") {
            return "Un compte existe déjà avec cette adresse. Connecte-toi à la place."
        }
        if text.contains("weak_password") || text.contains("at least") && text.contains("password") || text.contains("password should") {
            return "Ce mot de passe est trop faible. Choisis-en un d'au moins 8 caractères."
        }
        if text.contains("same_password") || text.contains("different from the old") {
            return "Choisis un mot de passe différent de l'ancien."
        }
        if text.contains("rate limit") || text.contains("rate_limit") || text.contains("too many") {
            return "Trop de tentatives. Patiente quelques minutes avant de réessayer."
        }
        if text.contains("offline") || text.contains("network") || text.contains("internet") {
            return "Pas de connexion Internet. Vérifie ton réseau et réessaie."
        }
        return "Une erreur est survenue. Réessaie dans un instant."
    }
}

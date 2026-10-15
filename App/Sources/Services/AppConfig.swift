import Foundation
import Network
import Observation
import OSLog
import Supabase

/// Loggers (sub-system = bundle id). Never log personal data (e-mail, name, answers…).
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "app.quinze"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let content = Logger(subsystem: subsystem, category: "content")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let lesson = Logger(subsystem: subsystem, category: "lesson")
    static let tutor = Logger(subsystem: subsystem, category: "tutor")
}

/// Configuration read from Info.plist (filled by `Config/*.xcconfig`). No provider key lives in the app.
struct AppConfig: Sendable {
    let supabaseURL: URL?
    let anonKey: String?

    static let authCallbackURL: URL = makeURL("quinze://auth-callback")
    static let resetPasswordURL: URL = makeURL("quinze://reset-password")

    private static func makeURL(_ string: String) -> URL {
        URL(string: string) ?? URL(fileURLWithPath: "/")
    }

    var isConfigured: Bool { supabaseURL != nil && anonKey != nil }

    static func load(bundle: Bundle = .main) -> AppConfig {
        func value(_ key: String) -> String? {
            guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // An unresolved "$(VAR)" or an empty value means the xcconfig is not filled in.
            guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
            // Template values of Config/*.xcconfig: no backend -> personal local mode.
            let placeholders = ["example.supabase.co", "YOUR-PROJECT-REF", "anon-key-non-configuree", "your-anon-key"]
            guard !placeholders.contains(where: { trimmed.contains($0) }) else { return nil }
            return trimmed
        }
        let url = value("SUPABASE_URL").flatMap { URL(string: $0) }
        if url == nil { Log.app.info("No Supabase configured: local mode (no account, no sync)") }
        return AppConfig(supabaseURL: url, anonKey: value("SUPABASE_ANON_KEY"))
    }
}

/// Holds the Supabase client (PKCE, tokens in the Keychain via the SDK, no password stored by the app).
struct BackendClient: Sendable {
    let config: AppConfig
    let client: SupabaseClient?

    init(config: AppConfig) {
        self.config = config
        if let url = config.supabaseURL, let key = config.anonKey {
            client = SupabaseClient(
                supabaseURL: url, supabaseKey: key,
                options: SupabaseClientOptions(
                    auth: .init(redirectToURL: AppConfig.authCallbackURL, flowType: .pkce)))
        } else {
            client = nil
        }
    }
}

/// Connectivity (NWPathMonitor). `onRegain` fires when the network comes back.
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline: Bool = true
    var onRegain: (@MainActor () -> Void)?

    private let monitor = NWPathMonitor()
    @ObservationIgnored private var started = false

    func start() {
        guard !started else { return }
        started = true
        // Explicitly @Sendable: called on the monitor's queue, never on the main actor.
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in self?.update(online: satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "quinze.network"))
    }

    private func update(online: Bool) {
        let regained = online && !isOnline
        if isOnline != online { isOnline = online }
        if regained { onRegain?() }
    }
}

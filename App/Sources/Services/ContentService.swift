import Foundation
import Observation
import CryptoKit
import Supabase
import LearningCore

/// Content bundle storage: the bundled `Content/en.json`, or a newer downloaded bundle cached in
/// Application Support (verified: sha256 + decodable) and used from the next launch.
struct ContentCache: Sendable {
    struct Metadata: Codable, Sendable, Equatable {
        var version: String
        var sha256: String
        var fileName: String
        /// Build of the app that installed the bundle: a new app build re-evaluates the cache.
        var appBuild: String
    }

    struct Loaded: Sendable {
        let engine: LearningEngine
        let version: String
        let fromCache: Bool
    }

    static var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static func directory() -> URL? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true) else { return nil }
        let dir = base.appendingPathComponent("Quinze", isDirectory: true).appendingPathComponent("Content", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func metadata() -> Metadata? {
        guard let dir = directory(), let data = try? Data(contentsOf: dir.appendingPathComponent("cache.json")) else { return nil }
        return try? JSONDecoder().decode(Metadata.self, from: data)
    }

    static func hexSHA256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Cached bundle (when still valid for this app build), else the bundled one. Blocking: call off the main actor.
    static func loadBest(languageCode: String) -> Loaded? {
        // The cache only ever holds one downloaded bundle; it is used for its own language only.
        if let meta = metadata(), meta.fileName.hasPrefix(languageCode + "-"), meta.appBuild == currentBuild, let dir = directory() {
            let file = dir.appendingPathComponent(meta.fileName)
            if let data = try? Data(contentsOf: file), let bundle = try? ContentBundle.decode(from: data) {
                return Loaded(engine: LearningEngine(bundle: bundle), version: bundle.contentVersion, fromCache: true)
            }
            Log.content.error("cached content unusable: removed")
            removeCache()
        } else if let meta = metadata(), meta.fileName.hasPrefix(languageCode + "-") {
            removeCache()
        }
        let bundle = Bundle.main
        guard let url = bundle.url(forResource: languageCode, withExtension: "json", subdirectory: "Content")
                ?? bundle.url(forResource: languageCode, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            Log.content.error("bundled content missing")
            return nil
        }
        do {
            let decoded = try ContentBundle.decode(from: data)
            return Loaded(engine: LearningEngine(bundle: decoded), version: decoded.contentVersion, fromCache: false)
        } catch {
            Log.content.error("bundled content undecodable: \(String(describing: type(of: error)), privacy: .public)")
            return nil
        }
    }

    static func removeCache() {
        guard let dir = directory() else { return }
        for item in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(item))
        }
    }

    /// Verifies and installs a downloaded bundle. Returns the version installed, nil if rejected.
    static func install(data: Data, manifest: ContentManifest, languageCode: String) -> String? {
        guard hexSHA256(data) == manifest.sha256.lowercased() else {
            Log.content.error("content sha256 mismatch: rejected")
            return nil
        }
        guard let bundle = try? ContentBundle.decode(from: data), bundle.language.code == languageCode else {
            Log.content.error("downloaded content undecodable: rejected")
            return nil
        }
        guard let dir = directory() else { return nil }
        let fileName = "\(languageCode)-\(manifest.version).json"
        do {
            try data.write(to: dir.appendingPathComponent(fileName), options: .atomic)
            let meta = Metadata(version: bundle.contentVersion, sha256: manifest.sha256.lowercased(),
                                fileName: fileName, appBuild: currentBuild)
            try JSONEncoder().encode(meta).write(to: dir.appendingPathComponent("cache.json"), options: .atomic)
            for item in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            where item != fileName && item != "cache.json" {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(item))
            }
            return bundle.contentVersion
        } catch {
            Log.content.error("content install failed: \(String(describing: type(of: error)), privacy: .public)")
            return nil
        }
    }
}

@MainActor
@Observable
final class ContentService {
    /// One engine per subject whose bundle could be loaded.
    private(set) var engines: [Subject: LearningEngine] = [:]
    /// English engine (the subject every user has).
    var engine: LearningEngine? { engines[.english] }
    private(set) var activeVersion: String?
    private(set) var loadFailed = false
    /// Version downloaded and waiting for the next launch.
    private(set) var pendingVersion: String?

    private let backend: BackendClient
    private let network: NetworkMonitor
    @ObservationIgnored private var lastCheck: Date?

    init(backend: BackendClient, network: NetworkMonitor) {
        self.backend = backend
        self.network = network
    }

    /// Loads the bundle of every subject and builds the engines off the main actor.
    /// `configuration` gives the engine settings of a subject (session length, new lessons per day).
    func loadAll(configuration: (Subject) -> EngineConfiguration) async {
        var loadedEngines: [Subject: LearningEngine] = [:]
        for subject in Subject.allCases {
            let code = subject.code
            let loaded = await Task.detached(priority: .userInitiated) {
                ContentCache.loadBest(languageCode: code)
            }.value
            guard let loaded else {
                Log.content.error("content \(code, privacy: .public) missing")
                continue
            }
            loadedEngines[subject] = LearningEngine(index: loaded.engine.index, configuration: configuration(subject))
            if subject == .english { activeVersion = loaded.version }
            Log.content.info("content \(code, privacy: .public) \(loaded.version, privacy: .public) loaded")
        }
        engines = loadedEngines
        loadFailed = loadedEngines[.english] == nil
    }

    /// Applies new engine settings (session length changed in the settings) without reloading the content.
    func reconfigure(_ configuration: (Subject) -> EngineConfiguration) {
        engines = engines.reduce(into: [:]) { result, entry in
            result[entry.key] = LearningEngine(index: entry.value.index, configuration: configuration(entry.key))
        }
    }

    /// Checks `content_manifest` and downloads a newer bundle (used from the next launch). Throttled to every 6 hours.
    func checkForUpdate(languageCode: String = "en", force: Bool = false) async {
        guard let client = backend.client, let base = backend.config.supabaseURL, network.isOnline else { return }
        if !force, let last = lastCheck, Date().timeIntervalSince(last) < 6 * 3600 { return }
        lastCheck = Date()
        do {
            let manifest = try await Self.fetchManifest(client: client, languageCode: languageCode)
            guard let manifest, ContentVersion.isNewer(manifest.version, than: pendingVersion ?? activeVersion) else { return }
            let path = manifest.bundlePath
            guard !path.hasPrefix("/"), !path.contains(".."), !path.contains("://") else {
                Log.content.error("manifest path rejected")
                return
            }
            let url = base.appendingPathComponent("storage/v1/object/public/content/\(path)")
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let installed = await Task.detached(priority: .utility) {
                ContentCache.install(data: data, manifest: manifest, languageCode: languageCode)
            }.value
            if let installed {
                pendingVersion = installed
                Log.content.info("content \(installed, privacy: .public) downloaded, used at next launch")
            }
        } catch {
            Log.content.error("content update failed: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    /// Off the main actor: the SDK's `PostgrestResponse` is not `Sendable` and cannot be returned to it.
    nonisolated private static func fetchManifest(client: SupabaseClient, languageCode: String) async throws -> ContentManifest? {
        try await client.rpc("content_manifest", params: ManifestParams(languageId: languageCode)).execute().value
    }
}

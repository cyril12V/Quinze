import Foundation

/// Persistence of `SharedState` in App Group UserDefaults with a safe read-modify-write.
///
/// Every mutation goes through `update(_:)`, which holds an in-process lock and an exclusive `flock`
/// on a lock file in the App Group container, so the app and the extensions (separate processes)
/// never overwrite each other's changes. The system calls made by the shield controller are performed
/// inside the same critical section, so "shield applied" and "record written" are observed together.
final class SharedStateStore: Sendable {
    static let shared = SharedStateStore(
        suiteName: AppGroup.identifier,
        lockURL: AppGroup.containerURL?.appendingPathComponent("quinze-state.lock"))

    static let defaultsKey = "quinze.sharedState.v1"
    private static let processLock = NSLock()

    private let suiteName: String
    private let lockURL: URL?

    /// `lockURL == nil` only disables the cross-process lock (unit tests, missing container).
    init(suiteName: String, lockURL: URL?) {
        self.suiteName = suiteName
        self.lockURL = lockURL
    }

    func load() -> SharedState {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: Self.defaultsKey),
              let state = try? JSONDecoder().decode(SharedState.self, from: data) else {
            return SharedState()
        }
        return state
    }

    /// Reads, mutates and writes the state atomically (across processes). Returns the closure's result.
    @discardableResult
    func update<T>(_ body: (inout SharedState) -> T) -> T {
        Self.processLock.lock()
        defer { Self.processLock.unlock() }
        let descriptor = acquireFileLock()
        defer { releaseFileLock(descriptor) }

        var state = load()
        let result = body(&state)
        save(state)
        return result
    }

    /// Test helper / "reset" for the whole shared state.
    func reset() {
        Self.processLock.lock()
        defer { Self.processLock.unlock() }
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: Self.defaultsKey)
    }

    private func save(_ state: SharedState) {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private func acquireFileLock() -> Int32 {
        guard let url = lockURL else { return -1 }
        let descriptor = open(url.path, O_CREAT | O_RDWR, 0o644)
        if descriptor >= 0 { _ = flock(descriptor, LOCK_EX) }
        return descriptor
    }

    private func releaseFileLock(_ descriptor: Int32) {
        guard descriptor >= 0 else { return }
        _ = flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}

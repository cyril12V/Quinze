import Foundation
import SwiftData
import LearningCore

// SwiftData persistence (main context). Complex values are stored as JSON `Data` blobs next to scalar
// index fields (unit id, day, slot, dirty flag, updatedAt) used for queries and for the sync.

@Model
final class MemoryStateEntity {
    @Attribute(.unique) var unitId: String
    var data: Data
    var nextReviewAt: Date
    var updatedAt: Date
    var dirty: Bool

    init(unitId: String, data: Data, nextReviewAt: Date, updatedAt: Date, dirty: Bool) {
        self.unitId = unitId
        self.data = data
        self.nextReviewAt = nextReviewAt
        self.updatedAt = updatedAt
        self.dirty = dirty
    }
}

@Model
final class AttemptEntity {
    @Attribute(.unique) var id: String
    var sessionId: String?
    var exerciseId: String
    var answeredAt: Date
    var resultRaw: String
    var data: Data
    var updatedAt: Date
    var dirty: Bool

    init(id: String, sessionId: String?, exerciseId: String, answeredAt: Date, resultRaw: String,
         data: Data, updatedAt: Date, dirty: Bool) {
        self.id = id
        self.sessionId = sessionId
        self.exerciseId = exerciseId
        self.answeredAt = answeredAt
        self.resultRaw = resultRaw
        self.data = data
        self.updatedAt = updatedAt
        self.dirty = dirty
    }
}

@Model
final class SessionEntity {
    @Attribute(.unique) var id: String
    var dayString: String
    var slotRaw: String?
    var typeRaw: String
    var statusRaw: String
    var data: Data
    /// Codable `SessionRunner` snapshot used to resume an interrupted session.
    var runnerData: Data?
    var updatedAt: Date
    var dirty: Bool

    init(id: String, dayString: String, slotRaw: String?, typeRaw: String, statusRaw: String,
         data: Data, runnerData: Data? = nil, updatedAt: Date, dirty: Bool) {
        self.id = id
        self.dayString = dayString
        self.slotRaw = slotRaw
        self.typeRaw = typeRaw
        self.statusRaw = statusRaw
        self.data = data
        self.runnerData = runnerData
        self.updatedAt = updatedAt
        self.dirty = dirty
    }
}

@Model
final class VocabularyEntity {
    @Attribute(.unique) var dictionaryItemId: String
    var data: Data
    var updatedAt: Date
    var dirty: Bool

    init(dictionaryItemId: String, data: Data, updatedAt: Date, dirty: Bool) {
        self.dictionaryItemId = dictionaryItemId
        self.data = data
        self.updatedAt = updatedAt
        self.dirty = dirty
    }
}

/// An uncertain answer waiting for AI grading (offline, quota…).
@Model
final class PendingGradingEntity {
    @Attribute(.unique) var attemptId: String
    var exerciseId: String
    var userAnswer: String
    var createdAt: Date
    var tries: Int

    init(attemptId: String, exerciseId: String, userAnswer: String, createdAt: Date, tries: Int = 0) {
        self.attemptId = attemptId
        self.exerciseId = exerciseId
        self.userAnswer = userAnswer
        self.createdAt = createdAt
        self.tries = tries
    }
}

/// Key/value rows: profile & placement, settings, sync cursors.
@Model
final class AppStateEntity {
    @Attribute(.unique) var key: String
    var data: Data
    var updatedAt: Date

    init(key: String, data: Data, updatedAt: Date) {
        self.key = key
        self.data = data
        self.updatedAt = updatedAt
    }
}

struct PendingGrading: Sendable, Equatable {
    let attemptId: UUID
    let exerciseId: String
    let userAnswer: String
    let tries: Int
}

@MainActor
final class LocalStore {
    let container: ModelContainer
    /// False when the on-disk store could not be opened and an in-memory one is used instead.
    let isPersistent: Bool
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var context: ModelContext { container.mainContext }

    init(inMemory: Bool = false) {
        let schema = Schema([MemoryStateEntity.self, AttemptEntity.self, SessionEntity.self,
                             VocabularyEntity.self, PendingGradingEntity.self, AppStateEntity.self])
        let wanted = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        if let made = try? ModelContainer(for: schema, configurations: [wanted]) {
            container = made
            isPersistent = !inMemory
        } else {
            Log.store.error("SwiftData store could not be opened: falling back to memory")
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            // An in-memory container only fails on a programming error in the schema.
            guard let made = try? ModelContainer(for: schema, configurations: [fallback]) else {
                fatalError("SwiftData unavailable")
            }
            container = made
            isPersistent = false
        }
    }

    // MARK: Helpers

    private func encode<T: Encodable>(_ value: T) -> Data? {
        do { return try encoder.encode(value) } catch {
            Log.store.error("encode failed: \(String(describing: T.self), privacy: .public)")
            return nil
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) -> T? {
        try? decoder.decode(type, from: data)
    }

    private func fetch<E: PersistentModel>(_ descriptor: FetchDescriptor<E>) -> [E] {
        do { return try context.fetch(descriptor) } catch {
            Log.store.error("fetch failed: \(String(describing: E.self), privacy: .public)")
            return []
        }
    }

    func save() {
        guard context.hasChanges else { return }
        do { try context.save() } catch {
            Log.store.error("save failed: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    // MARK: Memory states

    func memoryStates() -> [MemoryState] {
        fetch(FetchDescriptor<MemoryStateEntity>()).compactMap { decode(MemoryState.self, $0.data) }
    }

    func upsertMemoryStates(_ states: [MemoryState], dirty: Bool) {
        guard !states.isEmpty else { return }
        let ids = states.map(\.unitId)
        var existing = Dictionary(fetch(FetchDescriptor<MemoryStateEntity>(
            predicate: #Predicate { ids.contains($0.unitId) })).map { ($0.unitId, $0) }, uniquingKeysWith: { a, _ in a })
        for state in states {
            guard let data = encode(state) else { continue }
            if let row = existing[state.unitId] {
                row.data = data
                row.nextReviewAt = state.nextReviewAt
                row.updatedAt = state.updatedAt
                row.dirty = dirty
            } else {
                let row = MemoryStateEntity(unitId: state.unitId, data: data, nextReviewAt: state.nextReviewAt,
                                            updatedAt: state.updatedAt, dirty: dirty)
                context.insert(row)
                existing[state.unitId] = row
            }
        }
        save()
    }

    /// Merge of server rows: a row replaces the local one only when its `updatedAt` is strictly newer.
    @discardableResult
    func mergeRemoteMemoryStates(_ states: [MemoryState]) -> Int {
        guard !states.isEmpty else { return 0 }
        let ids = states.map(\.unitId)
        var existing = Dictionary(fetch(FetchDescriptor<MemoryStateEntity>(
            predicate: #Predicate { ids.contains($0.unitId) })).map { ($0.unitId, $0) }, uniquingKeysWith: { a, _ in a })
        var changed = 0
        for state in states {
            guard let data = encode(state) else { continue }
            if let row = existing[state.unitId] {
                guard state.updatedAt > row.updatedAt else { continue }
                row.data = data
                row.nextReviewAt = state.nextReviewAt
                row.updatedAt = state.updatedAt
                row.dirty = false
            } else {
                let row = MemoryStateEntity(unitId: state.unitId, data: data, nextReviewAt: state.nextReviewAt,
                                            updatedAt: state.updatedAt, dirty: false)
                context.insert(row)
                existing[state.unitId] = row
            }
            changed += 1
        }
        save()
        return changed
    }

    func dirtyMemoryStates(limit: Int) -> [Stamped<MemoryState>] {
        var d = FetchDescriptor<MemoryStateEntity>(predicate: #Predicate { $0.dirty == true })
        d.fetchLimit = limit
        return fetch(d).compactMap { row in
            decode(MemoryState.self, row.data).map { Stamped(value: $0, updatedAt: row.updatedAt) }
        }
    }

    func markMemoryStatesClean(_ sent: [(id: String, updatedAt: Date)]) {
        guard !sent.isEmpty else { return }
        let ids = sent.map(\.id)
        let stamps = Dictionary(sent.map { ($0.id, $0.updatedAt) }, uniquingKeysWith: { a, _ in a })
        for row in fetch(FetchDescriptor<MemoryStateEntity>(predicate: #Predicate { ids.contains($0.unitId) }))
        where stamps[row.unitId] == row.updatedAt {
            row.dirty = false
        }
        save()
    }

    // MARK: Attempts

    /// The `limit` most recent attempts, oldest first.
    func recentAttempts(limit: Int = 500) -> [AttemptRecord] {
        var d = FetchDescriptor<AttemptEntity>(sortBy: [SortDescriptor(\.answeredAt, order: .reverse)])
        d.fetchLimit = limit
        return fetch(d).compactMap { decode(AttemptRecord.self, $0.data) }.reversed()
    }

    func attempt(id: UUID) -> AttemptRecord? {
        let key = id.uuidString
        var d = FetchDescriptor<AttemptEntity>(predicate: #Predicate { $0.id == key })
        d.fetchLimit = 1
        return fetch(d).first.flatMap { decode(AttemptRecord.self, $0.data) }
    }

    func attemptCount(sessionId: UUID) -> Int {
        let key: String? = sessionId.uuidString
        return (try? context.fetchCount(FetchDescriptor<AttemptEntity>(predicate: #Predicate { $0.sessionId == key }))) ?? 0
    }

    func saveAttempt(_ attempt: AttemptRecord, updatedAt: Date, dirty: Bool) {
        guard let data = encode(attempt) else { return }
        let key = attempt.id.uuidString
        var d = FetchDescriptor<AttemptEntity>(predicate: #Predicate { $0.id == key })
        d.fetchLimit = 1
        if let row = fetch(d).first {
            row.data = data
            row.resultRaw = attempt.result.rawValue
            row.updatedAt = updatedAt
            row.dirty = dirty
        } else {
            context.insert(AttemptEntity(id: key, sessionId: attempt.sessionId?.uuidString, exerciseId: attempt.exerciseId,
                                         answeredAt: attempt.answeredAt, resultRaw: attempt.result.rawValue,
                                         data: data, updatedAt: updatedAt, dirty: dirty))
        }
        save()
    }

    /// Attempts are immutable: a remote row only fills a missing one, or resolves a local `pending` attempt.
    @discardableResult
    func mergeRemoteAttempts(_ remote: [Stamped<AttemptRecord>]) -> Int {
        guard !remote.isEmpty else { return 0 }
        let ids = remote.map { $0.value.id.uuidString }
        var existing = Dictionary(fetch(FetchDescriptor<AttemptEntity>(
            predicate: #Predicate { ids.contains($0.id) })).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var changed = 0
        for item in remote {
            let a = item.value
            guard let data = encode(a) else { continue }
            let key = a.id.uuidString
            if let row = existing[key] {
                guard row.resultRaw == AttemptResult.pending.rawValue, a.result != .pending,
                      var local = decode(AttemptRecord.self, row.data) else { continue }
                local.result = a.result
                local.errorCategory = a.errorCategory
                guard let merged = encode(local) else { continue }
                row.data = merged
                row.resultRaw = a.result.rawValue
                row.updatedAt = item.updatedAt
                row.dirty = false
            } else {
                let row = AttemptEntity(id: key, sessionId: a.sessionId?.uuidString, exerciseId: a.exerciseId,
                                        answeredAt: a.answeredAt, resultRaw: a.result.rawValue, data: data,
                                        updatedAt: item.updatedAt, dirty: false)
                context.insert(row)
                existing[key] = row
            }
            changed += 1
        }
        save()
        return changed
    }

    func dirtyAttempts(limit: Int) -> [Stamped<AttemptRecord>] {
        var d = FetchDescriptor<AttemptEntity>(predicate: #Predicate { $0.dirty == true },
                                               sortBy: [SortDescriptor(\.answeredAt)])
        d.fetchLimit = limit
        return fetch(d).compactMap { row in
            decode(AttemptRecord.self, row.data).map { Stamped(value: $0, updatedAt: row.updatedAt) }
        }
    }

    func markAttemptsClean(_ sent: [(id: UUID, updatedAt: Date)]) {
        guard !sent.isEmpty else { return }
        let ids = sent.map { $0.id.uuidString }
        let stamps = Dictionary(sent.map { ($0.id.uuidString, $0.updatedAt) }, uniquingKeysWith: { a, _ in a })
        for row in fetch(FetchDescriptor<AttemptEntity>(predicate: #Predicate { ids.contains($0.id) }))
        where stamps[row.id] == row.updatedAt {
            row.dirty = false
        }
        save()
    }

    /// Re-attaches the attempts of a discarded local session to the session that replaced it.
    func repointAttempts(from old: UUID, to new: UUID) {
        let key: String? = old.uuidString
        for row in fetch(FetchDescriptor<AttemptEntity>(predicate: #Predicate { $0.sessionId == key })) {
            guard let a = decode(AttemptRecord.self, row.data) else { continue }
            let moved = AttemptRecord(id: a.id, exerciseId: a.exerciseId, sessionId: new, unitIds: a.unitIds,
                                      exerciseType: a.exerciseType, presentation: a.presentation,
                                      submittedAnswer: a.submittedAnswer, result: a.result,
                                      errorCategory: a.errorCategory, hintUsed: a.hintUsed,
                                      isRemediation: a.isRemediation, durationSeconds: a.durationSeconds,
                                      answeredAt: a.answeredAt)
            guard let data = encode(moved) else { continue }
            row.data = data
            row.sessionId = new.uuidString
            row.dirty = true
        }
        save()
    }

    // MARK: Sessions

    private func record(of row: SessionEntity) -> SessionRecord? { decode(SessionRecord.self, row.data) }

    func sessions() -> [SessionRecord] {
        fetch(FetchDescriptor<SessionEntity>()).compactMap { record(of: $0) }
    }

    func sessions(on day: LocalDay) -> [SessionRecord] {
        let key = day.isoString
        return fetch(FetchDescriptor<SessionEntity>(predicate: #Predicate { $0.dayString == key })).compactMap { record(of: $0) }
    }

    func session(id: UUID) -> SessionRecord? {
        let key = id.uuidString
        var d = FetchDescriptor<SessionEntity>(predicate: #Predicate { $0.id == key })
        d.fetchLimit = 1
        return fetch(d).first.flatMap { record(of: $0) }
    }

    func saveSession(_ session: SessionRecord, dirty: Bool = true) {
        guard let data = encode(session) else { return }
        let key = session.id.uuidString
        var d = FetchDescriptor<SessionEntity>(predicate: #Predicate { $0.id == key })
        d.fetchLimit = 1
        if let row = fetch(d).first {
            row.dayString = session.day.isoString
            row.slotRaw = session.slot?.rawValue
            row.typeRaw = session.type.rawValue
            row.statusRaw = session.status.rawValue
            row.data = data
            row.updatedAt = session.updatedAt
            row.dirty = dirty
        } else {
            context.insert(SessionEntity(id: key, dayString: session.day.isoString, slotRaw: session.slot?.rawValue,
                                         typeRaw: session.type.rawValue, statusRaw: session.status.rawValue,
                                         data: data, updatedAt: session.updatedAt, dirty: dirty))
        }
        save()
    }

    func saveRunner(_ runner: SessionRunner, for sessionId: UUID) {
        guard let data = encode(runner) else { return }
        let key = sessionId.uuidString
        var d = FetchDescriptor<SessionEntity>(predicate: #Predicate { $0.id == key })
        d.fetchLimit = 1
        guard let row = fetch(d).first else { return }
        row.runnerData = data
        save()
    }

    func runner(for sessionId: UUID) -> SessionRunner? {
        let key = sessionId.uuidString
        var d = FetchDescriptor<SessionEntity>(predicate: #Predicate { $0.id == key })
        d.fetchLimit = 1
        return fetch(d).first?.runnerData.flatMap { decode(SessionRunner.self, $0) }
    }

    func clearRunner(for sessionId: UUID) {
        let key = sessionId.uuidString
        var d = FetchDescriptor<SessionEntity>(predicate: #Predicate { $0.id == key })
        d.fetchLimit = 1
        fetch(d).first?.runnerData = nil
        save()
    }

    func dirtySessions(limit: Int) -> [SessionRecord] {
        var d = FetchDescriptor<SessionEntity>(predicate: #Predicate { $0.dirty == true })
        d.fetchLimit = limit
        return fetch(d).compactMap { record(of: $0) }
    }

    func markSessionsClean(_ sent: [(id: UUID, updatedAt: Date)]) {
        guard !sent.isEmpty else { return }
        let ids = sent.map { $0.id.uuidString }
        let stamps = Dictionary(sent.map { ($0.id.uuidString, $0.updatedAt) }, uniquingKeysWith: { a, _ in a })
        for row in fetch(FetchDescriptor<SessionEntity>(predicate: #Predicate { ids.contains($0.id) }))
        where stamps[row.id] == row.updatedAt {
            row.dirty = false
        }
        save()
    }

    /// Newer `updatedAt` wins. A remote session that occupies the same (day, slot) as a different local
    /// one (two devices) replaces it, and the local attempts are re-attached, so the unique key holds.
    @discardableResult
    func mergeRemoteSessions(_ remote: [SessionRecord]) -> Int {
        guard !remote.isEmpty else { return 0 }
        var changed = 0
        for incoming in remote {
            let key = incoming.id.uuidString
            var d = FetchDescriptor<SessionEntity>(predicate: #Predicate { $0.id == key })
            d.fetchLimit = 1
            if let row = fetch(d).first {
                guard incoming.updatedAt > row.updatedAt, let data = encode(incoming) else { continue }
                row.dayString = incoming.day.isoString
                row.slotRaw = incoming.slot?.rawValue
                row.typeRaw = incoming.type.rawValue
                row.statusRaw = incoming.status.rawValue
                row.data = data
                row.updatedAt = incoming.updatedAt
                row.dirty = false
                if incoming.status == .completed { row.runnerData = nil }
            } else {
                if let slot = incoming.slot {
                    let day = incoming.day.isoString
                    let slotRaw: String? = slot.rawValue
                    let clashes = fetch(FetchDescriptor<SessionEntity>(
                        predicate: #Predicate { $0.dayString == day && $0.slotRaw == slotRaw && $0.id != key }))
                    for clash in clashes {
                        if let uuid = UUID(uuidString: clash.id) { repointAttempts(from: uuid, to: incoming.id) }
                        context.delete(clash)
                    }
                }
                guard let data = encode(incoming) else { continue }
                context.insert(SessionEntity(id: key, dayString: incoming.day.isoString, slotRaw: incoming.slot?.rawValue,
                                             typeRaw: incoming.type.rawValue, statusRaw: incoming.status.rawValue,
                                             data: data, updatedAt: incoming.updatedAt, dirty: false))
            }
            changed += 1
        }
        save()
        return changed
    }

    // MARK: Vocabulary

    func vocabulary() -> [VocabularyRecord] {
        fetch(FetchDescriptor<VocabularyEntity>()).compactMap { decode(VocabularyRecord.self, $0.data) }
    }

    func saveVocabulary(_ item: VocabularyRecord, dirty: Bool) {
        guard let data = encode(item) else { return }
        let key = item.dictionaryItemId
        var d = FetchDescriptor<VocabularyEntity>(predicate: #Predicate { $0.dictionaryItemId == key })
        d.fetchLimit = 1
        if let row = fetch(d).first {
            row.data = data
            row.updatedAt = item.updatedAt
            row.dirty = dirty
        } else {
            context.insert(VocabularyEntity(dictionaryItemId: key, data: data, updatedAt: item.updatedAt, dirty: dirty))
        }
        save()
    }

    @discardableResult
    func mergeRemoteVocabulary(_ items: [VocabularyRecord]) -> Int {
        var changed = 0
        for item in items {
            let key = item.dictionaryItemId
            var d = FetchDescriptor<VocabularyEntity>(predicate: #Predicate { $0.dictionaryItemId == key })
            d.fetchLimit = 1
            if let row = fetch(d).first, item.updatedAt <= row.updatedAt { continue }
            saveVocabulary(item, dirty: false)
            changed += 1
        }
        return changed
    }

    func dirtyVocabulary(limit: Int) -> [VocabularyRecord] {
        var d = FetchDescriptor<VocabularyEntity>(predicate: #Predicate { $0.dirty == true })
        d.fetchLimit = limit
        return fetch(d).compactMap { decode(VocabularyRecord.self, $0.data) }
    }

    func markVocabularyClean(_ sent: [(id: String, updatedAt: Date)]) {
        guard !sent.isEmpty else { return }
        let ids = sent.map(\.id)
        let stamps = Dictionary(sent.map { ($0.id, $0.updatedAt) }, uniquingKeysWith: { a, _ in a })
        for row in fetch(FetchDescriptor<VocabularyEntity>(predicate: #Predicate { ids.contains($0.dictionaryItemId) }))
        where stamps[row.dictionaryItemId] == row.updatedAt {
            row.dirty = false
        }
        save()
    }

    // MARK: Pending AI gradings

    func enqueueGrading(attemptId: UUID, exerciseId: String, userAnswer: String, now: Date) {
        let key = attemptId.uuidString
        var d = FetchDescriptor<PendingGradingEntity>(predicate: #Predicate { $0.attemptId == key })
        d.fetchLimit = 1
        guard fetch(d).isEmpty else { return }
        context.insert(PendingGradingEntity(attemptId: key, exerciseId: exerciseId, userAnswer: userAnswer, createdAt: now))
        save()
    }

    func pendingGradings(limit: Int) -> [PendingGrading] {
        var d = FetchDescriptor<PendingGradingEntity>(sortBy: [SortDescriptor(\.createdAt)])
        d.fetchLimit = limit
        return fetch(d).compactMap { row in
            UUID(uuidString: row.attemptId).map {
                PendingGrading(attemptId: $0, exerciseId: row.exerciseId, userAnswer: row.userAnswer, tries: row.tries)
            }
        }
    }

    func pendingGradingCount() -> Int {
        (try? context.fetchCount(FetchDescriptor<PendingGradingEntity>())) ?? 0
    }

    func bumpGradingTries(attemptId: UUID) {
        let key = attemptId.uuidString
        var d = FetchDescriptor<PendingGradingEntity>(predicate: #Predicate { $0.attemptId == key })
        d.fetchLimit = 1
        if let row = fetch(d).first { row.tries += 1; save() }
    }

    func removePendingGrading(attemptId: UUID) {
        let key = attemptId.uuidString
        for row in fetch(FetchDescriptor<PendingGradingEntity>(predicate: #Predicate { $0.attemptId == key })) {
            context.delete(row)
        }
        save()
    }

    // MARK: Key/value state

    func value<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        var d = FetchDescriptor<AppStateEntity>(predicate: #Predicate { $0.key == key })
        d.fetchLimit = 1
        return fetch(d).first.flatMap { decode(type, $0.data) }
    }

    func setValue<T: Encodable>(_ value: T, for key: String, now: Date = .now) {
        guard let data = encode(value) else { return }
        var d = FetchDescriptor<AppStateEntity>(predicate: #Predicate { $0.key == key })
        d.fetchLimit = 1
        if let row = fetch(d).first {
            row.data = data
            row.updatedAt = now
        } else {
            context.insert(AppStateEntity(key: key, data: data, updatedAt: now))
        }
        save()
    }

    func removeValue(for key: String) {
        for row in fetch(FetchDescriptor<AppStateEntity>(predicate: #Predicate { $0.key == key })) {
            context.delete(row)
        }
        save()
    }

    // MARK: Wipe

    /// Deletes everything studied in some subjects (ids starting with "ar." / "cg.", sessions of those
    /// subjects). Used once when the content of these subjects was rewritten from scratch.
    func wipeSubjects(_ codes: Set<String>) {
        let prefixes = codes.map { $0 + "." }
        func owned(_ id: String) -> Bool { prefixes.contains { id.hasPrefix($0) } }
        for row in fetch(FetchDescriptor<MemoryStateEntity>()) where owned(row.unitId) { context.delete(row) }
        for row in fetch(FetchDescriptor<AttemptEntity>()) where owned(row.exerciseId) { context.delete(row) }
        for row in fetch(FetchDescriptor<VocabularyEntity>()) where owned(row.dictionaryItemId) { context.delete(row) }
        for row in fetch(FetchDescriptor<PendingGradingEntity>()) where owned(row.exerciseId) { context.delete(row) }
        for row in fetch(FetchDescriptor<SessionEntity>()) {
            if let session = decode(SessionRecord.self, row.data), codes.contains(session.subjectCode) { context.delete(row) }
        }
        save()
    }

    /// Deletes every row (account deletion, switching accounts).
    func wipeAll() {
        do {
            try context.delete(model: MemoryStateEntity.self)
            try context.delete(model: AttemptEntity.self)
            try context.delete(model: SessionEntity.self)
            try context.delete(model: VocabularyEntity.self)
            try context.delete(model: PendingGradingEntity.self)
            try context.delete(model: AppStateEntity.self)
            try context.save()
        } catch {
            Log.store.error("wipe failed: \(String(describing: type(of: error)), privacy: .public)")
        }
    }
}

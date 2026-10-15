import Foundation
import LearningPrimitives

// Small, versioned, Codable state shared between the app and the Screen Time extensions through
// App Group UserDefaults. It never contains anything synced to a server: the selection data holds
// opaque, device-specific tokens.

/// Mirror of the app's `RestrictionMode` (the app type lives in a contract file the extensions do not compile).
enum StoredMode: String, Codable, Sendable, CaseIterable {
    case selectedApps
    case allExceptAllowed
}

/// Why a slot's shield stopped (or never started).
enum LiftReason: String, Codable, Sendable {
    case completed
    case emergency
    case expired
    case disabled
    case authorizationLost
    case stale

    /// Reasons that must not be undone by a later reconcile / monitor restart on the same day.
    var blocksReactivation: Bool {
        switch self {
        case .completed, .emergency, .expired: return true
        case .disabled, .authorizationLost, .stale: return false
        }
    }
}

/// Restriction record of one slot on one local day.
struct SlotRecord: Codable, Equatable, Sendable {
    var slot: SessionSlot
    var day: LocalDay
    var completed: Bool = false
    var completedAt: Date?
    var active: Bool = false
    var activatedAt: Date?
    /// Safety deadline: the shield is always lifted at this instant, completed or not.
    var expiresAt: Date?
    var liftReason: LiftReason?
    var liftedAt: Date?

    init(slot: SessionSlot, day: LocalDay) {
        self.slot = slot
        self.day = day
    }
}

struct EmergencyEvent: Codable, Equatable, Sendable {
    var date: Date
    var reason: String
    var slots: [SessionSlot]
}

struct SharedState: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let maxEmergencyEvents = 50
    static let recordRetentionDays = 3

    var version: Int = SharedState.currentVersion
    /// User-level switch "Restreindre les apps pendant les leçons".
    var enabled: Bool = false
    var mode: StoredMode = .selectedApps
    /// JSON-encoded `FamilyActivitySelection` (opaque tokens, device-local).
    var selectionData: Data?
    /// Copy of the schedule used to build the DeviceActivity intervals (so extensions know the windows).
    var schedule: DailySchedule?
    /// Records keyed by `"<yyyy-MM-dd>#<slot>"`.
    var records: [String: SlotRecord] = [:]
    var emergencyLog: [EmergencyEvent] = []
    /// Last authorization status seen as approved by the app (used to detect a revocation).
    var authorizationWasApproved: Bool = false
    /// Time zone for which monitoring was last (re)started.
    var monitoringTimeZoneIdentifier: String?

    init() {}

    // Tolerant decoding: missing keys fall back to defaults so an older or newer writer never breaks a reader.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? SharedState.currentVersion
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        mode = try c.decodeIfPresent(StoredMode.self, forKey: .mode) ?? .selectedApps
        selectionData = try c.decodeIfPresent(Data.self, forKey: .selectionData)
        schedule = try c.decodeIfPresent(DailySchedule.self, forKey: .schedule)
        records = try c.decodeIfPresent([String: SlotRecord].self, forKey: .records) ?? [:]
        emergencyLog = try c.decodeIfPresent([EmergencyEvent].self, forKey: .emergencyLog) ?? []
        authorizationWasApproved = try c.decodeIfPresent(Bool.self, forKey: .authorizationWasApproved) ?? false
        monitoringTimeZoneIdentifier = try c.decodeIfPresent(String.self, forKey: .monitoringTimeZoneIdentifier)
    }

    // MARK: Records

    static func key(slot: SessionSlot, day: LocalDay) -> String {
        "\(day.isoString)#\(slot.rawValue)"
    }

    func record(_ slot: SessionSlot, _ day: LocalDay) -> SlotRecord? {
        records[Self.key(slot: slot, day: day)]
    }

    mutating func setRecord(_ record: SlotRecord) {
        records[Self.key(slot: record.slot, day: record.day)] = record
    }

    /// Keys of the records of `slot` (any day), so callers can mutate while iterating.
    func recordKeys(for slot: SessionSlot) -> [String] {
        records.filter { $0.value.slot == slot }.map { $0.key }
    }

    /// Drops records older than `recordRetentionDays` (never an active one).
    mutating func prune(today: LocalDay, calendar: Calendar) {
        let limit = today.adding(days: -Self.recordRetentionDays, calendar: calendar)
        records = records.filter { $0.value.active || $0.value.day >= limit }
    }

    mutating func appendEmergency(_ event: EmergencyEvent) {
        emergencyLog.append(event)
        if emergencyLog.count > Self.maxEmergencyEvents {
            emergencyLog.removeFirst(emergencyLog.count - Self.maxEmergencyEvents)
        }
    }

    // MARK: Windows

    var effectiveSchedule: DailySchedule { schedule ?? .default }

    func window(for slot: SessionSlot) -> (start: TimeOfDay, end: TimeOfDay) {
        effectiveSchedule.restrictionWindow(for: slot)
    }
}

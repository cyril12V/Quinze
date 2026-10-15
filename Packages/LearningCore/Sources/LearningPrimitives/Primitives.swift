import Foundation

// Types shared by the app, the pedagogical engine and the Screen Time extensions.
// Keep this file free of any dependency other than Foundation: the DeviceActivity
// monitor extension runs under a strict memory limit.

/// The three independent daily lesson slots.
public enum SessionSlot: String, Codable, CaseIterable, Sendable, Comparable, Identifiable {
    case morning, afternoon, evening

    public var id: String { rawValue }

    public var index: Int {
        switch self {
        case .morning: return 0
        case .afternoon: return 1
        case .evening: return 2
        }
    }

    /// Session 1 = learning, 2 = application, 3 = consolidation.
    public var defaultSessionType: SessionType {
        switch self {
        case .morning: return .learning
        case .afternoon: return .application
        case .evening: return .consolidation
        }
    }

    public var displayName: String {
        switch self {
        case .morning: return "Matin"
        case .afternoon: return "Après-midi"
        case .evening: return "Soir"
        }
    }

    public static func < (lhs: SessionSlot, rhs: SessionSlot) -> Bool { lhs.index < rhs.index }
}

public enum SessionType: String, Codable, CaseIterable, Sendable {
    case learning, application, consolidation, diagnostic, assessment, extra

    public var displayName: String {
        switch self {
        case .learning: return "Apprentissage"
        case .application: return "Application"
        case .consolidation: return "Consolidation"
        case .diagnostic: return "Évaluation initiale"
        case .assessment: return "Test de consolidation"
        case .extra: return "Révision libre"
        }
    }
}

/// A wall-clock time (no date, no time zone).
public struct TimeOfDay: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    /// Parses "HH:mm" (also accepts "HH:mm:ss" as returned by Postgres `time`).
    public init?(string: String) {
        let parts = string.split(separator: ":")
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        self.init(hour: h, minute: m)
    }

    public init(minutesSinceMidnight: Int) {
        let clamped = min(max(minutesSinceMidnight, 0), 23 * 60 + 59)
        self.init(hour: clamped / 60, minute: clamped % 60)
    }

    public var minutesSinceMidnight: Int { hour * 60 + minute }

    /// Adds minutes, clamping to the same day (00:00 ... 23:59).
    public func adding(minutes: Int) -> TimeOfDay {
        TimeOfDay(minutesSinceMidnight: minutesSinceMidnight + minutes)
    }

    public var dateComponents: DateComponents { DateComponents(hour: hour, minute: minute) }

    /// "09:05"
    public var description: String { String(format: "%02d:%02d", hour, minute) }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}

/// A calendar day in the user's local time zone.
public struct LocalDay: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// Parses "yyyy-MM-dd".
    public init?(isoString: String) {
        let parts = isoString.prefix(10).split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// "2026-10-13"
    public var isoString: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var description: String { isoString }

    /// Start of the day in the given calendar's time zone.
    public func startDate(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    /// The instant at which `time` occurs on this day (nil when the wall-clock time does not exist, e.g. DST gap).
    public func date(at time: TimeOfDay, calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: time.hour, minute: time.minute))
    }

    public func adding(days: Int, calendar: Calendar = .current) -> LocalDay {
        let shifted = calendar.date(byAdding: .day, value: days, to: startDate(calendar: calendar)) ?? startDate(calendar: calendar)
        return LocalDay(date: shifted, calendar: calendar)
    }

    /// Number of days from `self` to `other` (positive when `other` is later).
    public func days(until other: LocalDay, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: startDate(calendar: calendar), to: other.startDate(calendar: calendar)).day ?? 0
    }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// The user's daily lesson schedule.
public struct DailySchedule: Codable, Hashable, Sendable {
    public var morning: TimeOfDay
    public var afternoon: TimeOfDay
    public var evening: TimeOfDay
    /// IANA identifier recorded when the schedule was saved (informational: the system applies wall-clock times in the current zone).
    public var timeZoneIdentifier: String
    public var enabled: Bool
    /// Maximum duration of a restriction after the slot starts. Restrictions are always lifted at the end of this window,
    /// even if the lesson was not done ("échéance de sécurité").
    public var safetyWindowMinutes: Int
    /// A slot's lesson can be done this many minutes before its scheduled time (it then pre-validates the slot).
    public var earlyStartMinutes: Int

    public init(morning: TimeOfDay, afternoon: TimeOfDay, evening: TimeOfDay,
                timeZoneIdentifier: String = TimeZone.current.identifier, enabled: Bool = true,
                safetyWindowMinutes: Int = 120, earlyStartMinutes: Int = 60) {
        self.morning = morning
        self.afternoon = afternoon
        self.evening = evening
        self.timeZoneIdentifier = timeZoneIdentifier
        self.enabled = enabled
        self.safetyWindowMinutes = safetyWindowMinutes
        self.earlyStartMinutes = earlyStartMinutes
    }

    public static let `default` = DailySchedule(
        morning: TimeOfDay(hour: 9, minute: 0),
        afternoon: TimeOfDay(hour: 14, minute: 0),
        evening: TimeOfDay(hour: 20, minute: 0))

    public static let minimumSafetyWindowMinutes = 15
    public static let maximumSafetyWindowMinutes = 240
    public static let minimumGapBetweenSlotsMinutes = 30

    public func time(for slot: SessionSlot) -> TimeOfDay {
        switch slot {
        case .morning: return morning
        case .afternoon: return afternoon
        case .evening: return evening
        }
    }

    public mutating func setTime(_ time: TimeOfDay, for slot: SessionSlot) {
        switch slot {
        case .morning: morning = time
        case .afternoon: afternoon = time
        case .evening: evening = time
        }
    }

    /// Restriction window of a slot: from the slot time to slot time + safety window,
    /// clamped to 23:59 so that a window never crosses midnight.
    public func restrictionWindow(for slot: SessionSlot) -> (start: TimeOfDay, end: TimeOfDay) {
        let start = time(for: slot)
        let window = min(max(safetyWindowMinutes, Self.minimumSafetyWindowMinutes), Self.maximumSafetyWindowMinutes)
        return (start, start.adding(minutes: window))
    }

    public enum Issue: Equatable, Sendable {
        case slotsNotInOrder
        case slotsTooClose(SessionSlot, SessionSlot)
        case windowTooShort(SessionSlot)
        case safetyWindowOutOfRange
    }

    /// Validation used by the settings screen before saving.
    public func validate() -> [Issue] {
        var issues: [Issue] = []
        if !(morning < afternoon && afternoon < evening) { issues.append(.slotsNotInOrder) }
        let pairs: [(SessionSlot, SessionSlot)] = [(.morning, .afternoon), (.afternoon, .evening)]
        for (a, b) in pairs where time(for: b).minutesSinceMidnight - time(for: a).minutesSinceMidnight < Self.minimumGapBetweenSlotsMinutes {
            issues.append(.slotsTooClose(a, b))
        }
        if !(Self.minimumSafetyWindowMinutes...Self.maximumSafetyWindowMinutes).contains(safetyWindowMinutes) {
            issues.append(.safetyWindowOutOfRange)
        }
        for slot in SessionSlot.allCases {
            let w = restrictionWindow(for: slot)
            // DeviceActivity requires intervals of at least 15 minutes.
            if w.end.minutesSinceMidnight - w.start.minutesSinceMidnight < 15 { issues.append(.windowTooShort(slot)) }
        }
        return issues
    }
}

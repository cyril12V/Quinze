import Foundation
import LearningCore

// Pure computations (no storage, no UI, no network): slot statuses and learner snapshots.

enum SlotLogic {
    /// The instant at which `time` occurs on `day` (falls back to midnight + minutes when the wall-clock
    /// time does not exist, e.g. in a DST gap).
    static func instant(day: LocalDay, time: TimeOfDay, calendar: Calendar = .current) -> Date {
        day.date(at: time, calendar: calendar)
            ?? day.startDate(calendar: calendar).addingTimeInterval(TimeInterval(time.minutesSinceMidnight * 60))
    }

    /// Status of one slot for `day`, given the sessions already stored for that slot.
    /// - completed: a completed session exists.
    /// - inProgress: a started and unfinished session exists.
    /// - upcoming: before `slot time − earlyStartMinutes`.
    /// - available: from the early-start instant until the end of the safety window.
    /// - missed: after the safety window, lesson not done (still startable for practice).
    static func status(slot: SessionSlot, day: LocalDay, now: Date, schedule: DailySchedule,
                       sessions: [SessionRecord], calendar: Calendar = .current) -> SlotStatus {
        let mine = sessions.filter { $0.slot == slot && $0.day == day }
        if mine.contains(where: { $0.status == .completed }) { return .completed }
        if mine.contains(where: { $0.status == .inProgress }) { return .inProgress }
        let window = schedule.restrictionWindow(for: slot)
        let start = instant(day: day, time: window.start, calendar: calendar)
        let end = instant(day: day, time: window.end, calendar: calendar)
        let earlyStart = start.addingTimeInterval(-TimeInterval(max(0, schedule.earlyStartMinutes) * 60))
        if now < earlyStart { return .upcoming }
        if now <= end { return .available }
        return .missed
    }

    static func slotStates(day: LocalDay, now: Date, schedule: DailySchedule, sessions: [SessionRecord],
                           activeRestrictions: Set<SessionSlot>, calendar: Calendar = .current) -> [SlotState] {
        SessionSlot.allCases.map { slot in
            let status = status(slot: slot, day: day, now: now, schedule: schedule, sessions: sessions, calendar: calendar)
            let sessionId = sessions
                .filter { $0.slot == slot && $0.day == day }
                .sorted { rank($0.status) > rank($1.status) }
                .first?.id
            return SlotState(slot: slot, scheduledTime: schedule.time(for: slot), status: status,
                             restrictionActive: activeRestrictions.contains(slot) && status != .completed,
                             sessionId: sessionId)
        }
    }

    private static func rank(_ status: SessionStatus) -> Int {
        switch status {
        case .completed: return 3
        case .inProgress: return 2
        case .scheduled: return 1
        case .expired, .skipped: return 0
        }
    }

    /// Days on which at least one lesson-like session was completed (the diagnostic does not count).
    static func completedDays(sessions: [SessionRecord]) -> Set<LocalDay> {
        Set(sessions.filter { $0.status == .completed && $0.type != .diagnostic }.map(\.day))
    }
}

enum SnapshotBuilder {
    /// Builds the engine's view of the learner from what is stored locally.
    /// `attempts` can be in any order; the most recent `attemptLimit` are kept, oldest first.
    static func build(memoryStates: [MemoryState], attempts: [AttemptRecord], sessions: [SessionRecord],
                      profile: UserProfileRecord, attemptLimit: Int = 500) -> LearnerSnapshot {
        var states: [String: MemoryState] = [:]
        for state in memoryStates { states[state.unitId] = state }
        let recent = attempts.sorted { $0.answeredAt < $1.answeredAt }.suffix(max(0, attemptLimit))
        let completed = sessions.filter { $0.status == .completed }
        let lessonIds = Set(completed.compactMap(\.lessonId))
        let lastAssessment = completed.filter { $0.type == .assessment }.compactMap(\.completedAt).max()
        return LearnerSnapshot(
            memoryStates: states,
            recentAttempts: Array(recent),
            completedLessonIds: lessonIds,
            placedLessonIds: Set(profile.placement?.placedLessonIds ?? []),
            estimatedLevel: profile.placement?.estimatedLevel ?? profile.estimatedLevel,
            lastAssessmentAt: lastAssessment,
            startedAt: profile.startedAt)
    }
}

extension DailySchedule.Issue {
    /// French message shown under the schedule pickers.
    var message: String {
        switch self {
        case .slotsNotInOrder:
            return "Les leçons doivent se suivre : matin, puis après-midi, puis soir."
        case .slotsTooClose(let a, let b):
            return "Laisse au moins \(DailySchedule.minimumGapBetweenSlotsMinutes) minutes entre la leçon « \(a.displayName.lowercased()) » et la leçon « \(b.displayName.lowercased()) »."
        case .windowTooShort(let slot):
            return "La leçon « \(slot.displayName.lowercased()) » est trop tard dans la journée : il faut au moins 15 minutes avant minuit."
        case .safetyWindowOutOfRange:
            return "L'échéance de sécurité doit durer entre \(DailySchedule.minimumSafetyWindowMinutes) minutes et 4 heures."
        }
    }
}

import Foundation
import LearningPrimitives

/// The restriction state machine, shared by the app and the three extensions.
///
/// Invariants:
/// - one record per (day, slot); one shield store per slot;
/// - a shield is always paired with `active == true` and an `expiresAt` deadline;
/// - every mutation (state + ManagedSettings call) runs inside `SharedStateStore.update`, which is
///   serialised across processes;
/// - nothing here can keep a shield forever: `intervalDidEnd`, `reconcile` and `emergencyUnlock`
///   all clear stores unconditionally.
struct SlotEngine {
    let store: SharedStateStore
    let shields: any ShieldControlling
    private let calendarOverride: Calendar?

    init(store: SharedStateStore = .shared,
         shields: any ShieldControlling = SystemShieldController(),
         calendar: Calendar? = nil) {
        self.store = store
        self.shields = shields
        self.calendarOverride = calendar
    }

    /// Evaluated at each call so a time zone change is taken into account.
    private var calendar: Calendar { calendarOverride ?? Calendar.autoupdatingCurrent }

    struct ReconcileOutcome: Equatable, Sendable {
        var activeSlots: [SessionSlot]
        var changed: Bool
    }

    // MARK: Time helpers

    private func instant(_ day: LocalDay, _ time: TimeOfDay) -> Date {
        day.date(at: time, calendar: calendar)
            ?? day.startDate(calendar: calendar).addingTimeInterval(TimeInterval(time.minutesSinceMidnight * 60))
    }

    private func windowInstants(_ slot: SessionSlot, _ day: LocalDay, _ state: SharedState) -> (start: Date, end: Date) {
        let window = state.window(for: slot)
        return (instant(day, window.start), instant(day, window.end))
    }

    // MARK: Monitor extension entry points

    /// `intervalDidStart`: shields the slot when the feature is on and the slot's lesson is not already completed.
    @discardableResult
    func intervalDidStart(slot: SessionSlot, now: Date) -> Bool {
        store.update { state in
            let today = LocalDay(date: now, calendar: calendar)
            state.prune(today: today, calendar: calendar)
            var record = state.record(slot, today) ?? SlotRecord(slot: slot, day: today)
            let end = windowInstants(slot, today, state).end

            // Feature off: make sure nothing stays.
            guard state.enabled else {
                shields.clear(slot: slot)
                return false
            }
            // Lesson already done (early-start pre-validation) or restriction already lifted today.
            if record.completed || (record.liftReason?.blocksReactivation ?? false) {
                shields.clear(slot: slot)
                if record.active {
                    record.active = false
                    state.setRecord(record)
                }
                return false
            }
            // Late delivery: the window is already over.
            if end <= now {
                shields.clear(slot: slot)
                record.active = false
                record.liftReason = .expired
                record.liftedAt = now
                state.setRecord(record)
                return false
            }
            guard shields.apply(slot: slot, selectionData: state.selectionData, mode: state.mode) else {
                shields.clear(slot: slot)
                record.active = false
                state.setRecord(record)
                return false
            }
            record.active = true
            record.activatedAt = record.activatedAt ?? now
            record.expiresAt = end
            record.liftReason = nil
            record.liftedAt = nil
            state.setRecord(record)
            return true
        }
    }

    /// `intervalDidEnd`: always clears the slot store; records `expired` when the lesson was not completed.
    func intervalDidEnd(slot: SessionSlot, now: Date) {
        store.update { state in
            let today = LocalDay(date: now, calendar: calendar)
            shields.clear(slot: slot)

            for key in state.recordKeys(for: slot) {
                guard var record = state.records[key], record.active else { continue }
                record.active = false
                if !record.completed && record.liftReason == nil {
                    record.liftReason = .expired
                    record.liftedAt = now
                }
                state.records[key] = record
            }
            guard state.enabled else { return }
            var todayRecord = state.record(slot, today) ?? SlotRecord(slot: slot, day: today)
            if !todayRecord.completed && todayRecord.liftReason == nil {
                todayRecord.liftReason = .expired
                todayRecord.liftedAt = now
                state.setRecord(todayRecord)
            }
        }
    }

    // MARK: App / shield action entry points

    /// The lesson of (slot, day) is completed. Returns true when an active shield was lifted.
    @discardableResult
    func markCompleted(slot: SessionSlot, day: LocalDay, now: Date) -> Bool {
        store.update { state in
            var record = state.record(slot, day) ?? SlotRecord(slot: slot, day: day)
            record.completed = true
            record.completedAt = record.completedAt ?? now
            var lifted = false
            if record.active {
                shields.clear(slot: slot)
                record.active = false
                record.liftReason = .completed
                record.liftedAt = now
                lifted = true
            } else if day == LocalDay(date: now, calendar: calendar) {
                // Defensive: a shield without a record (crash) must not outlive a completed lesson.
                shields.clear(slot: slot)
            }
            state.setRecord(record)
            return lifted
        }
    }

    /// Lifts every active shield and every slot currently inside its window. Always works.
    @discardableResult
    func emergencyUnlock(reason: String, now: Date) -> [SessionSlot] {
        store.update { state in
            let today = LocalDay(date: now, calendar: calendar)
            var lifted: [SessionSlot] = []
            for slot in SessionSlot.allCases {
                var touched = false
                shields.clear(slot: slot)
                for key in state.recordKeys(for: slot) {
                    guard var record = state.records[key], record.active else { continue }
                    record.active = false
                    record.liftReason = .emergency
                    record.liftedAt = now
                    state.records[key] = record
                    touched = true
                }
                // A slot inside its window but not shielded yet must not be shielded right after.
                let window = windowInstants(slot, today, state)
                var todayRecord = state.record(slot, today) ?? SlotRecord(slot: slot, day: today)
                if window.start <= now, now < window.end, !todayRecord.completed, todayRecord.liftReason == nil {
                    todayRecord.liftReason = .emergency
                    todayRecord.liftedAt = now
                    state.setRecord(todayRecord)
                    touched = true
                }
                if touched { lifted.append(slot) }
            }
            state.appendEmergency(EmergencyEvent(date: now, reason: reason, slots: lifted))
            return lifted
        }
    }

    // MARK: Settings changes (app only)

    func setEnabled(_ enabled: Bool, now: Date) {
        store.update { state in
            state.enabled = enabled
            if !enabled {
                for slot in SessionSlot.allCases {
                    shields.clear(slot: slot)
                    for key in state.recordKeys(for: slot) {
                        guard var record = state.records[key], record.active else { continue }
                        record.active = false
                        record.liftReason = .disabled
                        record.liftedAt = now
                        state.records[key] = record
                    }
                }
            } else {
                // Non-final lift reasons of today are forgotten so the slot can start again.
                for key in Array(state.records.keys) {
                    guard var record = state.records[key], let reason = record.liftReason, !reason.blocksReactivation else { continue }
                    record.liftReason = nil
                    record.liftedAt = nil
                    state.records[key] = record
                }
            }
        }
    }

    /// Clears every store and marks the active records as lifted for `reason` (not an emergency).
    func liftAll(reason: LiftReason, now: Date) {
        store.update { state in
            for slot in SessionSlot.allCases {
                shields.clear(slot: slot)
                for key in state.recordKeys(for: slot) {
                    guard var record = state.records[key], record.active else { continue }
                    record.active = false
                    record.liftReason = reason
                    record.liftedAt = now
                    state.records[key] = record
                }
            }
        }
    }

    func updateSelection(data: Data?, mode: StoredMode, now: Date) {
        store.update { state in
            state.selectionData = data
            state.mode = mode
            // Re-apply to the slots that are shielded right now.
            for slot in SessionSlot.allCases {
                for key in state.recordKeys(for: slot) {
                    guard var record = state.records[key], record.active else { continue }
                    if !shields.apply(slot: slot, selectionData: data, mode: mode) {
                        shields.clear(slot: slot)
                        record.active = false
                        record.liftReason = .stale
                        record.liftedAt = now
                        state.records[key] = record
                    }
                }
            }
        }
    }

    /// Stores the schedule copy read by the extensions. When a slot's window changed, an `expired`
    /// mark of today is forgotten so the new window can start.
    func updateSchedule(_ schedule: DailySchedule, now: Date) {
        store.update { state in
            let today = LocalDay(date: now, calendar: calendar)
            let old = state.effectiveSchedule
            state.schedule = schedule
            state.monitoringTimeZoneIdentifier = calendar.timeZone.identifier
            for slot in SessionSlot.allCases {
                let oldWindow = old.restrictionWindow(for: slot)
                let newWindow = schedule.restrictionWindow(for: slot)
                guard oldWindow.start != newWindow.start || oldWindow.end != newWindow.end,
                      var record = state.record(slot, today), !record.active, record.liftReason == .expired else { continue }
                record.liftReason = nil
                record.liftedAt = nil
                state.setRecord(record)
            }
        }
    }

    func setAuthorizationApproved(_ approved: Bool) {
        store.update { state in state.authorizationWasApproved = approved }
    }

    // MARK: Reconcile

    /// Crash recovery and consistency. Clears shields past their deadline, completed, disabled or stale,
    /// applies the shield of a slot that should be active but is not, and clears every store that has
    /// no active record. Idempotent.
    @discardableResult
    func reconcile(now: Date, authorized: Bool) -> ReconcileOutcome {
        store.update { state in
            let today = LocalDay(date: now, calendar: calendar)
            state.prune(today: today, calendar: calendar)
            var changed = false

            // 1. Active records that must stop.
            for key in Array(state.records.keys) {
                guard var record = state.records[key], record.active else { continue }
                let reason: LiftReason?
                if record.completed {
                    reason = .completed
                } else if !state.enabled {
                    reason = .disabled
                } else if !authorized {
                    reason = .authorizationLost
                } else if let deadline = record.expiresAt, now >= deadline {
                    reason = .expired
                } else if record.expiresAt == nil || record.day != today {
                    reason = .stale
                } else {
                    reason = nil
                }
                if let reason {
                    shields.clear(slot: record.slot)
                    record.active = false
                    record.liftReason = reason
                    record.liftedAt = now
                    state.records[key] = record
                    changed = true
                }
            }

            // 2. Today's slots: start the ones that should be running, clear the others.
            for slot in SessionSlot.allCases {
                let existing = state.record(slot, today)
                var record = existing ?? SlotRecord(slot: slot, day: today)
                let window = windowInstants(slot, today, state)

                if record.active {
                    continue
                }
                let inWindow = window.start <= now && now < window.end
                let mayStart = state.enabled && authorized && inWindow && !record.completed
                    && !(record.liftReason?.blocksReactivation ?? false)
                if mayStart, shields.apply(slot: slot, selectionData: state.selectionData, mode: state.mode) {
                    record.active = true
                    record.activatedAt = now
                    record.expiresAt = window.end
                    record.liftReason = nil
                    record.liftedAt = nil
                    changed = true
                } else {
                    shields.clear(slot: slot)
                    if state.enabled, existing != nil, now >= window.end, !record.completed, record.liftReason == nil {
                        record.liftReason = .expired
                        record.liftedAt = now
                        changed = true
                    }
                }
                if record != (existing ?? SlotRecord(slot: slot, day: today)) {
                    state.setRecord(record)
                }
            }

            let active = SessionSlot.allCases.filter { state.record($0, today)?.active == true }
            return ReconcileOutcome(activeSlots: active, changed: changed)
        }
    }

    // MARK: Read-only

    func activeSlots(now: Date) -> [SessionSlot] {
        let state = store.load()
        let today = LocalDay(date: now, calendar: calendar)
        return SessionSlot.allCases.filter { state.record($0, today)?.active == true }
    }

    func record(slot: SessionSlot, day: LocalDay) -> SlotRecord? {
        store.load().record(slot, day)
    }
}

import XCTest
import LearningPrimitives
@testable import Quinze

/// Records the ManagedSettings calls instead of touching the system.
final class FakeShields: ShieldControlling {
    var applyResult = true
    private(set) var shielded: Set<SessionSlot> = []
    private(set) var applyCalls = 0

    func apply(slot: SessionSlot, selectionData: Data?, mode: StoredMode) -> Bool {
        applyCalls += 1
        guard applyResult, selectionData != nil else { return false }
        shielded.insert(slot)
        return true
    }

    func clear(slot: SessionSlot) {
        shielded.remove(slot)
    }

    func preset(_ slots: Set<SessionSlot>) { shielded = slots }
}

/// A deterministic world: UTC calendar, 2026-10-14, default schedule (9:00 / 14:00 / 20:00, 120 min window).
final class SlotFixture {
    let store: SharedStateStore
    let shields: FakeShields
    let calendar: Calendar
    let day: LocalDay
    let engine: SlotEngine

    init(schedule: DailySchedule = .default, enabled: Bool = true, selection: Data? = Data([1])) {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let localStore = SharedStateStore(suiteName: "quinze.tests.\(UUID().uuidString)", lockURL: nil)
        let fake = FakeShields()
        calendar = utc
        day = LocalDay(year: 2026, month: 10, day: 14)
        store = localStore
        shields = fake
        engine = SlotEngine(store: localStore, shields: fake, calendar: utc)
        localStore.update { state in
            state.enabled = enabled
            state.selectionData = selection
            state.schedule = schedule
        }
    }

    deinit { store.reset() }

    func at(_ hour: Int, _ minute: Int = 0) -> Date {
        day.date(at: TimeOfDay(hour: hour, minute: minute), calendar: calendar) ?? Date(timeIntervalSince1970: 0)
    }

    func record(_ slot: SessionSlot) -> SlotRecord? { engine.record(slot: slot, day: day) }
}

final class SlotEngineTests: XCTestCase {
    // MARK: Monitor

    func testIntervalStartShieldsTheSlotAndRecordsTheSafetyDeadline() {
        let f = SlotFixture()
        XCTAssertTrue(f.engine.intervalDidStart(slot: .afternoon, now: f.at(14)))
        XCTAssertEqual(f.shields.shielded, [.afternoon])
        let record = f.record(.afternoon)
        XCTAssertEqual(record?.active, true)
        XCTAssertEqual(record?.activatedAt, f.at(14))
        XCTAssertEqual(record?.expiresAt, f.at(16))
        XCTAssertNil(record?.liftReason)
    }

    func testIntervalStartDoesNotShieldAnAlreadyCompletedSlot() {
        let f = SlotFixture()
        XCTAssertFalse(f.engine.markCompleted(slot: .afternoon, day: f.day, now: f.at(13, 30)))
        XCTAssertFalse(f.engine.intervalDidStart(slot: .afternoon, now: f.at(14)))
        XCTAssertTrue(f.shields.shielded.isEmpty)
        XCTAssertEqual(f.record(.afternoon)?.completed, true)
        XCTAssertEqual(f.record(.afternoon)?.active, false)
    }

    func testIntervalStartDoesNothingWhenTheFeatureIsOff() {
        let f = SlotFixture(enabled: false)
        XCTAssertFalse(f.engine.intervalDidStart(slot: .morning, now: f.at(9)))
        XCTAssertTrue(f.shields.shielded.isEmpty)
        XCTAssertNil(f.record(.morning))
    }

    func testIntervalStartShieldsNothingWithoutAUsableSelection() {
        let f = SlotFixture(selection: nil)
        XCTAssertFalse(f.engine.intervalDidStart(slot: .morning, now: f.at(9)))
        XCTAssertTrue(f.shields.shielded.isEmpty)
        XCTAssertEqual(f.record(.morning)?.active, false)
    }

    func testLateIntervalStartAfterTheWindowIsRecordedAsExpired() {
        let f = SlotFixture()
        XCTAssertFalse(f.engine.intervalDidStart(slot: .morning, now: f.at(11, 5)))
        XCTAssertTrue(f.shields.shielded.isEmpty)
        XCTAssertEqual(f.record(.morning)?.liftReason, .expired)
    }

    func testDuplicateIntervalStartKeepsTheFirstActivationTime() {
        let f = SlotFixture()
        f.engine.intervalDidStart(slot: .afternoon, now: f.at(14))
        f.engine.intervalDidStart(slot: .afternoon, now: f.at(14, 20))
        XCTAssertEqual(f.record(.afternoon)?.activatedAt, f.at(14))
        XCTAssertEqual(f.shields.shielded, [.afternoon])
    }

    func testIntervalEndAlwaysClearsAndMarksExpiredWhenNotCompleted() {
        let f = SlotFixture()
        f.engine.intervalDidStart(slot: .afternoon, now: f.at(14))
        f.engine.intervalDidEnd(slot: .afternoon, now: f.at(16))
        XCTAssertTrue(f.shields.shielded.isEmpty)
        XCTAssertEqual(f.record(.afternoon)?.active, false)
        XCTAssertEqual(f.record(.afternoon)?.liftReason, .expired)
    }

    func testIntervalEndKeepsTheCompletionReason() {
        let f = SlotFixture()
        f.engine.intervalDidStart(slot: .afternoon, now: f.at(14))
        XCTAssertTrue(f.engine.markCompleted(slot: .afternoon, day: f.day, now: f.at(14, 30)))
        f.engine.intervalDidEnd(slot: .afternoon, now: f.at(16))
        XCTAssertEqual(f.record(.afternoon)?.liftReason, .completed)
        XCTAssertTrue(f.shields.shielded.isEmpty)
    }

    func testIntervalEndWithoutAStartStillClearsTheStore() {
        let f = SlotFixture()
        f.shields.preset([.evening])
        f.engine.intervalDidEnd(slot: .evening, now: f.at(22))
        XCTAssertTrue(f.shields.shielded.isEmpty)
    }

    // MARK: Independence of the slots

    func testCompletingOneSlotKeepsTheOverlappingSlotShielded() {
        var schedule = DailySchedule.default
        schedule.afternoon = TimeOfDay(hour: 14, minute: 0)
        schedule.evening = TimeOfDay(hour: 15, minute: 0)
        let f = SlotFixture(schedule: schedule)
        f.engine.intervalDidStart(slot: .afternoon, now: f.at(14))
        f.engine.intervalDidStart(slot: .evening, now: f.at(15))
        XCTAssertEqual(f.shields.shielded, [.afternoon, .evening])

        f.engine.markCompleted(slot: .afternoon, day: f.day, now: f.at(15, 10))
        XCTAssertEqual(f.shields.shielded, [.evening])
        XCTAssertEqual(f.engine.activeSlots(now: f.at(15, 10)), [.evening])
    }

    // MARK: Emergency

    func testEmergencyUnlockLiftsEverythingLogsAndSticksForTheDay() {
        var schedule = DailySchedule.default
        schedule.evening = TimeOfDay(hour: 15, minute: 0)
        let f = SlotFixture(schedule: schedule)
        f.engine.intervalDidStart(slot: .afternoon, now: f.at(14))
        f.engine.intervalDidStart(slot: .evening, now: f.at(15))

        let lifted = f.engine.emergencyUnlock(reason: "test", now: f.at(15, 5))
        XCTAssertEqual(Set(lifted), [.afternoon, .evening])
        XCTAssertTrue(f.shields.shielded.isEmpty)
        XCTAssertEqual(f.record(.afternoon)?.liftReason, .emergency)
        XCTAssertEqual(f.store.load().emergencyLog.count, 1)
        XCTAssertEqual(f.store.load().emergencyLog.first?.reason, "test")

        // Neither a reconcile nor a monitor restart brings the shield back.
        f.engine.reconcile(now: f.at(15, 30), authorized: true)
        f.engine.intervalDidStart(slot: .afternoon, now: f.at(15, 31))
        XCTAssertTrue(f.shields.shielded.isEmpty)
    }

    func testEmergencyInsideAWindowBeforeTheMonitorStartedPreventsTheShield() {
        let f = SlotFixture()
        let lifted = f.engine.emergencyUnlock(reason: "early", now: f.at(14, 10))
        XCTAssertEqual(lifted, [.afternoon])
        XCTAssertFalse(f.engine.intervalDidStart(slot: .afternoon, now: f.at(14, 11)))
        XCTAssertTrue(f.shields.shielded.isEmpty)
    }

    // MARK: Reconcile

    func testReconcileLiftsAShieldPastItsDeadline() {
        let f = SlotFixture()
        f.engine.intervalDidStart(slot: .afternoon, now: f.at(14))
        // The intervalDidEnd callback never ran (crash, reboot): the app recovers.
        let outcome = f.engine.reconcile(now: f.at(16, 5), authorized: true)
        XCTAssertTrue(outcome.activeSlots.isEmpty)
        XCTAssertTrue(outcome.changed)
        XCTAssertTrue(f.shields.shielded.isEmpty)
        XCTAssertEqual(f.record(.afternoon)?.liftReason, .expired)
    }

    func testReconcileAppliesTheShieldInsideAWindowWhenTheMonitorDidNot() {
        let f = SlotFixture()
        let outcome = f.engine.reconcile(now: f.at(14, 30), authorized: true)
        XCTAssertEqual(outcome.activeSlots, [.afternoon])
        XCTAssertEqual(f.shields.shielded, [.afternoon])
        XCTAssertEqual(f.record(.afternoon)?.expiresAt, f.at(16))
    }

    func testReconcileOutsideAnyWindowShieldsNothing() {
        let f = SlotFixture()
        let outcome = f.engine.reconcile(now: f.at(12), authorized: true)
        XCTAssertTrue(outcome.activeSlots.isEmpty)
        XCTAssertTrue(f.shields.shielded.isEmpty)
    }

    func testReconcileRespectsACompletedSlot() {
        let f = SlotFixture()
        f.engine.markCompleted(slot: .afternoon, day: f.day, now: f.at(13))
        f.engine.reconcile(now: f.at(14, 30), authorized: true)
        XCTAssertTrue(f.shields.shielded.isEmpty)
    }

    func testReconcileDoesNotShieldAndLiftsWhenAuthorizationIsLost() {
        let f = SlotFixture()
        XCTAssertTrue(f.engine.reconcile(now: f.at(14, 30), authorized: false).activeSlots.isEmpty)
        XCTAssertTrue(f.shields.shielded.isEmpty)

        f.engine.reconcile(now: f.at(14, 31), authorized: true)
        XCTAssertEqual(f.shields.shielded, [.afternoon])
        f.engine.reconcile(now: f.at(14, 32), authorized: false)
        XCTAssertTrue(f.shields.shielded.isEmpty)
        XCTAssertEqual(f.record(.afternoon)?.liftReason, .authorizationLost)

        // Authorization is back inside the same window: the shield returns (not a final lift reason).
        f.engine.reconcile(now: f.at(14, 40), authorized: true)
        XCTAssertEqual(f.shields.shielded, [.afternoon])
    }

    func testReconcileClearsAStoreThatHasNoActiveRecord() {
        let f = SlotFixture()
        f.shields.preset([.morning])
        f.engine.reconcile(now: f.at(12), authorized: true)
        XCTAssertTrue(f.shields.shielded.isEmpty)
    }

    func testReconcileLiftsAnActiveRecordOfAnotherDay() {
        let f = SlotFixture()
        f.store.update { state in
            var old = SlotRecord(slot: .morning, day: f.day.adding(days: -1, calendar: f.calendar))
            old.active = true
            old.expiresAt = f.at(23)   // still in the future, but the record belongs to yesterday
            state.setRecord(old)
        }
        f.shields.preset([.morning])
        f.engine.reconcile(now: f.at(8), authorized: true)
        XCTAssertTrue(f.shields.shielded.isEmpty)
        XCTAssertTrue(f.engine.activeSlots(now: f.at(8)).isEmpty)
    }

    func testReconcileIsIdempotent() {
        let f = SlotFixture()
        let first = f.engine.reconcile(now: f.at(14, 30), authorized: true)
        let second = f.engine.reconcile(now: f.at(14, 31), authorized: true)
        XCTAssertEqual(first.activeSlots, second.activeSlots)
        XCTAssertFalse(second.changed)
        XCTAssertEqual(f.record(.afternoon)?.activatedAt, f.at(14, 30))
    }

    // MARK: Settings changes

    func testDisablingTheFeatureClearsEveryShield() {
        let f = SlotFixture()
        f.engine.intervalDidStart(slot: .afternoon, now: f.at(14))
        f.engine.setEnabled(false, now: f.at(14, 10))
        XCTAssertTrue(f.shields.shielded.isEmpty)
        XCTAssertEqual(f.record(.afternoon)?.liftReason, .disabled)
        // Switching back on inside the window shields again.
        f.engine.setEnabled(true, now: f.at(14, 20))
        f.engine.reconcile(now: f.at(14, 20), authorized: true)
        XCTAssertEqual(f.shields.shielded, [.afternoon])
    }

    func testMovingTheScheduleReopensAnExpiredSlot() {
        let f = SlotFixture()
        f.engine.intervalDidStart(slot: .afternoon, now: f.at(14))
        f.engine.intervalDidEnd(slot: .afternoon, now: f.at(16))
        XCTAssertEqual(f.record(.afternoon)?.liftReason, .expired)

        var moved = DailySchedule.default
        moved.afternoon = TimeOfDay(hour: 16, minute: 30)
        f.engine.updateSchedule(moved, now: f.at(16, 10))
        XCTAssertNil(f.record(.afternoon)?.liftReason)
        f.engine.reconcile(now: f.at(16, 45), authorized: true)
        XCTAssertEqual(f.shields.shielded, [.afternoon])
        XCTAssertEqual(f.record(.afternoon)?.expiresAt, f.at(18, 30))
    }

    func testUpdatingTheSelectionReappliesToActiveSlotsOnly() {
        let f = SlotFixture()
        f.engine.intervalDidStart(slot: .afternoon, now: f.at(14))
        let calls = f.shields.applyCalls
        f.engine.updateSelection(data: Data([2]), mode: .allExceptAllowed, now: f.at(14, 5))
        XCTAssertEqual(f.shields.applyCalls, calls + 1)
        XCTAssertEqual(f.store.load().mode, .allExceptAllowed)

        // An empty selection cannot be shielded: the slot is lifted rather than left half-configured.
        f.engine.updateSelection(data: nil, mode: .selectedApps, now: f.at(14, 6))
        XCTAssertTrue(f.shields.shielded.isEmpty)
        XCTAssertEqual(f.record(.afternoon)?.active, false)
    }
}

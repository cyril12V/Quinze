import XCTest
import LearningCore
@testable import Quinze

/// Slot status computation: upcoming → available (from slot − early start) → completed / inProgress / missed.
final class SlotLogicTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
        return c
    }()

    private let day = LocalDay(year: 2026, month: 10, day: 14)
    private let schedule = DailySchedule(morning: TimeOfDay(hour: 9, minute: 0), afternoon: TimeOfDay(hour: 14, minute: 0),
                                         evening: TimeOfDay(hour: 20, minute: 0), timeZoneIdentifier: "Europe/Paris",
                                         enabled: true, safetyWindowMinutes: 120, earlyStartMinutes: 60)

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        SlotLogic.instant(day: day, time: TimeOfDay(hour: hour, minute: minute), calendar: calendar)
    }

    private func session(_ slot: SessionSlot?, _ status: SessionStatus, day: LocalDay? = nil,
                         type: SessionType = .learning) -> SessionRecord {
        SessionRecord(id: UUID(), type: type, slot: slot, day: day ?? self.day, status: status, updatedAt: Date(timeIntervalSince1970: 1))
    }

    private func status(_ slot: SessionSlot, now: Date, sessions: [SessionRecord] = []) -> SlotStatus {
        SlotLogic.status(slot: slot, day: day, now: now, schedule: schedule, sessions: sessions, calendar: calendar)
    }

    func testBeforeEarlyStartIsUpcoming() {
        XCTAssertEqual(status(.morning, now: at(7, 59)), .upcoming)
        XCTAssertEqual(status(.afternoon, now: at(9, 0)), .upcoming)
        XCTAssertEqual(status(.evening, now: at(12, 0)), .upcoming)
    }

    func testEarlyStartWindowMakesSlotAvailable() {
        XCTAssertEqual(status(.morning, now: at(8, 0)), .available)
        XCTAssertEqual(status(.morning, now: at(8, 45)), .available)
        XCTAssertEqual(status(.afternoon, now: at(13, 0)), .available)
    }

    func testAvailableUntilEndOfSafetyWindowThenMissed() {
        XCTAssertEqual(status(.morning, now: at(9, 0)), .available)
        XCTAssertEqual(status(.morning, now: at(11, 0)), .available)
        XCTAssertEqual(status(.morning, now: at(11, 1)), .missed)
        XCTAssertEqual(status(.morning, now: at(23, 30)), .missed)
        XCTAssertEqual(status(.afternoon, now: at(11, 30)), .upcoming)
    }

    func testCompletedAndInProgressWinOverTime() {
        XCTAssertEqual(status(.morning, now: at(7, 0), sessions: [session(.morning, .completed)]), .completed)
        XCTAssertEqual(status(.morning, now: at(18, 0), sessions: [session(.morning, .completed)]), .completed)
        XCTAssertEqual(status(.morning, now: at(18, 0), sessions: [session(.morning, .inProgress)]), .inProgress)
        XCTAssertEqual(status(.morning, now: at(10, 0), sessions: [session(.morning, .completed), session(.morning, .inProgress)]), .completed)
    }

    func testOtherSlotsOtherDaysAndStaleRowsAreIgnored() {
        let yesterday = day.adding(days: -1, calendar: calendar)
        XCTAssertEqual(status(.morning, now: at(10, 0), sessions: [session(.afternoon, .completed)]), .available)
        XCTAssertEqual(status(.morning, now: at(10, 0), sessions: [session(.morning, .completed, day: yesterday)]), .available)
        XCTAssertEqual(status(.morning, now: at(10, 0), sessions: [session(.morning, .expired)]), .available)
        XCTAssertEqual(status(.morning, now: at(10, 0), sessions: [session(nil, .completed, type: .extra)]), .available)
    }

    func testEarlyStartCanBeDisabled() {
        var strict = schedule
        strict.earlyStartMinutes = 0
        XCTAssertEqual(SlotLogic.status(slot: .morning, day: day, now: at(8, 59), schedule: strict, sessions: [], calendar: calendar), .upcoming)
        XCTAssertEqual(SlotLogic.status(slot: .morning, day: day, now: at(9, 0), schedule: strict, sessions: [], calendar: calendar), .available)
    }

    func testLateEveningWindowIsClampedBeforeMidnight() {
        var late = schedule
        late.evening = TimeOfDay(hour: 23, minute: 0)
        // 23:00 + 120 min would cross midnight: the window is clamped to 23:59.
        XCTAssertEqual(SlotLogic.status(slot: .evening, day: day, now: at(23, 58), schedule: late, sessions: [], calendar: calendar), .available)
    }

    func testSlotStatesCoverTheThreeSlotsInOrder() {
        let running = session(.morning, .inProgress)
        let states = SlotLogic.slotStates(day: day, now: at(10, 0), schedule: schedule,
                                          sessions: [running, session(.afternoon, .completed)],
                                          activeRestrictions: [.morning, .afternoon], calendar: calendar)
        XCTAssertEqual(states.map(\.slot), [.morning, .afternoon, .evening])
        XCTAssertEqual(states.map(\.status), [.inProgress, .completed, .upcoming])
        XCTAssertEqual(states[0].sessionId, running.id)
        XCTAssertEqual(states[0].scheduledTime, TimeOfDay(hour: 9, minute: 0))
        XCTAssertTrue(states[0].restrictionActive)
        XCTAssertFalse(states[1].restrictionActive, "a completed slot has no active shield")
        XCTAssertFalse(states[2].restrictionActive)
        XCTAssertNil(states[2].sessionId)
    }

    func testTodayStateFeaturedSlotAndCounts() {
        let states = SlotLogic.slotStates(day: day, now: at(10, 0), schedule: schedule, sessions: [session(.morning, .completed)],
                                          activeRestrictions: [], calendar: calendar)
        let today = TodayState(day: day, slots: states, streakDays: 3, dueReviewCount: 0, assessmentDue: false)
        XCTAssertEqual(today.completedCount, 1)
        XCTAssertEqual(today.featuredSlot?.slot, .afternoon)
    }

    func testCompletedDaysIgnoreDiagnosticAndUnfinishedSessions() {
        let yesterday = day.adding(days: -1, calendar: calendar)
        let days = SlotLogic.completedDays(sessions: [
            session(.morning, .completed), session(nil, .completed, day: yesterday, type: .diagnostic),
            session(.afternoon, .inProgress, day: yesterday), session(nil, .completed, day: day.adding(days: -2, calendar: calendar), type: .extra)
        ])
        XCTAssertEqual(days, [day, day.adding(days: -2, calendar: calendar)])
    }

    func testPlannerSeedIsStablePerSessionId() throws {
        let id = try XCTUnwrap(UUID(uuidString: "01020304-0506-0708-090A-0B0C0D0E0F10"))
        XCTAssertEqual(id.planSeed, 0x0102_0304_0506_0708)
        XCTAssertEqual(id.planSeed, id.planSeed)
    }
}

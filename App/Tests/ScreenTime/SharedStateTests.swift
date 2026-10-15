import XCTest
import LearningPrimitives
@testable import Quinze

final class SharedStateTests: XCTestCase {
    private func makeStore() -> SharedStateStore {
        SharedStateStore(suiteName: "quinze.tests.\(UUID().uuidString)", lockURL: nil)
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    // MARK: Codable

    func testStateSurvivesAJSONRoundTrip() throws {
        var state = SharedState()
        state.enabled = true
        state.mode = .allExceptAllowed
        state.selectionData = Data([1, 2, 3])
        state.schedule = .default
        var record = SlotRecord(slot: .morning, day: LocalDay(year: 2026, month: 10, day: 14))
        record.active = true
        record.activatedAt = Date(timeIntervalSince1970: 1_000)
        record.liftReason = .emergency
        state.setRecord(record)
        state.appendEmergency(EmergencyEvent(date: Date(timeIntervalSince1970: 2_000), reason: "x", slots: [.morning]))

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(SharedState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    func testDecodingToleratesMissingAndUnknownKeys() throws {
        let json = #"{"version": 99, "enabled": true, "someFutureField": {"a": 1}}"#
        let state = try JSONDecoder().decode(SharedState.self, from: Data(json.utf8))
        XCTAssertTrue(state.enabled)
        XCTAssertEqual(state.version, 99)
        XCTAssertEqual(state.mode, .selectedApps)
        XCTAssertTrue(state.records.isEmpty)
        XCTAssertNil(state.schedule)
    }

    func testWindowsFallBackToTheDefaultScheduleWhenNoCopyIsStored() {
        let state = SharedState()
        let window = state.window(for: .afternoon)
        XCTAssertEqual(window.start, TimeOfDay(hour: 14, minute: 0))
        XCTAssertEqual(window.end, TimeOfDay(hour: 16, minute: 0))
    }

    // MARK: Store

    func testUpdateIsVisibleToAnotherInstanceOfTheSameSuite() {
        let suite = "quinze.tests.\(UUID().uuidString)"
        let writer = SharedStateStore(suiteName: suite, lockURL: nil)
        let reader = SharedStateStore(suiteName: suite, lockURL: nil)
        defer { writer.reset() }
        writer.update { $0.enabled = true }
        XCTAssertTrue(reader.load().enabled)
        reader.update { $0.enabled = false }
        XCTAssertFalse(writer.load().enabled)
    }

    func testUpdateReturnsTheClosureResultAndAppliesEveryMutation() {
        let store = makeStore()
        defer { store.reset() }
        let count = store.update { state -> Int in
            state.enabled = true
            state.appendEmergency(EmergencyEvent(date: Date(), reason: "a", slots: []))
            return state.emergencyLog.count
        }
        XCTAssertEqual(count, 1)
        XCTAssertEqual(store.load().emergencyLog.count, 1)
    }

    func testFileLockSerialisesConcurrentWriters() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("quinze-lock-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SharedStateStore(suiteName: "quinze.tests.\(UUID().uuidString)",
                                     lockURL: directory.appendingPathComponent("state.lock"))
        defer { store.reset() }

        DispatchQueue.concurrentPerform(iterations: 40) { _ in
            store.update { state in
                state.appendEmergency(EmergencyEvent(date: Date(), reason: "n", slots: []))
            }
        }
        XCTAssertEqual(store.load().emergencyLog.count, 40)
    }

    func testEmergencyLogIsCapped() {
        var state = SharedState()
        for index in 0..<(SharedState.maxEmergencyEvents + 10) {
            state.appendEmergency(EmergencyEvent(date: Date(timeIntervalSince1970: Double(index)), reason: "\(index)", slots: []))
        }
        XCTAssertEqual(state.emergencyLog.count, SharedState.maxEmergencyEvents)
        XCTAssertEqual(state.emergencyLog.last?.reason, "\(SharedState.maxEmergencyEvents + 9)")
    }

    func testPruneDropsOldInactiveRecordsButKeepsActiveOnes() {
        var state = SharedState()
        let today = LocalDay(year: 2026, month: 10, day: 14)
        let old = today.adding(days: -10, calendar: utc)
        var oldInactive = SlotRecord(slot: .morning, day: old)
        oldInactive.completed = true
        var oldActive = SlotRecord(slot: .afternoon, day: old)
        oldActive.active = true
        state.setRecord(oldInactive)
        state.setRecord(oldActive)
        state.setRecord(SlotRecord(slot: .evening, day: today))

        state.prune(today: today, calendar: utc)
        XCTAssertNil(state.record(.morning, old))
        XCTAssertNotNil(state.record(.afternoon, old))
        XCTAssertNotNil(state.record(.evening, today))
    }

    // MARK: Names and identifiers

    func testActivityNamesRoundTrip() {
        for slot in SessionSlot.allCases {
            let name = ScreenTimeNames.activityRawName(for: slot)
            XCTAssertTrue(name.hasPrefix("quinze.slot."))
            XCTAssertEqual(ScreenTimeNames.slot(fromActivityRawName: name), slot)
        }
        XCTAssertEqual(ScreenTimeNames.activityRawName(for: .morning), "quinze.slot.morning")
        XCTAssertNil(ScreenTimeNames.slot(fromActivityRawName: "quinze.slot.night"))
        XCTAssertNil(ScreenTimeNames.slot(fromActivityRawName: "other.morning"))
    }

    func testEachSlotHasItsOwnStoreName() {
        let names = Set(SessionSlot.allCases.map { ScreenTimeNames.storeRawName(for: $0) })
        XCTAssertEqual(names.count, SessionSlot.allCases.count)
    }

    func testAppGroupIdentifierResolution() {
        XCTAssertEqual(AppGroup.resolve(infoValue: nil), AppGroup.fallbackIdentifier)
        XCTAssertEqual(AppGroup.resolve(infoValue: ""), AppGroup.fallbackIdentifier)
        XCTAssertEqual(AppGroup.resolve(infoValue: "$(BUNDLE_ID_PREFIX)"), AppGroup.fallbackIdentifier)
        XCTAssertEqual(AppGroup.resolve(infoValue: "group.$(BUNDLE_ID_PREFIX).quinze"), AppGroup.fallbackIdentifier)
        XCTAssertEqual(AppGroup.resolve(infoValue: "not-a-group"), AppGroup.fallbackIdentifier)
        XCTAssertEqual(AppGroup.resolve(infoValue: " group.fr.example.quinze \n"), "group.fr.example.quinze")
        XCTAssertTrue(AppGroup.identifier.hasPrefix("group."))
    }

    func testRestrictionModeMapsToTheStoredMode() {
        for mode in RestrictionMode.allCases {
            XCTAssertEqual(RestrictionMode(mode.stored), mode)
        }
        XCTAssertEqual(StoredMode.allCases.count, RestrictionMode.allCases.count)
    }

    func testOnlyFinalLiftReasonsBlockReactivation() {
        XCTAssertTrue(LiftReason.completed.blocksReactivation)
        XCTAssertTrue(LiftReason.emergency.blocksReactivation)
        XCTAssertTrue(LiftReason.expired.blocksReactivation)
        XCTAssertFalse(LiftReason.disabled.blocksReactivation)
        XCTAssertFalse(LiftReason.authorizationLost.blocksReactivation)
        XCTAssertFalse(LiftReason.stale.blocksReactivation)
    }
}

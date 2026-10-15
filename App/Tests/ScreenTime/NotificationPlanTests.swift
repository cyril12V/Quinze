import XCTest
import LearningPrimitives
@testable import Quinze

final class NotificationPlanTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private let today = LocalDay(year: 2026, month: 10, day: 14)

    private func date(_ day: LocalDay, _ hour: Int, _ minute: Int = 0) -> Date {
        day.date(at: TimeOfDay(hour: hour, minute: minute), calendar: utc) ?? Date(timeIntervalSince1970: 0)
    }

    private func plan(preferences: NotificationPreferences = .default,
                      schedule: DailySchedule = .default,
                      completed: [LocalDay: Set<SessionSlot>] = [:],
                      dueReviewCount: Int = 0,
                      now: Date? = nil) -> [PlannedNotification] {
        NotificationScheduler.plan(schedule: schedule, preferences: preferences, completed: completed,
                                   dueReviewCount: dueReviewCount, now: now ?? date(today, 8), calendar: utc)
    }

    func testDefaultPlanCoversSevenDaysBelowTheSystemLimit() {
        let items = plan()
        // 7 days x 3 slots x (lesson + unfinished reminder)
        XCTAssertEqual(items.count, 42)
        XCTAssertLessThan(items.count, 64)
        XCTAssertEqual(Set(items.map { $0.identifier }).count, items.count, "identifiers must be unique")
        XCTAssertEqual(items.map { $0.fireDate }, items.map { $0.fireDate }.sorted())
        XCTAssertEqual(items.last?.day, today.adding(days: 6, calendar: utc))
    }

    func testLessonReminderTextAndTime() {
        let items = plan()
        let morning = items.first { $0.kind == .lesson && $0.slot == .morning && $0.day == today }
        XCTAssertEqual(morning?.fireDate, date(today, 9))
        XCTAssertEqual(morning?.body, "Ta leçon d'anglais est prête. Cinq minutes pour progresser.")
        XCTAssertEqual(morning?.identifier, "quinze.n.lesson.2026-10-14.morning")
    }

    func testUnfinishedReminderUsesTheConfiguredDelay() {
        var preferences = NotificationPreferences.default
        preferences.unfinishedReminderDelayMinutes = 45
        let items = plan(preferences: preferences)
        let late = items.first { $0.kind == .unfinished && $0.slot == .afternoon && $0.day == today }
        XCTAssertEqual(late?.fireDate, date(today, 14, 45))
    }

    func testCompletedSlotsAreSkipped() {
        let items = plan(completed: [today: [.morning, .afternoon]])
        XCTAssertFalse(items.contains { $0.day == today && ($0.slot == .morning || $0.slot == .afternoon) })
        XCTAssertTrue(items.contains { $0.day == today && $0.slot == .evening })
        // Completing today never removes tomorrow's reminders.
        XCTAssertTrue(items.contains { $0.day == today.adding(days: 1, calendar: utc) && $0.slot == .morning })
    }

    func testPastLessonIsSkippedButItsUnfinishedReminderStillFires() {
        let items = plan(now: date(today, 9, 10))
        XCTAssertFalse(items.contains { $0.kind == .lesson && $0.slot == .morning && $0.day == today })
        XCTAssertTrue(items.contains { $0.kind == .unfinished && $0.slot == .morning && $0.day == today })
    }

    func testNothingIsScheduledInThePast() {
        let now = date(today, 21)
        let items = plan(now: now)
        XCTAssertTrue(items.allSatisfy { $0.fireDate > now })
    }

    func testEveningMentionsDueReviews() {
        let items = plan(dueReviewCount: 3)
        let tonight = items.first { $0.kind == .lesson && $0.slot == .evening && $0.day == today }
        XCTAssertEqual(tonight?.body.contains("3 révisions"), true)
        let tomorrow = items.first { $0.kind == .lesson && $0.slot == .evening && $0.day == today.adding(days: 1, calendar: utc) }
        XCTAssertEqual(tomorrow?.body.contains("révisions"), true)
        // Other slots keep the standard text.
        let morning = items.first { $0.kind == .lesson && $0.slot == .morning }
        XCTAssertEqual(morning?.body, "Ta leçon d'anglais est prête. Cinq minutes pour progresser.")
    }

    func testSingularReviewAndOptOut() {
        let single = plan(dueReviewCount: 1).first { $0.kind == .lesson && $0.slot == .evening && $0.day == today }
        XCTAssertEqual(single?.body.contains("1 révision t'attend"), true)

        var preferences = NotificationPreferences.default
        preferences.reviewAvailable = false
        let off = plan(preferences: preferences, dueReviewCount: 5).first { $0.kind == .lesson && $0.slot == .evening }
        XCTAssertEqual(off?.body, "Ta leçon d'anglais est prête. Cinq minutes pour progresser.")
    }

    func testPreferencesSwitchesAreRespected() {
        var preferences = NotificationPreferences.default
        preferences.lessonReminders = false
        XCTAssertTrue(plan(preferences: preferences).allSatisfy { $0.kind == .unfinished })

        preferences = .default
        preferences.unfinishedReminder = false
        XCTAssertTrue(plan(preferences: preferences).allSatisfy { $0.kind == .lesson })

        preferences.lessonReminders = false
        XCTAssertTrue(plan(preferences: preferences).isEmpty)
    }

    func testDisabledScheduleProducesNoNotification() {
        var schedule = DailySchedule.default
        schedule.enabled = false
        XCTAssertTrue(plan(schedule: schedule).isEmpty)
    }

    func testUnfinishedReminderNeverCrossesMidnight() {
        var schedule = DailySchedule.default
        schedule.evening = TimeOfDay(hour: 23, minute: 50)
        var preferences = NotificationPreferences.default
        preferences.unfinishedReminderDelayMinutes = 30
        let items = plan(preferences: preferences, schedule: schedule)
        XCTAssertFalse(items.contains { $0.kind == .unfinished && $0.slot == .evening })
        XCTAssertTrue(items.contains { $0.kind == .lesson && $0.slot == .evening })
    }

    func testIdentifierFormat() {
        XCTAssertEqual(NotificationScheduler.identifier(.unfinished, day: today, slot: .evening),
                       "quinze.n.unfinished.2026-10-14.evening")
    }
}

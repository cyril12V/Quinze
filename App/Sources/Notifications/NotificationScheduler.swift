import Foundation
import Observation
import UserNotifications
import OSLog
import LearningPrimitives

// CONTRACT FILE — owned by the "Screen Time" workstream (A).
// Notifications are a reminder only: restrictions never depend on them (§16.3).

struct NotificationPreferences: Codable, Equatable, Sendable {
    /// "Ta leçon d'anglais est prête. Cinq minutes pour progresser." at each slot time.
    var lessonReminders: Bool = true
    /// Reminder if the slot's lesson is still not done after `unfinishedReminderDelayMinutes`.
    var unfinishedReminder: Bool = true
    var unfinishedReminderDelayMinutes: Int = 30
    /// Confirmation when a session is completed and restrictions are lifted (useful when the app is backgrounded).
    var completionConfirmation: Bool = false
    /// Mention due reviews in the evening reminder.
    var reviewAvailable: Bool = true
    /// Alert when Screen Time authorization is lost.
    var authorizationProblems: Bool = true

    static let `default` = NotificationPreferences()
}

/// One notification of the 7-day plan (pure data: the plan is unit-tested without UserNotifications).
struct PlannedNotification: Equatable, Sendable {
    enum Kind: String, Sendable { case lesson, unfinished }

    var identifier: String
    var kind: Kind
    var slot: SessionSlot
    var day: LocalDay
    var fireDate: Date
    var title: String
    var body: String
}

@MainActor
@Observable
final class NotificationScheduler {
    static let shared = NotificationScheduler()

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// Days planned ahead. 7 days x 3 slots x 2 reminders = 42 requests, below the system limit of 64.
    nonisolated static let horizonDays = 7
    nonisolated static let maxPendingRequests = 60

    nonisolated static let lessonPrefix = "quinze.n.lesson."
    nonisolated static let unfinishedPrefix = "quinze.n.unfinished."
    nonisolated static let completedPrefix = "quinze.n.completed."
    nonisolated static let authorizationProblemID = "quinze.n.authproblem"
    nonisolated private static let preferencesKey = "quinze.notificationPreferences"

    @ObservationIgnored private let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "fr.elmdigitalagency.quinze", category: "notifications")

    /// Last preferences passed to `reschedule` (used for alerts raised outside the settings screen).
    var lastKnownPreferences: NotificationPreferences {
        guard let data = UserDefaults.standard.data(forKey: Self.preferencesKey),
              let value = try? JSONDecoder().decode(NotificationPreferences.self, from: data) else {
            return .default
        }
        return value
    }

    private var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await Self.systemAuthorizationStatus()
    }

    /// Asks the system permission. Returns true when granted.
    func requestAuthorization() async -> Bool {
        let granted: Bool
        do {
            granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            log.error("Notification authorization failed: \(String(describing: error), privacy: .public)")
            granted = false
        }
        await refreshAuthorizationStatus()
        return granted
    }

    /// Rebuilds the pending notifications for the next 7 days.
    /// `completed` = slots already completed (by day), so their reminders are skipped.
    func reschedule(schedule: DailySchedule, preferences: NotificationPreferences,
                    completed: [LocalDay: Set<SessionSlot>], dueReviewCount: Int, now: Date) async {
        savePreferences(preferences)
        await refreshAuthorizationStatus()

        let pending = await Self.pendingRequestIdentifiers()
        let ours = pending.filter { $0.hasPrefix(Self.lessonPrefix) || $0.hasPrefix(Self.unfinishedPrefix) }
        if !ours.isEmpty { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ours) }
        guard isAuthorized else { return }

        let calendar = Calendar.autoupdatingCurrent
        let plan = Self.plan(schedule: schedule, preferences: preferences, completed: completed,
                             dueReviewCount: dueReviewCount, now: now, calendar: calendar)
        for item in plan {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.interruptionLevel = .active
            content.threadIdentifier = "quinze.lessons"
            content.userInfo = ["kind": item.kind.rawValue, "slot": item.slot.rawValue, "day": item.day.isoString]
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger)
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                log.error("Could not schedule a reminder: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Removes today's pending reminders for the slot and, if enabled, confirms completion.
    func sessionCompleted(slot: SessionSlot, day: LocalDay, restrictionsLifted: Bool,
                          preferences: NotificationPreferences) async {
        let center = UNUserNotificationCenter.current()
        let ids = [Self.identifier(.lesson, day: day, slot: slot), Self.identifier(.unfinished, day: day, slot: slot)]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)

        guard preferences.completionConfirmation else { return }
        await refreshAuthorizationStatus()
        guard isAuthorized else { return }
        let body = restrictionsLifted
            ? "Bravo, leçon terminée. Tes apps sont de nouveau disponibles."
            : "Bravo, leçon terminée. À tout à l'heure pour la suivante."
        await postImmediately(identifier: Self.completedPrefix + day.isoString + "." + slot.rawValue,
                              title: "Leçon terminée", body: body)
    }

    /// "Les restrictions ne fonctionnent plus : autorisation Temps d'écran retirée."
    func notifyAuthorizationProblem(preferences: NotificationPreferences) async {
        guard preferences.authorizationProblems else { return }
        await refreshAuthorizationStatus()
        guard isAuthorized else { return }
        await postImmediately(
            identifier: Self.authorizationProblemID,
            title: "Restrictions désactivées",
            body: "Les restrictions ne fonctionnent plus : autorisation Temps d'écran retirée. Ouvre Quinze pour la rétablir.")
    }

    // MARK: Plan (pure)

    nonisolated static func identifier(_ kind: PlannedNotification.Kind, day: LocalDay, slot: SessionSlot) -> String {
        let prefix = kind == .lesson ? lessonPrefix : unfinishedPrefix
        return prefix + day.isoString + "." + slot.rawValue
    }

    /// The reminders to schedule, sorted by date and capped below the system limit.
    nonisolated static func plan(schedule: DailySchedule, preferences: NotificationPreferences,
                                 completed: [LocalDay: Set<SessionSlot>], dueReviewCount: Int,
                                 now: Date, calendar: Calendar) -> [PlannedNotification] {
        guard schedule.enabled, preferences.lessonReminders || preferences.unfinishedReminder else { return [] }
        let today = LocalDay(date: now, calendar: calendar)
        let earliest = now.addingTimeInterval(5)
        let delay = min(max(preferences.unfinishedReminderDelayMinutes, 5), 180)
        var items: [PlannedNotification] = []

        for offset in 0..<horizonDays {
            let day = today.adding(days: offset, calendar: calendar)
            for slot in SessionSlot.allCases {
                if completed[day]?.contains(slot) == true { continue }
                guard let fire = day.date(at: schedule.time(for: slot), calendar: calendar) else { continue }

                if preferences.lessonReminders, fire > earliest {
                    items.append(PlannedNotification(
                        identifier: identifier(.lesson, day: day, slot: slot), kind: .lesson, slot: slot, day: day,
                        fireDate: fire, title: lessonTitle(slot),
                        body: lessonBody(slot: slot, isToday: offset == 0, preferences: preferences, dueReviewCount: dueReviewCount)))
                }
                if preferences.unfinishedReminder {
                    let late = fire.addingTimeInterval(TimeInterval(delay * 60))
                    if late > earliest, calendar.isDate(late, inSameDayAs: fire) {
                        items.append(PlannedNotification(
                            identifier: identifier(.unfinished, day: day, slot: slot), kind: .unfinished, slot: slot, day: day,
                            fireDate: late, title: "Ta leçon t'attend",
                            body: "Il reste une leçon d'anglais à faire. Cinq minutes suffisent."))
                    }
                }
            }
        }
        items.sort { $0.fireDate < $1.fireDate }
        return Array(items.prefix(maxPendingRequests))
    }

    nonisolated private static func lessonTitle(_ slot: SessionSlot) -> String {
        switch slot {
        case .morning: return "Leçon du matin"
        case .afternoon: return "Leçon de l'après-midi"
        case .evening: return "Leçon du soir"
        }
    }

    nonisolated private static func lessonBody(slot: SessionSlot, isToday: Bool,
                                               preferences: NotificationPreferences, dueReviewCount: Int) -> String {
        guard slot == .evening, preferences.reviewAvailable, dueReviewCount > 0 else {
            return "Ta leçon d'anglais est prête. Cinq minutes pour progresser."
        }
        if isToday {
            let reviews = dueReviewCount == 1 ? "1 révision t'attend" : "\(dueReviewCount) révisions t'attendent"
            return "Ta leçon du soir est prête, et \(reviews). Cinq minutes pour progresser."
        }
        return "Ta leçon du soir est prête, avec tes révisions. Cinq minutes pour progresser."
    }

    // MARK: Helpers

    // `UNNotificationSettings` and `UNNotificationRequest` are not Sendable: they cannot be returned from the
    // (nonisolated) UserNotifications async calls to the main actor, so only Sendable values leave these helpers.
    nonisolated private static func systemAuthorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    nonisolated private static func pendingRequestIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map { $0.identifier }
    }

    private func savePreferences(_ preferences: NotificationPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: Self.preferencesKey)
    }

    private func postImmediately(identifier: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "quinze.status"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            log.error("Could not post a notification: \(String(describing: error), privacy: .public)")
        }
    }
}

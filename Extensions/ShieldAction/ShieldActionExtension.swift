import ManagedSettings
import UserNotifications
import Foundation

/// Wraps the system completion handler so it can be called from an asynchronous continuation.
/// The handler is invoked exactly once by the code below.
private struct ResponseHandler: @unchecked Sendable {
    let call: (ShieldActionResponse) -> Void
}

/// Handles the two buttons of the shield.
///
/// - Primary « Compris »: closes the shield and posts a local notification « Ouvre Quinze pour faire ta
///   leçon » (a shield cannot open another app).
/// - Secondary « Déblocage d'urgence »: lifts every active slot, logs the event, closes the shield.
final class ShieldActionExtension: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, completionHandler: completionHandler)
    }

    private func respond(to action: ShieldAction, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            let handler = ResponseHandler(call: completionHandler)
            let request = Self.openQuinzeRequest()
            UNUserNotificationCenter.current().add(request) { _ in
                handler.call(.close)
            }
        case .secondaryButtonPressed:
            SlotEngine().emergencyUnlock(reason: "shield", now: Date())
            completionHandler(.close)
        @unknown default:
            completionHandler(.close)
        }
    }

    private static func openQuinzeRequest() -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Quinze"
        content.body = "Ouvre Quinze pour faire ta leçon"
        content.sound = .default
        content.interruptionLevel = .active
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        return UNNotificationRequest(
            identifier: ScreenTimeNames.shieldReminderNotificationID, content: content, trigger: trigger)
    }
}

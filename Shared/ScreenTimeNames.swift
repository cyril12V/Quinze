import Foundation
import LearningPrimitives

/// Names of the system objects used for each slot. One DeviceActivity and one named
/// ManagedSettingsStore per slot: completing A never lifts the shield of B.
enum ScreenTimeNames {
    static let activityPrefix = "quinze.slot."
    static let storePrefix = "quinze.store."

    static func activityRawName(for slot: SessionSlot) -> String {
        activityPrefix + slot.rawValue
    }

    static func slot(fromActivityRawName name: String) -> SessionSlot? {
        guard name.hasPrefix(activityPrefix) else { return nil }
        return SessionSlot(rawValue: String(name.dropFirst(activityPrefix.count)))
    }

    static func storeRawName(for slot: SessionSlot) -> String {
        storePrefix + slot.rawValue
    }

    /// Identifier of the local notification posted by the shield action extension.
    static let shieldReminderNotificationID = "quinze.shield.reminder"
}

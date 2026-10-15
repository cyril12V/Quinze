import DeviceActivity
import Foundation
import LearningPrimitives

/// DeviceActivity monitor extension. Runs in its own process (about 6 MB of memory): keep it tiny.
///
/// - `intervalDidStart`: when the feature is on and today's slot is not completed (an early-start
///   lesson pre-validates the slot), shield the slot's own store according to the saved mode and record
///   `active` with its safety deadline.
/// - `intervalDidEnd`: always clears the slot's store and records `expired` when the lesson was not
///   completed. A restriction can never outlive its window because of this callback.
final class QuinzeMonitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard let slot = ScreenTimeNames.slot(fromActivityRawName: activity.rawValue) else { return }
        SlotEngine().intervalDidStart(slot: slot, now: Date())
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard let slot = ScreenTimeNames.slot(fromActivityRawName: activity.rawValue) else { return }
        SlotEngine().intervalDidEnd(slot: slot, now: Date())
    }
}

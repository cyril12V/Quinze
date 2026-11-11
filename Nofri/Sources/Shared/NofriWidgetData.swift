import Foundation

/// What the app publishes for the lock-screen widgets (App Group defaults, JSON).
struct NofriWidgetData: Codable, Equatable, Sendable {
    /// « À retenir » sentences of the lessons already validated (the most recent last).
    var facts: [String] = []
    var streakDays: Int = 0
    var rankTitle: String = "Catéchumène"
    var points: Int = 0
    /// ISO day ("2026-11-11") on which a lesson was last completed.
    var lastStudyDay: String?
    var nextLessonTitle: String?

    static let key = "nofri.widget.v1"

    static func load() -> NofriWidgetData {
        guard let defaults = UserDefaults(suiteName: AppGroup.identifier),
              let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(NofriWidgetData.self, from: data) else { return NofriWidgetData() }
        return value
    }

    func save() {
        guard let defaults = UserDefaults(suiteName: AppGroup.identifier),
              let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    static func isoDay(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

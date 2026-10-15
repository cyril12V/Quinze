import Foundation

/// App Group shared by the app and the three Screen Time extensions.
///
/// The identifier comes from the `AppGroupIdentifier` Info.plist key (set from build settings in
/// `project.yml`, so it always matches the entitlement) with a hard-coded fallback.
enum AppGroup {
    static let infoPlistKey = "AppGroupIdentifier"
    static let fallbackIdentifier = "group.fr.elmdigitalagency.quinze"

    static var identifier: String {
        resolve(infoValue: Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String)
    }

    /// Pure resolution rule (unit-tested): ignores empty values and unexpanded `$(...)` placeholders.
    static func resolve(infoValue: String?) -> String {
        guard let value = infoValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.hasPrefix("group."), !value.contains("$(") else {
            return fallbackIdentifier
        }
        return value
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

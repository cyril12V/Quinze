import Foundation

/// Name of the app shown in texts shared by Quinze and Nofri (set by the `AppBrandName` Info.plist key).
enum AppBrand {
    static var name: String {
        (Bundle.main.object(forInfoDictionaryKey: "AppBrandName") as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Quinze"
    }

    /// Nofri calls its modules « chapitres ».
    static var moduleWord: String {
        #if NOFRI
        return "Chapitre"
        #else
        return "Module"
        #endif
    }
}

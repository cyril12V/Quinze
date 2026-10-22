import SwiftUI

extension AppearanceMode {
    /// nil = follow the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

extension String {
    /// The text contains Arabic letters (shown right to left, with a larger font).
    var containsArabic: Bool {
        unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) || (0x0750...0x077F).contains($0.value)
            || (0xFB50...0xFDFF).contains($0.value) || (0xFE70...0xFEFF).contains($0.value) }
    }
}

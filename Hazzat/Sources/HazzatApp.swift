import SwiftUI
import UIKit

@main
struct HazzatApp: App {
    @State private var library = Library()

    init() {
        Theme.styleNavigationBars()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(library)
                .tint(Palette.accent)
                .font(Typo.body(16))
        }
    }
}

/// Colours that follow the phone's light or dark mode, so text is always readable.
enum Palette {
    static let background = dynamic(light: 0xF7F3EC, dark: 0x121010)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x1D1918)
    static let cardPressed = dynamic(light: 0xF2ECE3, dark: 0x262120)
    static let ink = dynamic(light: 0x231A16, dark: 0xF3EDE6)
    static let muted = dynamic(light: 0x736660, dark: 0xA69A91)
    static let line = dynamic(light: 0xECE5DB, dark: 0x2C2624)
    static let accent = dynamic(light: 0x7A1F2B, dark: 0xE38D98)
    static let accentSoft = dynamic(light: 0xF5E9E7, dark: 0x351C20)
    static let hero = dynamic(light: 0x6F1C27, dark: 0x3E1219)
    static let heroDeep = dynamic(light: 0x4E111A, dark: 0x2A0B10)
    static let gold = Color(hex: 0xD8B15E)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: dynamicUIColor(light: light, dark: dark))
    }

    static func dynamicUIColor(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) }
    }
}

/// Cormorant Garamond for titles, Manrope for everything else. Both follow the text size of the phone.
enum Typo {
    static func title(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("CormorantGaramond-Bold", size: size, relativeTo: style)
    }

    static func titleSemi(_ size: CGFloat, relativeTo style: Font.TextStyle = .title2) -> Font {
        .custom("CormorantGaramond-SemiBold", size: size, relativeTo: style)
    }

    static func body(_ size: CGFloat, _ weight: Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight.fontName, size: size, relativeTo: style)
    }

    enum Weight {
        case regular, medium, semibold, bold

        var fontName: String {
            switch self {
            case .regular: "Manrope-Regular"
            case .medium: "Manrope-Medium"
            case .semibold: "Manrope-SemiBold"
            case .bold: "Manrope-Bold"
            }
        }
    }
}

enum Theme {
    @MainActor
    static func styleNavigationBars() {
        let ink = Palette.dynamicUIColor(light: 0x231A16, dark: 0xF3EDE6)
        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        for appearance in [standard, edge] {
            if let font = UIFont(name: "Manrope-SemiBold", size: 17) {
                appearance.titleTextAttributes = [.font: font, .foregroundColor: ink]
            }
            if let font = UIFont(name: "CormorantGaramond-Bold", size: 36) {
                appearance.largeTitleTextAttributes = [.font: font, .foregroundColor: ink]
            }
        }
        UINavigationBar.appearance().standardAppearance = standard
        UINavigationBar.appearance().compactAppearance = standard
        UINavigationBar.appearance().scrollEdgeAppearance = edge
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

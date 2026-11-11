import SwiftUI

// Design tokens — direction artistique « éditoriale pastel » (docs/design/direction-artistique.md).
// Light: off-white background, near-black ink, big pastel cards, black pill buttons, almost no shadow.
// Dark: same structure with deep neutrals and muted pastels (accessibility requirement §14.6).
// Every screen uses these tokens; the legacy names (accent, card, Font.callout…) are kept and remapped.

enum Theme {
    // MARK: Neutrals

    /// Page background (`--bg-main`), never pure white.
    #if NOFRI
    static let background = Color.dynamic(light: 0xF6EFE2, dark: 0x17120E)
    #else
    static let background = Color.dynamic(light: 0xF6F7FA, dark: 0x111214)
    #endif
    /// Cards, inputs, round buttons (`--surface`).
    #if NOFRI
    static let surface = Color.dynamic(light: 0xFFFBF3, dark: 0x241C16)
    #else
    static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x1C1D20)
    #endif
    /// Near-black ink (`--black`): titles, primary buttons, active icons. Inverted in dark mode.
    #if NOFRI
    static let ink = Color.dynamic(light: 0x6E1B27, dark: 0xE9BE5A)
    #else
    static let ink = Color.dynamic(light: 0x181818, dark: 0xF3F2F0)
    #endif
    /// Text and icons drawn on `ink`.
    #if NOFRI
    static let onInk = Color.dynamic(light: 0xFBF3E4, dark: 0x2B1A14)
    #else
    static let onInk = Color.dynamic(light: 0xFFFFFF, dark: 0x181818)
    #endif
    /// Big titles.
    #if NOFRI
    static let primaryText = Color.dynamic(light: 0x2B1A14, dark: 0xF3ECDD)
    #else
    static let primaryText = Color.dynamic(light: 0x171717, dark: 0xF3F2F0)
    #endif
    /// Subtitles (15 pt).
    #if NOFRI
    static let secondaryText = Color.dynamic(light: 0x6B5A4C, dark: 0xB5A796)
    #else
    static let secondaryText = Color.dynamic(light: 0x66635F, dark: 0xA9A5A0)
    #endif
    /// Small text (12 pt) — slightly darker than the brief's #7D7974 to reach a 4.5:1 contrast.
    #if NOFRI
    static let tertiaryText = Color.dynamic(light: 0x75644F, dark: 0xA39584)
    #else
    static let tertiaryText = Color.dynamic(light: 0x6E6A65, dark: 0x9A9691)
    #endif
    /// Secondary text drawn on a pastel card (grey would fall under 4.5:1 there).
    #if NOFRI
    static let onPastelSecondary = Color.dynamic(light: 0x4F3F33, dark: 0xDDD2C2)
    #else
    static let onPastelSecondary = Color.dynamic(light: 0x4A4547, dark: 0xD9D5D0)
    #endif
    /// Inactive navigation items (brief #AAA6A2 darkened to stay readable).
    #if NOFRI
    static let inactive = Color.dynamic(light: 0x9A8875, dark: 0x7C6F60)
    #else
    static let inactive = Color.dynamic(light: 0x8C8883, dark: 0x77736E)
    #endif
    #if NOFRI
    static let separator = Color.dynamic(light: 0xE8DCC4, dark: 0x3A2E24)
    #else
    static let separator = Color.dynamic(light: 0xECEDEF, dark: 0x2A2B2E)
    #endif
    /// Skeleton blocks.
    #if NOFRI
    static let skeleton = Color.dynamic(light: 0xEADFCB, dark: 0x2E251D)
    #else
    static let skeleton = Color.dynamic(light: 0xECEDEF, dark: 0x26272A)
    #endif
    #if NOFRI
    static let sheetHandle = Color.dynamic(light: 0xD9CBB2, dark: 0x4F4336)
    #else
    static let sheetHandle = Color.dynamic(light: 0xD7D4D1, dark: 0x4A4845)
    #endif

    // MARK: Pastels (cards, stats, tags, accents — never the page background)

    #if NOFRI
    static let pink = Color.dynamic(light: 0xEBCFC6, dark: 0x5C3A33)
    #else
    static let pink = Color.dynamic(light: 0xE8B5EF, dark: 0x5B3D60)
    #endif
    #if NOFRI
    static let pinkSoft = Color.dynamic(light: 0xF5E4DE, dark: 0x3E2925)
    #else
    static let pinkSoft = Color.dynamic(light: 0xF3D8F5, dark: 0x3E2C41)
    #endif
    #if NOFRI
    static let blue = Color.dynamic(light: 0xD9E2E4, dark: 0x2F4044)
    #else
    static let blue = Color.dynamic(light: 0xC7DDF6, dark: 0x2E4258)
    #endif
    #if NOFRI
    static let yellow = Color.dynamic(light: 0xF0DDB0, dark: 0x5A4A22)
    #else
    static let yellow = Color.dynamic(light: 0xF6DEA0, dark: 0x5A4A22)
    #endif
    /// Darker yellow for chart bars on a yellow card.
    #if NOFRI
    static let yellowStrong = Color.dynamic(light: 0xD9A93F, dark: 0xC9A34A)
    #else
    static let yellowStrong = Color.dynamic(light: 0xE5BE5A, dark: 0xC9A34A)
    #endif
    #if NOFRI
    static let green = Color.dynamic(light: 0x9BBF7A, dark: 0x5E7A45)
    #else
    static let green = Color.dynamic(light: 0x93D76E, dark: 0x4E7A38)
    #endif
    #if NOFRI
    static let greenSoft = Color.dynamic(light: 0xE6EDD8, dark: 0x2F3A22)
    #else
    static let greenSoft = Color.dynamic(light: 0xDDF1CF, dark: 0x2C4322)
    #endif
    #if NOFRI
    static let peach = Color.dynamic(light: 0xF0CDB0, dark: 0x6A4636)
    #else
    static let peach = Color.dynamic(light: 0xF6C6A8, dark: 0x6A4636)
    #endif

    #if NOFRI
    /// Nofri: the burgundy of the main card and the gold of its button (same as the app icon).
    static let burgundy = Color.dynamic(light: 0x6E1B27, dark: 0x5A1620)
    static let onBurgundy = Color.dynamic(light: 0xFBF3E4, dark: 0xFBF3E4)
    static let gold = Color.dynamic(light: 0xE9BE5A, dark: 0xE9BE5A)
    static let onGold = Color.dynamic(light: 0x3A1A08, dark: 0x3A1A08)
    #endif

    // MARK: Legacy names, remapped to the new palette

    /// Interactive accent = ink (black pills, selected states, progress).
    static let accent = ink
    static let accentSoft = pinkSoft
    /// Correct answer: green card, ink text, dark green icon.
    #if NOFRI
    static let success = Color.dynamic(light: 0x4A6B1F, dark: 0xB5D48A)
    #else
    static let success = Color.dynamic(light: 0x2F7A1C, dark: 0x93D76E)
    #endif
    static let successSoft = greenSoft
    /// « À revoir »: pink family, never an alarm red.
    #if NOFRI
    static let error = Color.dynamic(light: 0x9A4A2A, dark: 0xF0C0A8)
    #else
    static let error = Color.dynamic(light: 0x9C3A86, dark: 0xF0B6F3)
    #endif
    static let errorSoft = pinkSoft
    #if NOFRI
    static let warning = Color.dynamic(light: 0x7D5A00, dark: 0xF0DDB0)
    #else
    static let warning = Color.dynamic(light: 0x7D5A00, dark: 0xF6DEA0)
    #endif
    #if NOFRI
    static let warningSoft = Color.dynamic(light: 0xF7EBCB, dark: 0x3F3418)
    #else
    static let warningSoft = Color.dynamic(light: 0xFBEFD0, dark: 0x3F3418)
    #endif
    static let secondaryBackground = background
    static let groupedBackground = background
    static let card = surface

    // MARK: Layout

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        /// Gap between cards.
        static let card: CGFloat = 14
        static let m: CGFloat = 16
        /// Horizontal page padding.
        static let page: CGFloat = 20
        static let l: CGFloat = 24
        /// Title -> first block.
        static let titleToContent: CGFloat = 26
        /// Header -> title, and between sections.
        static let section: CGFloat = 28
        static let xl: CGFloat = 32
    }

    enum Radius {
        /// Small blocks, inputs.
        static let small: CGFloat = 16
        /// Secondary cards.
        static let medium: CGFloat = 22
        /// Mini stat cards, portraits.
        static let mediumLarge: CGFloat = 24
        /// Big cards, bottom sheets.
        static let large: CGFloat = 28
        /// Course / chart cards.
        static let xl: CGFloat = 30
    }

    /// Minimum hit target (accessibility).
    static let minTapSize: CGFloat = 44
    /// Primary button height.
    static let primaryButtonHeight: CGFloat = 58
    /// Content width cap on iPad.
    static let maxContentWidth: CGFloat = 720

    // MARK: Typography — Plus Jakarta Sans (400/500/600/700), Dynamic Type through `relativeTo:`

    enum Font {
        static func jakarta(_ size: CGFloat, _ weight: SwiftUI.Font.Weight = .regular,
                            relativeTo style: SwiftUI.Font.TextStyle = .body) -> SwiftUI.Font {
            SwiftUI.Font.custom(postScriptName(weight), size: size, relativeTo: style)
        }

        static func postScriptName(_ weight: SwiftUI.Font.Weight) -> String {
            switch weight {
            case .bold, .heavy, .black: return "PlusJakartaSans-Bold"
            case .semibold: return "PlusJakartaSans-SemiBold"
            case .medium: return "PlusJakartaSans-Medium"
            default: return "PlusJakartaSans-Regular"
            }
        }

        /// Onboarding title (38).
        static let display = jakarta(38, .bold, relativeTo: .largeTitle)
        /// Screen title (34).
        static let largeTitle = jakarta(34, .bold, relativeTo: .largeTitle)
        /// Card title (22).
        static let title = jakarta(22, .bold, relativeTo: .title2)
        /// Big stat value (28).
        static let statValue = jakarta(28, .bold, relativeTo: .title)
        /// Mini stat value (20).
        static let miniStatValue = jakarta(20, .bold, relativeTo: .title3)
        /// Sentence in the studied language (question prompt).
        static let prompt = jakarta(22, .semibold, relativeTo: .title2)
        static let headline = jakarta(17, .semibold, relativeTo: .headline)
        static let body = jakarta(16, .regular, relativeTo: .body)
        /// Subtitle (15, medium).
        static let callout = jakarta(15, .medium, relativeTo: .callout)
        /// Button label (14, semibold).
        static let button = jakarta(14, .semibold, relativeTo: .subheadline)
        /// Small text (12).
        static let caption = jakarta(12, .regular, relativeTo: .caption)
        /// Pills and badges (11, semibold).
        static let badge = jakarta(11, .semibold, relativeTo: .caption2)
        /// Header label (10).
        static let micro = jakarta(10, .regular, relativeTo: .caption2)

        // Weighted variants (custom fonts do not reliably honour `.weight(_:)`).
        static func display(_ w: SwiftUI.Font.Weight) -> SwiftUI.Font { jakarta(38, w, relativeTo: .largeTitle) }
        static func largeTitle(_ w: SwiftUI.Font.Weight) -> SwiftUI.Font { jakarta(34, w, relativeTo: .largeTitle) }
        static func title(_ w: SwiftUI.Font.Weight) -> SwiftUI.Font { jakarta(22, w, relativeTo: .title2) }
        static func prompt(_ w: SwiftUI.Font.Weight) -> SwiftUI.Font { jakarta(22, w, relativeTo: .title2) }
        static func headline(_ w: SwiftUI.Font.Weight) -> SwiftUI.Font { jakarta(17, w, relativeTo: .headline) }
        static func body(_ w: SwiftUI.Font.Weight) -> SwiftUI.Font { jakarta(16, w, relativeTo: .body) }
        static func callout(_ w: SwiftUI.Font.Weight) -> SwiftUI.Font { jakarta(15, w, relativeTo: .callout) }
        static func caption(_ w: SwiftUI.Font.Weight) -> SwiftUI.Font { jakarta(12, w, relativeTo: .caption) }
    }

    /// Letter-spacing of the big titles (-0.04 em) and card titles (-0.025 em), in points.
    enum Tracking {
        static let display: CGFloat = -1.5
        static let largeTitle: CGFloat = -1.36
        static let title: CGFloat = -0.55
    }
}

extension Color {
    /// Light/dark adaptive color from hex RGB values.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
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

/// The one primary action of a screen: black pill, 58 pt, no gradient, scale .985 on tap.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.button)
            .frame(maxWidth: .infinity, minHeight: Theme.primaryButtonHeight)
            .padding(.horizontal, Theme.Spacing.l)
            .foregroundStyle(Theme.onInk)
            .background(Capsule().fill(isEnabled ? Theme.ink : Theme.ink.opacity(0.28)))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Secondary actions ("Explique-moi", "Plus de détails"): white pill, ink label.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.button)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, Theme.Spacing.m)
            .foregroundStyle(Theme.ink)
            .background(Capsule().fill(Theme.surface))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// White secondary card: radius 22, padding 18, no border, no shadow.
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .fill(Theme.surface)
            )
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}

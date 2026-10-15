import ManagedSettings
import ManagedSettingsUI
import UIKit
import LearningPrimitives

/// Calm French shield shown over a restricted app while a lesson is pending.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    // MARK: Content

    private func makeConfiguration() -> ShieldConfiguration {
        // Art direction « éditoriale pastel »: cool off-white page, near-black ink, black pill button.
        // Dark mode follows the app tokens (deep neutral page, inverted ink).
        let background = Self.dynamicColor(light: 0xF6F7FA, dark: 0x111214)
        let ink = Self.dynamicColor(light: 0x181818, dark: 0xF3F2F0)
        let onInk = Self.dynamicColor(light: 0xFFFFFF, dark: 0x181818)
        let titleColor = Self.dynamicColor(light: 0x171717, dark: 0xF3F2F0)
        let subtitleColor = Self.dynamicColor(light: 0x66635F, dark: 0xA9A5A0)

        let symbolConfiguration = UIImage.SymbolConfiguration(weight: .light)
        let icon = UIImage(systemName: "book.closed", withConfiguration: symbolConfiguration)?
            .withTintColor(ink, renderingMode: .alwaysOriginal)

        return ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterial,
            backgroundColor: background,
            icon: icon,
            title: ShieldConfiguration.Label(text: title(), color: titleColor),
            subtitle: ShieldConfiguration.Label(
                text: "Fais ta leçon de 5 minutes dans Quinze pour débloquer tes apps.", color: subtitleColor),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Compris", color: onInk),
            primaryButtonBackgroundColor: ink,
            secondaryButtonLabel: ShieldConfiguration.Label(text: "Déblocage d'urgence", color: ink))
    }

    /// Light/dark adaptive color from hex RGB values (the extension does not link the app's `Theme`).
    private static func dynamicColor(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            let hex: UInt32 = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        }
    }

    /// « Leçon de 14:00 en attente » for the slot being shielded (several: « Leçons en attente »).
    private func title() -> String {
        let state = SharedStateStore.shared.load()
        let today = LocalDay(date: Date())
        let active = SessionSlot.allCases.filter { state.record($0, today)?.active == true }
        switch active.count {
        case 0:
            return "Leçon en attente"
        case 1:
            let time = state.window(for: active[0]).start
            return "Leçon de \(time) en attente"
        default:
            return "Leçons en attente"
        }
    }
}

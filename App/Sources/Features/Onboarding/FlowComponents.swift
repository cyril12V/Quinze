import SwiftUI
import LearningCore

// Small building blocks shared by the onboarding, authentication and settings screens.
// Art direction « éditoriale pastel »: grey-white page, 20 pt margins, big titles, soft callouts,
// one black pill at the bottom. Every step inherits this look through these components.

// MARK: - Viewport (hero sizing)

private struct FlowViewportHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 520
}

extension EnvironmentValues {
    /// Visible height of the enclosing `FlowScreen` (between the status bar and the pinned footer).
    /// `FlowHero` reads it to keep the title and the button on screen on a small iPhone.
    var flowViewportHeight: CGFloat {
        get { self[FlowViewportHeightKey.self] }
        set { self[FlowViewportHeightKey.self] = newValue }
    }
}

// MARK: - Screen scaffold

/// Scrollable content with a footer pinned above the home indicator (one primary action per screen).
struct FlowScreen<Content: View, Footer: View>: View {
    private let content: Content
    private let footer: Footer

    init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.content = content()
        self.footer = footer()
    }

    private var hasFooter: Bool { Footer.self != EmptyView.self }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.page)
                    .padding(.top, Theme.Spacing.s)
                    .padding(.bottom, Theme.Spacing.l)
                    .qContentWidth()
                    .environment(\.flowViewportHeight, proxy.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if hasFooter {
                VStack(spacing: Theme.Spacing.s) { footer }
                    .padding(.horizontal, Theme.Spacing.page)
                    .padding(.top, Theme.Spacing.s)
                    .padding(.bottom, Theme.Spacing.s)
                    .qContentWidth()
                    .background(Theme.background.ignoresSafeArea(edges: .bottom))
            }
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

extension FlowScreen where Footer == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(content: content, footer: { EmptyView() })
    }
}

// MARK: - Titles

/// Big title (2 to 3 lines) + short subtitle. `display` = onboarding size (38); the account and
/// sheet screens pass `display: false` for the regular screen-title size (34).
struct FlowHeader: View {
    let title: String
    var subtitle: String?
    var display: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            ScreenTitle(title, display: display)
            if let subtitle {
                ScreenSubtitle(subtitle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Hero

/// Onboarding illustration (cut-out person on a pastel shape), sized from the visible height of the
/// `FlowScreen` so that the title and the button stay visible on an iPhone SE.
struct FlowHero: View {
    let imageName: String?
    var pastel: Pastel = .pink
    var accent: Pastel = .yellow
    /// Upper bound of the circle diameter: input-heavy steps use a smaller hero.
    var maxDiameter: CGFloat = 310
    /// Height the rest of the screen needs (title, subtitle, spacing).
    var reservedHeight: CGFloat = 260

    @Environment(\.flowViewportHeight) private var viewportHeight

    private var diameter: CGFloat {
        let room: CGFloat = viewportHeight - reservedHeight
        let fitted: CGFloat = room / 1.15
        return min(max(fitted, 130), maxDiameter)
    }

    var body: some View {
        HeroIllustration(imageName: imageName, pastel: pastel, accent: accent, diameter: diameter)
            .frame(maxWidth: .infinity)
    }
}

/// Round pastel icon used where no illustration exists (e-mail sent…).
struct FlowBadgeIcon: View {
    let icon: QIcon
    var pastel: Pastel = .blue

    var body: some View {
        QIconView(icon: icon, size: 34)
            .foregroundStyle(Theme.ink)
            .frame(width: 96, height: 96)
            .background(Circle().fill(pastel.color))
            .accessibilityHidden(true)
    }
}

// MARK: - Messages

/// Inline message under a form: soft pink error, soft blue information, soft green success.
/// Always carries an icon and text, never color alone.
struct FlowMessage: View {
    enum Kind { case error, info, success }

    let text: String
    var kind: Kind = .error

    private var fill: Color {
        switch kind {
        case .error: return Theme.pinkSoft
        case .info: return Pastel.blue.soft
        case .success: return Theme.greenSoft
        }
    }

    private var symbol: String {
        switch kind {
        case .error: return "exclamationmark.circle"
        case .info: return "info.circle"
        case .success: return "checkmark.circle"
        }
    }

    private var spokenText: String {
        kind == .error ? "Erreur. \(text)" : text
    }

    var body: some View {
        QCallout(systemImage: symbol, tint: Theme.ink, fill: fill) {
            Text(text)
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
    }
}

// MARK: - Buttons

/// Text-only button (secondary link): ink, semibold, 44 pt hit target.
struct FlowLinkButton: View {
    let title: String
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Text(title)
                .font(Theme.Font.callout(.semibold))
                .frame(maxWidth: .infinity, minHeight: Theme.minTapSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .foregroundStyle(role == .destructive ? Theme.error : Theme.ink)
    }
}

/// Label of a primary button that shows a spinner while working.
struct FlowButtonLabel: View {
    let title: String
    var isWorking: Bool = false

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            if isWorking { ProgressView().tint(Theme.onInk) }
            Text(title)
        }
    }
}

// MARK: - Choice rows

/// Big white row (radius 22) that turns ink once selected. Selection is shown by the fill, a
/// checkmark and the VoiceOver « selected » trait, never by color alone.
/// Without `action` the row is static (unavailable choice, or a single fixed choice).
struct FlowChoiceRow: View {
    let title: String
    var detail: String? = nil
    /// Small text on the right instead of the selection marker (« Bientôt »).
    var badge: String? = nil
    var isSelected: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action {
                Button(action: action) { rowContent }
                    .buttonStyle(.press)
            } else {
                rowContent
                    .accessibilityElement(children: .combine)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rowContent: some View {
        HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Font.headline)
                    .foregroundStyle(isSelected ? Theme.onInk : Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(Theme.Font.caption)
                        .foregroundStyle(isSelected ? Theme.onInk.opacity(0.8) : Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Spacing.s)
            trailing
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.vertical, Theme.Spacing.card)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .fill(isSelected ? Theme.ink : Theme.surface)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    @ViewBuilder
    private var trailing: some View {
        if let badge {
            Text(badge)
                .font(Theme.Font.badge)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Theme.background))
        } else {
            ZStack {
                Circle().fill(isSelected ? Theme.onInk : Theme.separator)
                if isSelected {
                    QIconView(icon: .check, size: 14).foregroundStyle(Theme.ink)
                }
            }
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)
        }
    }
}

/// Soft separator between two rows of a white block (no hard border).
struct FlowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

// MARK: - Time conversions

extension TimeOfDay {
    /// Today at this wall-clock time, for `DatePicker`.
    var asDate: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    init(date: Date) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        self.init(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }
}

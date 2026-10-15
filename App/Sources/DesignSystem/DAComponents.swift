import SwiftUI
import UIKit

// Building blocks of the « éditoriale pastel » art direction (docs/design/direction-artistique.md).
// Screens compose these instead of styling views by hand: one strong element, one or two secondary
// blocks, a lot of space.

// MARK: - Pastels

enum Pastel: Int, CaseIterable, Sendable {
    case pink, blue, yellow, green

    var color: Color {
        switch self {
        case .pink: return Theme.pink
        case .blue: return Theme.blue
        case .yellow: return Theme.yellow
        case .green: return Color.dynamic(light: 0xC4E8AC, dark: 0x3D5F2C)
        }
    }

    /// Lighter tint of the same family (avatars, icon circles on white).
    var soft: Color {
        switch self {
        case .pink: return Theme.pinkSoft
        case .blue: return Color.dynamic(light: 0xE3EEFB, dark: 0x243444)
        case .yellow: return Theme.warningSoft
        case .green: return Theme.greenSoft
        }
    }

    /// Alternating card colors: rose, bleu, jaune, vert doux.
    static func cycle(_ index: Int) -> Pastel {
        let all = Pastel.allCases
        return all[((index % all.count) + all.count) % all.count]
    }
}

// MARK: - Icons (Nucleo-ready)

/// Semantic icon set. Rendered with thin SF Symbols until Nucleo outline SVGs are added to the asset
/// catalog as `nucleo-<rawValue>` (template images): they are then used automatically.
enum QIcon: String, CaseIterable, Sendable {
    case bell, search, menu, book, clock, play, arrowRight, chevronRight, chevronLeft, chevronDown
    case profile, calendar, chart, flame, home, path, dictionary, settings, close, check, tutor
    case speaker, speakerSlow, lock, unlock, info, plus, lightbulb, warning, send, refresh, target
    case star, logout, trash, share, shield, hourglass, sparkle, edit, mail, eye, eyeSlash

    var symbol: String {
        switch self {
        case .bell: return "bell"
        case .search: return "magnifyingglass"
        case .menu: return "line.3.horizontal"
        case .book: return "book"
        case .clock: return "clock"
        case .play: return "play.fill"
        case .arrowRight: return "arrow.right"
        case .chevronRight: return "chevron.right"
        case .chevronLeft: return "chevron.left"
        case .chevronDown: return "chevron.down"
        case .profile: return "person"
        case .calendar: return "calendar"
        case .chart: return "chart.bar"
        case .flame: return "flame"
        case .home: return "house"
        case .path: return "map"
        case .dictionary: return "character.book.closed"
        case .settings: return "gearshape"
        case .close: return "xmark"
        case .check: return "checkmark"
        case .tutor: return "bubble.left.and.text.bubble.right"
        case .speaker: return "speaker.wave.2"
        case .speakerSlow: return "tortoise"
        case .lock: return "lock"
        case .unlock: return "lock.open"
        case .info: return "info.circle"
        case .plus: return "plus"
        case .lightbulb: return "lightbulb"
        case .warning: return "exclamationmark.triangle"
        case .send: return "arrow.up"
        case .refresh: return "arrow.clockwise"
        case .target: return "target"
        case .star: return "star"
        case .logout: return "rectangle.portrait.and.arrow.right"
        case .trash: return "trash"
        case .share: return "square.and.arrow.up"
        case .shield: return "shield"
        case .hourglass: return "hourglass"
        case .sparkle: return "sparkles"
        case .edit: return "pencil"
        case .mail: return "envelope"
        case .eye: return "eye"
        case .eyeSlash: return "eye.slash"
        }
    }

    /// Filled variant, only for an important active state (selected tab).
    var filledSymbol: String {
        switch self {
        case .home: return "house.fill"
        case .path: return "map.fill"
        case .dictionary: return "character.book.closed.fill"
        case .chart: return "chart.bar.fill"
        case .book: return "book.fill"
        case .profile: return "person.fill"
        case .flame: return "flame.fill"
        case .bell: return "bell.fill"
        case .settings: return "gearshape.fill"
        default: return symbol
        }
    }

    var assetName: String { "nucleo-" + rawValue }
}

struct QIconView: View {
    let icon: QIcon
    var size: CGFloat = 20
    var filled: Bool = false

    var body: some View {
        Group {
            if UIImage(named: icon.assetName) != nil {
                Image(icon.assetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: filled ? icon.filledSymbol : icon.symbol)
                    .font(.system(size: size * 0.86, weight: filled ? .medium : .light))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK - Press feedback

/// Scale 1 -> .98 -> 1 on tap (disabled with Reduce Motion).
struct QPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == QPressStyle {
    static var press: QPressStyle { QPressStyle() }
}

// MARK: - Header

/// Round white button (42 pt, 44 pt hit area) with a thin icon.
struct RoundIconButton: View {
    let icon: QIcon
    let label: String
    var size: CGFloat = 42
    var fill: Color = Theme.surface
    var tint: Color = Theme.ink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            QIconView(icon: icon, size: 20)
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(fill))
                .frame(minWidth: Theme.minTapSize, minHeight: Theme.minTapSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .accessibilityLabel(label)
    }
}

/// Initials in a pastel circle (no photo needed).
struct QAvatar: View {
    let initials: String
    var pastel: Pastel = .pink
    var size: CGFloat = 34
    var ring: Color? = nil

    var body: some View {
        Text(initials.isEmpty ? "?" : initials)
            .font(Theme.Font.jakarta(size * 0.36, .semibold, relativeTo: .caption))
            .foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(pastel.color))
            .overlay {
                if let ring { Circle().strokeBorder(ring, lineWidth: 2) }
            }
            .accessibilityHidden(true)
    }

    /// "Camille Martin" -> "CM", "" -> "".
    static func initials(from name: String?) -> String {
        let parts = (name ?? "").split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map { String($0).uppercased() } }.joined()
    }
}

/// Top of every internal screen: avatar + small label + name/status on the left, a round button on the right.
struct AppHeader: View {
    let label: String
    let title: String
    var initials: String = ""
    var avatarAction: (() -> Void)? = nil
    var avatarAccessibilityLabel: String = "Profil et réglages"
    var trailingIcon: QIcon? = nil
    var trailingLabel: String = ""
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            identity
            Spacer(minLength: Theme.Spacing.s)
            if let trailingIcon, let trailingAction {
                RoundIconButton(icon: trailingIcon, label: trailingLabel, action: trailingAction)
            }
        }
    }

    @ViewBuilder private var identity: some View {
        let content = HStack(spacing: 10) {
            QAvatar(initials: initials)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(Theme.Font.micro)
                    .foregroundStyle(Theme.tertiaryText)
                Text(title)
                    .font(Theme.Font.caption(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
            }
        }
        if let avatarAction {
            Button(action: avatarAction) { content.contentShape(Rectangle()) }
                .buttonStyle(.press)
                .frame(minHeight: Theme.minTapSize)
                .accessibilityLabel(avatarAccessibilityLabel)
                .accessibilityHint("\(label) \(title)")
        } else {
            content.accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Titles

/// Big screen title: 34 pt bold, tight tracking, 3 lines max.
struct ScreenTitle: View {
    let text: String
    var display: Bool = false

    init(_ text: String, display: Bool = false) {
        self.text = text
        self.display = display
    }

    var body: some View {
        Text(text)
            .font(display ? Theme.Font.display : Theme.Font.largeTitle)
            .tracking(display ? Theme.Tracking.display : Theme.Tracking.largeTitle)
            .foregroundStyle(Theme.primaryText)
            .lineLimit(3)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Card title: 22 pt bold, -0.025 em.
struct CardTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.Font.title)
            .tracking(Theme.Tracking.title)
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Subtitle under a title (15 pt medium, grey).
struct ScreenSubtitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.Font.callout)
            .foregroundStyle(Theme.secondaryText)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Pills, filters

/// White pill badge (level, type, status).
struct QPill: View {
    let text: String
    var icon: QIcon? = nil
    var fill: Color = Color.white.opacity(0.85)
    var foreground: Color = Color.dynamic(light: 0x181818, dark: 0x181818)

    var body: some View {
        HStack(spacing: 5) {
            if let icon { QIconView(icon: icon, size: 12) }
            Text(text)
        }
        .font(Theme.Font.badge)
        .foregroundStyle(foreground)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(fill))
        .accessibilityElement(children: .combine)
    }
}

/// Filter capsule (38 pt) with a colored icon circle; ink when selected.
struct FilterChip: View {
    let title: String
    var icon: QIcon? = nil
    var iconFill: Color = Theme.peach
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    QIconView(icon: icon, size: 14)
                        .foregroundStyle(Theme.ink)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(iconFill))
                }
                Text(title)
                    .font(Theme.Font.caption(.semibold))
                    .lineLimit(1)
            }
            .padding(.leading, icon == nil ? 14 : 5)
            .padding(.trailing, 14)
            .frame(minHeight: 38)
            .foregroundStyle(isSelected ? Theme.onInk : Theme.ink)
            .background(Capsule().fill(isSelected ? Theme.ink : Theme.surface))
            .frame(minHeight: Theme.minTapSize)
            .contentShape(Capsule())
        }
        .buttonStyle(.press)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Cards

/// Big pastel card (radius 30, padding 18).
struct PastelCard<Content: View>: View {
    let fill: Color
    var radius: CGFloat = Theme.Radius.xl
    var padding: CGFloat = 18
    let content: Content

    init(_ pastel: Pastel, radius: CGFloat = Theme.Radius.xl, padding: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.fill = pastel.color
        self.radius = radius
        self.padding = padding
        self.content = content()
    }

    init(fill: Color, radius: CGFloat = Theme.Radius.xl, padding: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.fill = fill
        self.radius = radius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
    }
}

extension View {
    /// The only shadow of the art direction, for a floating card.
    func floatingShadow() -> some View {
        shadow(color: Color.black.opacity(0.04), radius: 15, x: 0, y: 10)
    }
}

/// Black 44 pt pill inside a card, label on the left, small round play on the right.
struct CardCTA: View {
    let title: String
    var icon: QIcon = .play
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                Text(title)
                    .font(Theme.Font.button)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.s)
                QIconView(icon: icon, size: 12)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.onInk))
            }
            .foregroundStyle(Theme.onInk)
            .padding(.leading, 18)
            .padding(.trailing, 7)
            .frame(minHeight: 44)
            .background(Capsule().fill(Theme.ink))
            .contentShape(Capsule())
        }
        .buttonStyle(.press)
    }
}

/// Slightly overlapping avatars (28 pt, ring of the card color) + optional green badge.
struct AvatarStack: View {
    let initials: [String]
    var ring: Color = Theme.pink
    var badge: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: -6) {
                ForEach(Array(initials.prefix(4).enumerated()), id: \.offset) { item in
                    QAvatar(initials: item.element, pastel: Pastel.cycle(item.offset + 1), size: 28, ring: ring)
                }
            }
            if let badge {
                Text(badge)
                    .font(Theme.Font.badge)
                    .foregroundStyle(Color.dynamic(light: 0x181818, dark: 0x181818))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.green))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Illustrations

/// Circle with a diagonal cut at the bottom-right (editorial mask behind cut-out portraits).
struct DiagonalCutCircle: Shape {
    /// Angles (degrees, clockwise from 3 o'clock) where the straight cut starts and ends.
    var cutStart: Double = 15
    var cutEnd: Double = 80

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        var angle = cutEnd
        let end = cutStart + 360
        var first = true
        while angle <= end {
            let t = angle * .pi / 180
            let p = CGPoint(x: c.x + r * CGFloat(cos(t)), y: c.y + r * CGFloat(sin(t)))
            if first { path.move(to: p); first = false } else { path.addLine(to: p) }
            angle += 2
        }
        path.closeSubpath()
        return path
    }
}

/// Onboarding hero: a cut-out person (transparent PNG in Assets) on a big pastel shape.
/// Without the image, an abstract pastel composition is shown (never a fake person).
struct HeroIllustration: View {
    let imageName: String?
    var pastel: Pastel = .pink
    var accent: Pastel = .yellow
    var diameter: CGFloat = 310

    var body: some View {
        ZStack(alignment: .bottom) {
            DiagonalCutCircle()
                .fill(pastel.color)
                .frame(width: diameter, height: diameter)
                .frame(maxHeight: .infinity, alignment: .bottom)
            if let imageName, UIImage(named: imageName) != nil {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: diameter * 1.05, maxHeight: diameter * 1.15, alignment: .bottom)
            } else {
                placeholder
            }
        }
        .frame(width: diameter, height: diameter * 1.15)
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Circle()
                .fill(accent.color)
                .frame(width: diameter * 0.3, height: diameter * 0.3)
                .offset(x: diameter * 0.3, y: -diameter * 0.62)
            RoundedRectangle(cornerRadius: Theme.Radius.mediumLarge, style: .continuous)
                .fill(Theme.surface)
                .frame(width: diameter * 0.5, height: diameter * 0.62)
                .rotationEffect(.degrees(-8))
                .offset(x: -diameter * 0.06, y: -diameter * 0.2)
            VStack(alignment: .leading, spacing: 10) {
                Capsule().fill(Theme.ink).frame(width: diameter * 0.26, height: 10)
                Capsule().fill(Theme.skeleton).frame(width: diameter * 0.34, height: 8)
                Capsule().fill(Theme.skeleton).frame(width: diameter * 0.3, height: 8)
                Capsule().fill(Theme.green).frame(width: diameter * 0.18, height: 8)
            }
            .rotationEffect(.degrees(-8))
            .offset(x: -diameter * 0.06, y: -diameter * 0.24)
        }
        .frame(width: diameter, height: diameter * 1.15, alignment: .bottom)
    }
}

/// Portrait on the right of a course card (140 x 180, radius 24). Placeholder when no image.
struct PortraitSlot: View {
    let imageName: String?
    var width: CGFloat = 140
    var height: CGFloat = 180
    var icon: QIcon = .book

    var body: some View {
        Group {
            if let imageName, UIImage(named: imageName) != nil {
                Image(imageName).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.45)
                    QIconView(icon: icon, size: 30).foregroundStyle(Theme.ink.opacity(0.75))
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.mediumLarge, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Charts

struct BarDatum: Identifiable, Equatable {
    let id: Int
    let label: String
    let value: Double
    /// Text of the tooltip / VoiceOver ("12 min").
    let valueText: String
}

/// Thick rounded bars, no axes: dark yellow, the highlighted one in ink with a pink tooltip.
struct RoundedBarChart: View {
    let data: [BarDatum]
    var highlighted: Int? = nil
    var barColor: Color = Theme.yellowStrong
    var highlightColor: Color = Theme.ink
    var height: CGFloat = 150
    var barWidth: CGFloat = 28

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    private var maxValue: Double { max(data.map { $0.value }.max() ?? 0, 0.0001) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(data) { item in
                column(item)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height + 48)
        .onAppear {
            if reduceMotion { grown = true } else {
                withAnimation(.easeOut(duration: 0.6)) { grown = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(data.map { "\($0.label) : \($0.valueText)" }.joined(separator: ", "))
    }

    private func column(_ item: BarDatum) -> some View {
        let isHighlighted = item.id == highlighted
        let ratio = CGFloat(item.value / maxValue)
        let barHeight = max(height * ratio, 6) * (grown ? 1 : 0.02)
        return VStack(spacing: 6) {
            Spacer(minLength: 0)
            if isHighlighted {
                ChartTooltip(text: item.valueText)
            }
            UnevenRoundedRectangle(topLeadingRadius: barWidth / 2, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0, topTrailingRadius: barWidth / 2, style: .continuous)
                .fill(isHighlighted ? highlightColor : barColor)
                .frame(width: barWidth, height: barHeight)
            Text(item.label)
                .font(Theme.Font.micro)
                .foregroundStyle(Theme.onPastelSecondary)
                .lineLimit(1)
        }
    }
}

/// Small pastel pill above a bar.
struct ChartTooltip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Font.jakarta(10, .semibold, relativeTo: .caption2))
            .foregroundStyle(Color.dynamic(light: 0x181818, dark: 0x181818))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(Theme.pink))
            .fixedSize()
    }
}

/// Big yellow chart card: icon + detail on top, big value, then the chart.
struct ChartCard<Chart: View>: View {
    let icon: QIcon
    let detail: String
    let value: String
    var caption: String? = nil
    var fill: Color = Theme.yellow
    let chart: Chart

    init(icon: QIcon, detail: String, value: String, caption: String? = nil, fill: Color = Theme.yellow,
         @ViewBuilder chart: () -> Chart) {
        self.icon = icon
        self.detail = detail
        self.value = value
        self.caption = caption
        self.fill = fill
        self.chart = chart()
    }

    var body: some View {
        PastelCard(fill: fill, radius: Theme.Radius.xl, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    QIconView(icon: icon, size: 18)
                        .foregroundStyle(Theme.onInk)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Theme.ink))
                    Spacer()
                    Text(detail)
                        .font(Theme.Font.caption(.semibold))
                        .foregroundStyle(Theme.onPastelSecondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(Theme.Font.statValue)
                        .tracking(-0.6)
                        .foregroundStyle(Theme.ink)
                    if let caption {
                        Text(caption)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.onPastelSecondary)
                    }
                }
                chart
            }
        }
    }
}

/// Mini stat card (radius 24, padding 18, min height 140) with a black round icon.
struct StatMiniCard: View {
    let icon: QIcon
    let value: String
    let label: String
    var pastel: Pastel = .pink

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            QIconView(icon: icon, size: 18)
                .foregroundStyle(Theme.onInk)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Theme.ink))
            Spacer(minLength: 18)
            Text(value)
                .font(Theme.Font.miniStatValue)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(Theme.Font.jakarta(11, .regular, relativeTo: .caption2))
                .foregroundStyle(Theme.onPastelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.mediumLarge, style: .continuous).fill(pastel.color))
        .accessibilityElement(children: .combine)
    }
}

/// Two mini cards side by side.
struct StatGrid<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            content
        }
    }
}

// MARK: - Inputs

/// Field label (12 pt semibold).
struct QFieldLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.Font.caption(.semibold))
            .foregroundStyle(Theme.primaryText)
    }
}

extension View {
    /// Input look: 52 pt, radius 16, white, no border, soft pink focus ring.
    func qField(isFocused: Bool = false) -> some View {
        self
            .font(Theme.Font.body)
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, Theme.Spacing.m)
            .frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.surface))
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.small + 3, style: .continuous)
                    .fill(Theme.pink.opacity(isFocused ? 0.25 : 0))
                    .padding(-3)
            )
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Bottom sheet

struct SheetHandle: View {
    var body: some View {
        Capsule()
            .fill(Theme.sheetHandle)
            .frame(width: 38, height: 4)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Bottom sheet, radius 28, custom handle. The sheet uses the page background so that the white
    /// cards inside it stay visible (a white sheet would swallow them).
    func qSheet() -> some View {
        self
            .safeAreaInset(edge: .top, spacing: 0) {
                SheetHandle().frame(maxWidth: .infinity)
            }
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(Theme.Radius.large)
            .presentationBackground(Theme.background)
    }
}

// MARK: - Loading & empty states

/// Soft shimmer on skeleton blocks (static with Reduce Motion).
struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geometry in
                        LinearGradient(colors: [.clear, Color.white.opacity(0.45), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: geometry.size.width * 0.6)
                            .offset(x: phase * geometry.size.width * 1.6)
                    }
                    .mask(content)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

struct SkeletonBlock: View {
    var height: CGFloat = 16
    var width: CGFloat? = nil
    var radius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Theme.skeleton)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .modifier(Shimmer())
            .accessibilityHidden(true)
    }
}

/// Placeholder of a big card while content loads.
struct SkeletonCard: View {
    var height: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonBlock(height: 28, width: 90, radius: 14)
            SkeletonBlock(height: 22, width: 200)
            SkeletonBlock(height: 14, width: 140)
            Spacer(minLength: 0)
            SkeletonBlock(height: 44, radius: 22)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).fill(Theme.surface))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement")
    }
}

/// Empty state: small pastel illustration, short sentence, black CTA.
struct EmptyStateView: View {
    let icon: QIcon
    var pastel: Pastel = .blue
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            ZStack {
                Circle().fill(pastel.color).frame(width: 120, height: 120)
                Circle().fill(Pastel.cycle(pastel.rawValue + 2).color).frame(width: 34, height: 34).offset(x: 48, y: -44)
                QIconView(icon: icon, size: 34).foregroundStyle(Theme.ink)
            }
            .accessibilityHidden(true)
            Text(message)
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.primary)
            }
        }
        .padding(.vertical, Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Motion

/// Page/card entrance: opacity 0 -> 1, y 8 -> 0, 50 ms stagger. Nothing with Reduce Motion.
struct AppearModifier: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .onAppear {
                guard !reduceMotion, !shown else { return }
                withAnimation(.easeOut(duration: 0.35).delay(Double(index) * 0.05)) { shown = true }
            }
    }
}

extension View {
    func qAppear(_ index: Int = 0) -> some View { modifier(AppearModifier(index: index)) }

    /// Caps the content width on iPad (720 pt) and centers it.
    func qContentWidth() -> some View {
        frame(maxWidth: Theme.maxContentWidth).frame(maxWidth: .infinity)
    }
}

// MARK: - Page scaffold

/// Standard scrolling page: grey background, 20 pt side padding, iPad width cap, room for the bottom nav.
struct QScreen<Content: View>: View {
    var bottomInset: CGFloat = Theme.Spacing.section
    let content: Content

    init(bottomInset: CGFloat = Theme.Spacing.section, @ViewBuilder content: () -> Content) {
        self.bottomInset = bottomInset
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, bottomInset)
            .qContentWidth()
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

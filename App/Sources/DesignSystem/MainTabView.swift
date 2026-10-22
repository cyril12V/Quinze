import SwiftUI
import UIKit

/// The bottom navigation: home, then one space per subject (its path, words and games, progress).
enum MainTab: String, CaseIterable, Identifiable, Sendable {
    case home, english, arabic, culture

    var id: String { rawValue }

    var subject: Subject? {
        switch self {
        case .home: return nil
        case .english: return .english
        case .arabic: return .arabic
        case .culture: return .culture
        }
    }

    var title: String { subject?.shortName ?? "Accueil" }
}

/// Root of the signed-in app: one NavigationStack per tab + the bottom navigation.
/// Each tab root draws its own `AppHeader` and hides the system navigation bar.
struct MainTabView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var tab: MainTab = .home

    var body: some View {
        ZStack {
            switch tab {
            case .home: NavigationStack { HomeView() }
            case .english: NavigationStack { SubjectSpaceView(subject: .english) }.id(MainTab.english)
            case .arabic: NavigationStack { SubjectSpaceView(subject: .arabic) }.id(MainTab.arabic)
            case .culture: NavigationStack { SubjectSpaceView(subject: .culture) }.id(MainTab.culture)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            QBottomNav(selection: Binding(get: { tab }, set: { select($0) }))
        }
    }

    private func select(_ newTab: MainTab) {
        if let subject = newTab.subject, env.study.focusSubject != subject {
            env.study.focusSubject = subject
            Task { await env.store.refresh() }
        }
        tab = newTab
    }
}

/// Bottom navigation: 78 pt incl. home indicator, translucent grey, thin outline icons,
/// active item in ink (filled icon), no pill behind the active item.
struct QBottomNav: View {
    @Binding var selection: MainTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases) { tab in
                item(tab)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, Theme.Spacing.s)
        .frame(maxWidth: Theme.maxContentWidth)
        .frame(maxWidth: .infinity)
        .background {
            Rectangle()
                .fill(Theme.background.opacity(0.96))
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func item(_ tab: MainTab) -> some View {
        let isActive = tab == selection
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 4) {
                if let subject = tab.subject {
                    Text(subject.emoji)
                        .font(.system(size: 20))
                        .opacity(isActive ? 1 : 0.55)
                        .frame(height: 22)
                } else {
                    QIconView(icon: .home, size: 22, filled: isActive)
                }
                Text(tab.title)
                    .font(Theme.Font.jakarta(10, isActive ? .semibold : .medium, relativeTo: .caption2))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isActive ? Theme.ink : Theme.inactive)
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }
}

/// UIKit-level styling for what SwiftUI does not reach (system navigation bars of pushed screens).
enum QAppearance {
    @MainActor
    static func configure() {
        let background = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x111214) : UIColor(hex: 0xF6F7FA) }
        let ink = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xF3F2F0) : UIColor(hex: 0x171717) }
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = background
        if let title = UIFont(name: "PlusJakartaSans-SemiBold", size: 17) {
            appearance.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: title),
                                              .foregroundColor: ink]
        }
        if let large = UIFont(name: "PlusJakartaSans-Bold", size: 34) {
            appearance.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large),
                                                   .foregroundColor: ink,
                                                   .kern: -1.36]
        }
        let bar = UINavigationBar.appearance()
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.compactAppearance = appearance
        bar.tintColor = ink
    }
}

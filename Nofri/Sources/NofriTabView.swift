import SwiftUI
import LearningCore

/// Root of Nofri once signed in: Accueil, Parcours, Collection, Progrès.
struct NofriTabView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var tab: Tab = .home

    enum Tab: String, CaseIterable, Identifiable {
        case home, path, collection, progress
        var id: String { rawValue }

        var title: String {
            switch self {
            case .home: return "Accueil"
            case .path: return "Parcours"
            case .collection: return "Collection"
            case .progress: return "Progrès"
            }
        }

        var icon: QIcon {
            switch self {
            case .home: return .home
            case .path: return .path
            case .collection: return .star
            case .progress: return .chart
            }
        }
    }

    var body: some View {
        ZStack {
            switch tab {
            case .home: NavigationStack { HomeView() }
            case .path: NavigationStack { PathView() }.id(Tab.path)
            case .collection: NavigationStack { NofriCollectionView() }.id(Tab.collection)
            case .progress: NavigationStack { ProgressDashboardView() }.id(Tab.progress)
            }
        }
        .environment(\.subjectLocked, true)
        .studySubject(.church)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomNav }
        .onAppear {
            if env.study.focusSubject != .church { env.study.focusSubject = .church }
        }
    }

    private var bottomNav: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { item in
                let isActive = item == tab
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 4) {
                        QIconView(icon: item.icon, size: 22, filled: isActive)
                        Text(item.title)
                            .font(Theme.Font.jakarta(10, isActive ? .semibold : .medium, relativeTo: .caption2))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(isActive ? Theme.ink : Theme.inactive)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.press)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
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
}

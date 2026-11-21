import SwiftUI
import UIKit

@main
struct HazzatApp: App {
    @State private var library = Library()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .tint(Palette.ink)
                .preferredColorScheme(.light)
        }
    }
}

/// Where a tap leads.
enum Route: Hashable {
    case period(UUID)
    case song(UUID)
    case search
    case recents
}

/// The four tabs and the screens opened in each one.
@MainActor
@Observable
final class Router {
    enum Tab: Hashable { case home, library, favorites, profile }

    var tab: Tab = .home
    var home: [Route] = []
    var library: [Route] = []
    var favorites: [Route] = []
    var profile: [Route] = []

    /// The bottom bar shows only on the first screen of a tab.
    var atRoot: Bool {
        switch tab {
        case .home: home.isEmpty
        case .library: library.isEmpty
        case .favorites: favorites.isEmpty
        case .profile: profile.isEmpty
        }
    }

    func open(_ route: Route) {
        switch tab {
        case .home: home.append(route)
        case .library: library.append(route)
        case .favorites: favorites.append(route)
        case .profile: profile.append(route)
        }
    }

    func popToRoot(_ tab: Tab) {
        switch tab {
        case .home: home = []
        case .library: library = []
        case .favorites: favorites = []
        case .profile: profile = []
        }
    }
}

struct RootView: View {
    @State private var router = Router()

    var body: some View {
        @Bindable var router = router
        ZStack(alignment: .bottom) {
            TabView(selection: $router.tab) {
                NavigationStack(path: $router.home) { HomeView().routes() }
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Router.Tab.home)
                NavigationStack(path: $router.library) { LibraryView().routes() }
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Router.Tab.library)
                NavigationStack(path: $router.favorites) { FavoritesView().routes() }
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Router.Tab.favorites)
                NavigationStack(path: $router.profile) { ProfileView().routes() }
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Router.Tab.profile)
            }
            if router.atRoot {
                TabBar(selection: $router.tab) { router.popToRoot($0) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: router.atRoot)
        .ignoresSafeArea(.keyboard)
        .environment(router)
    }
}

extension View {
    /// The screens every tab can open.
    func routes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .period(let id): PeriodView(periodID: id)
            case .song(let id): SongView(songID: id)
            case .search: SearchView()
            case .recents: RecentsView()
            }
        }
    }

    /// Leaves room for the bottom bar on the first screen of a tab.
    func tabBarRoom() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: TabBar.height) }
    }
}

/// White bar, four black icons, no labels.
struct TabBar: View {
    static let height: CGFloat = 66
    @Binding var selection: Router.Tab
    let reselect: (Router.Tab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            item(.home, "house.fill", "Accueil")
            item(.library, "square.stack.fill", "Bibliothèque")
            item(.favorites, "bookmark.fill", "Favoris")
            item(.profile, "person.fill", "Profil")
        }
        .padding(.horizontal, 18)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(Color.white.shadow(.drop(color: .black.opacity(0.06), radius: 14, x: 0, y: -2)))
    }

    private func item(_ tab: Router.Tab, _ icon: String, _ label: String) -> some View {
        Button {
            if selection == tab { reselect(tab) } else { selection = tab }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(selection == tab ? Palette.iconOn : Palette.iconOff)
                .frame(maxWidth: .infinity, minHeight: Self.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}

/// Our screens draw their own top bar; this keeps the swipe from the left edge to go back.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

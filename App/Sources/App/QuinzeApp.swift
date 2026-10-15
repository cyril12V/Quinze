import SwiftUI

@main
struct QuinzeApp: App {
    @State private var environment = AppEnvironment.live()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        QAppearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .tint(Theme.accent)
                .font(Theme.Font.body)
                .task { await environment.bootstrap() }
                // quinze://auth-callback (e-mail confirmation) and quinze://reset-password
                .onOpenURL { url in
                    Task { await environment.handle(url: url) }
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        Task { await environment.didBecomeActive() }
                    case .background:
                        environment.didEnterBackground()
                    default:
                        break
                    }
                }
        }
    }
}

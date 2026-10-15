import SwiftUI

/// Routes the app: loading → (auth | onboarding) → home. Also hosts the password-recovery screen and the
/// Screen Time authorization alert.
struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var env = env
        Group {
            switch env.route {
            case .loading:
                LoadingView()
            case .contentError:
                ContentErrorView()
            case .onboarding:
                OnboardingFlowView()
            case .auth:
                AuthFlowView()
            case .home:
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: env.route)
        .fullScreenCover(isPresented: Binding(
            get: { env.auth.state == .passwordRecovery },
            set: { presented in if !presented { env.auth.cancelRecovery() } })) {
            NewPasswordView()
        }
        .alert("Restrictions désactivées", isPresented: $env.screenTimeAlertVisible) {
            Button("Ouvrir les Réglages") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Plus tard", role: .cancel) {}
        } message: {
            Text("L'autorisation Temps d'écran a été retirée : Quinze ne peut plus bloquer tes apps. Tu peux la réactiver dans les Réglages de l'iPhone.")
        }
    }
}

/// Loading: a stack of skeleton cards on the page background (never a bare spinner).
private struct LoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.card) {
            SkeletonBlock(height: 34, width: 220, radius: 12)
                .padding(.bottom, Theme.Spacing.s)
            SkeletonCard(height: 220)
            SkeletonCard(height: 160)
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.top, Theme.Spacing.section)
        .qContentWidth()
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.background.ignoresSafeArea())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement de Quinze")
    }
}

/// The lesson content could not be loaded (corrupted install): the user can retry.
private struct ContentErrorView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var isRetrying = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            EmptyStateView(icon: .warning,
                           pastel: .pink,
                           message: "Contenu indisponible. Les leçons n'ont pas pu être chargées. Réessaie ; si le problème continue, réinstalle l'application : ta progression est sauvegardée sur ton compte.",
                           actionTitle: isRetrying ? "Chargement…" : "Réessayer",
                           action: retry)
                .disabled(isRetrying)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.page)
        .qContentWidth()
        .background(Theme.background.ignoresSafeArea())
    }

    private func retry() {
        isRetrying = true
        Task {
            await env.content.load(languageCode: env.settings.profile.languageId)
            env.store.attachContent()
            await env.store.refresh()
            isRetrying = false
        }
    }
}

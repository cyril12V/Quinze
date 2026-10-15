import SwiftUI
import LearningCore

/// The 8 onboarding steps: welcome → account → language → level → diagnostic → schedule → Screen Time → first lesson.
/// One primary action per screen. Progress is remembered once signed in, so a relaunch resumes the flow.
struct OnboardingFlowView: View {
    enum Step: Int, CaseIterable {
        case welcome, account, language, level, diagnostic, schedule, screenTime, firstLesson
    }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step: Step = .welcome
    @State private var selfAssessed: SelfAssessedLevel = .beginner
    @State private var didSetup = false

    var body: some View {
        VStack(spacing: 0) {
            if step != .welcome { progressHeader }
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .onAppear(perform: setup)
        .onChange(of: env.auth.state) { _, state in
            if state == .signedIn, step == .welcome || step == .account { go(.language) }
        }
    }

    /// Thin ink bar at the top of every step after the welcome (the step number is read by VoiceOver).
    private var progressHeader: some View {
        let total = Double(Step.allCases.count)
        return QProgressBar(value: Double(step.rawValue + 1) / total, height: 4)
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xs)
            .qContentWidth()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Étape \(step.rawValue + 1) sur \(Step.allCases.count)")
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            WelcomeStepView(onStart: { env.markWelcomeSeen(); go(env.auth.isLocalMode ? .language : .account) },
                            onHaveAccount: { env.markWelcomeSeen() })
        case .account:
            AuthFlowView(embedded: true)
        case .language:
            LanguageStepView(onContinue: { go(.level) })
        case .level:
            LevelStepView(selection: $selfAssessed, onContinue: { go(.diagnostic) })
        case .diagnostic:
            DiagnosticStepView(selfAssessed: selfAssessed, onFinished: { go(.schedule) })
        case .schedule:
            ScheduleStepView(onContinue: { go(.screenTime) })
        case .screenTime:
            ScreenTimeStepView(onContinue: { go(.firstLesson) })
        case .firstLesson:
            FirstLessonStepView()
        }
    }

    private func setup() {
        guard !didSetup else { return }
        didSetup = true
        guard env.auth.state == .signedIn else { return }
        let profile = env.settings.profile
        // Local mode starts signed in: still show the welcome screen on the very first launch.
        if env.auth.isLocalMode, profile.onboardingStep == 0, !env.welcomeSeen { return }
        var resume = max(profile.onboardingStep, Step.language.rawValue)
        // Past the diagnostic without a saved placement: redo it.
        if profile.startedAt == nil, resume > Step.diagnostic.rawValue { resume = Step.level.rawValue }
        step = Step(rawValue: resume) ?? .language
        if let raw = profile.selfAssessedLevel, let level = SelfAssessedLevel(rawValue: raw) { selfAssessed = level }
    }

    private func go(_ next: Step) {
        let change = { step = next }
        if reduceMotion { change() } else { withAnimation(.easeInOut(duration: 0.25), change) }
        if env.auth.state == .signedIn, next.rawValue >= Step.language.rawValue {
            env.settings.updateProfile { $0.onboardingStep = next.rawValue }
        }
    }
}

// MARK: - 1. Welcome

struct WelcomeStepView: View {
    let onStart: () -> Void
    let onHaveAccount: () -> Void

    var body: some View {
        FlowScreen {
            FlowHero(imageName: "onboarding-welcome", pastel: .pink, accent: .yellow, reservedHeight: 345)
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                QPill(text: "Quinze")
                ScreenTitle("Apprends quelques minutes chaque jour.", display: true)
                ScreenSubtitle("Révise intelligemment, progresse durablement. Trois leçons de cinq minutes par jour, pour apprendre l'anglais à ton rythme.")
            }
        } footer: {
            Button("Commencer", action: onStart)
                .buttonStyle(.primary)
            FlowLinkButton(title: "J'ai déjà un compte", action: onHaveAccount)
        }
    }
}

// MARK: - 3. Language

struct LanguageStepView: View {
    @Environment(AppEnvironment.self) private var env
    let onContinue: () -> Void

    var body: some View {
        FlowScreen {
            FlowHeader(title: "Quelle langue veux-tu apprendre ?",
                       subtitle: "Pour l'instant, Quinze t'apprend l'anglais.")
            VStack(spacing: Theme.Spacing.card) {
                FlowChoiceRow(title: env.store.languageName, detail: "Pour francophones", isSelected: true)
                FlowChoiceRow(title: "Arabe", badge: "Bientôt")
                    .accessibilityLabel("Arabe, bientôt disponible")
            }
        } footer: {
            Button("Continuer", action: onContinue)
                .buttonStyle(.primary)
        }
    }
}

// MARK: - 4. Self-assessed level

struct LevelStepView: View {
    @Binding var selection: SelfAssessedLevel
    let onContinue: () -> Void

    var body: some View {
        FlowScreen {
            FlowHero(imageName: "onboarding-level", pastel: .blue, accent: .pink,
                     maxDiameter: 170, reservedHeight: 330)
            FlowHeader(title: "Quel est ton niveau ?",
                       subtitle: "Choisis la phrase qui te ressemble le plus. Ça sert seulement à préparer les premières questions.")
            VStack(spacing: Theme.Spacing.card) {
                ForEach(SelfAssessedLevel.allCases, id: \.rawValue) { level in
                    FlowChoiceRow(title: level.displayName, isSelected: selection == level) {
                        selection = level
                    }
                }
            }
        } footer: {
            Button("Continuer", action: onContinue)
                .buttonStyle(.primary)
        }
    }
}

// MARK: - 8. First lesson

struct FirstLessonStepView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var controller: LessonController?
    @State private var isStarting = false
    @State private var errorMessage: String?

    var body: some View {
        FlowScreen {
            FlowHero(imageName: nil, pastel: .green, accent: .pink, maxDiameter: 250, reservedHeight: 340)
            FlowHeader(title: "Ta première leçon",
                       subtitle: "Cinq minutes pour commencer. Tu peux t'arrêter quand tu veux : ta progression est sauvegardée.")
            if let errorMessage { FlowMessage(text: errorMessage, kind: .error) }
        } footer: {
            Button {
                start()
            } label: {
                FlowButtonLabel(title: "Commencer ma première leçon", isWorking: isStarting)
            }
            .buttonStyle(.primary)
            .disabled(isStarting)
            FlowLinkButton(title: "Je la ferai plus tard") { env.completeOnboarding() }
        }
        .fullScreenCover(item: $controller) { active in
            LessonFlowView(controller: active, onClose: { close(active) })
        }
    }

    private func start() {
        isStarting = true
        errorMessage = nil
        Task {
            defer { isStarting = false }
            do {
                controller = try await env.store.startFirstLesson()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func close(_ active: LessonController) {
        if !active.isFinished { active.suspend() }
        controller = nil
        env.completeOnboarding()
    }
}

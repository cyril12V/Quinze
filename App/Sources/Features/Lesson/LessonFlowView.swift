import SwiftUI
import LearningCore

/// Full-screen lesson: top bar, then the screen of the current phase.
struct LessonFlowView: View {
    let controller: LessonController
    let onClose: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBusy = false
    @State private var tutorRequest: TutorRequest?

    init(controller: LessonController, onClose: @escaping () -> Void) {
        self.controller = controller
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            phaseContent
                .id(controller.currentItem?.id)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: controller.phase)
        .sheet(item: $tutorRequest) { request in
            TutorSheet(subject: request.subject)
                .environment(\.tutorAllowsPractice, false)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background && !controller.isFinished {
                controller.suspend()
            }
        }
        .onDisappear { env.speech.stop() }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: Theme.Spacing.s) {
            RoundIconButton(icon: .close, label: "Fermer la leçon", action: close)
                .accessibilityHint(controller.isFinished ? "" : "Ta progression est enregistrée.")

            if !controller.isFinished {
                HStack(spacing: Theme.Spacing.m) {
                    QProgressBar(value: controller.progressFraction)
                    Text(controller.progressLabel)
                        .font(Theme.Font.caption(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.tertiaryText)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Progression")
                .accessibilityValue(controller.progressLabel)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.top, Theme.Spacing.xs)
        .frame(minHeight: Theme.minTapSize)
        .qContentWidth()
    }

    private func close() {
        if controller.isFinished {
            onClose()
        } else {
            controller.suspend()
            onClose()
        }
    }

    // MARK: Phases

    @ViewBuilder private var phaseContent: some View {
        switch controller.phase {
        case .card:
            cardContent
        case .answering:
            answeringContent
        case .grading:
            LessonGradingView()
        case .correction(let evaluation):
            LessonCorrectionView(
                controller: controller,
                evaluation: evaluation,
                exercise: controller.currentExercise,
                isBusy: isBusy,
                onExplain: { explainAnswer(evaluation) },
                onContinue: advance
            )
        case .finished(let summary):
            LessonFinishedView(controller: controller, summary: summary, onDone: onClose)
        }
    }

    @ViewBuilder private var cardContent: some View {
        if let unit = controller.currentUnit {
            if isRuleCard(for: unit) {
                LessonRuleCard(
                    unit: unit,
                    isBusy: isBusy,
                    onContinue: advance,
                    onExplain: { tutorRequest = TutorRequest(subject: .rule(unitId: unit.id)) }
                )
            } else {
                LessonWordCard(unit: unit, isBusy: isBusy, onContinue: advance)
            }
        } else {
            LessonUnavailableView(isBusy: isBusy, onContinue: advance)
        }
    }

    @ViewBuilder private var answeringContent: some View {
        if let exercise = controller.currentExercise {
            LessonAnsweringView(
                controller: controller,
                exercise: exercise,
                hintAllowed: controller.currentItem?.hintAllowed ?? false,
                onSubmit: submit
            )
        } else {
            LessonUnavailableView(isBusy: isBusy, onContinue: advance)
        }
    }

    private func isRuleCard(for unit: LearningUnit) -> Bool {
        if let kind = controller.currentItem?.kind {
            switch kind {
            case .ruleCard: return true
            case .wordCard: return false
            case .exercise: return unit.kind == .grammar
            }
        }
        return unit.kind == .grammar
    }

    // MARK: Actions

    private func explainAnswer(_ evaluation: Evaluation) {
        guard let exercise = controller.currentExercise else { return }
        tutorRequest = TutorRequest(subject: .answer(exerciseId: exercise.id, userAnswer: evaluation.userAnswer))
    }

    private func advance() {
        guard !isBusy else { return }
        isBusy = true
        Task { @MainActor in
            await controller.continueToNext()
            isBusy = false
        }
    }

    private func submit(_ submission: AnswerSubmission) {
        guard !isBusy else { return }
        isBusy = true
        Task { @MainActor in
            await controller.submit(submission)
            isBusy = false
        }
    }
}

// MARK: - Shared scaffold

/// Scrollable content with a pinned footer (the screen's single primary action).
struct LessonScaffold<Content: View, Footer: View>: View {
    let content: Content
    let footer: Footer

    init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                content
                    .padding(.horizontal, Theme.Spacing.page)
                    .padding(.top, Theme.Spacing.s)
                    .padding(.bottom, Theme.Spacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .qContentWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            footer
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.vertical, Theme.Spacing.s)
                .qContentWidth()
                .background(Theme.background)
        }
    }
}

/// Shown while the answer is being graded: a soft card with skeleton lines, never a lone spinner.
struct LessonGradingView: View {
    var body: some View {
        VStack(spacing: 0) {
            PastelCard(.blue, padding: 20) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    CardTitle("Vérification de ta réponse…")
                    SkeletonBlock(height: 14, width: 200, radius: Theme.Radius.small)
                    SkeletonBlock(height: 14, width: 140, radius: Theme.Radius.small)
                }
            }
            .qAppear(0)
            .padding(.horizontal, Theme.Spacing.page)
            .qContentWidth()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Vérification de ta réponse")
    }
}

/// Safety net when the controller exposes no content for the current step.
struct LessonUnavailableView: View {
    let isBusy: Bool
    let onContinue: () -> Void

    var body: some View {
        LessonScaffold {
            PastelCard(.yellow, padding: 20) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    CardTitle("Cette étape n'est pas disponible.")
                    Text("Tu peux passer à la suite.")
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.onPastelSecondary)
                }
            }
            .qAppear(0)
        } footer: {
            Button("Continuer", action: onContinue)
                .buttonStyle(.primary)
                .disabled(isBusy)
        }
    }
}

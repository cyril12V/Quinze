import SwiftUI
import LearningCore

/// Screen of an exercise awaiting an answer: instruction, prompt card, hint, answer area,
/// and « Vérifier » pinned at the bottom.
struct LessonAnsweringView: View {
    let controller: LessonController
    let exercise: Exercise
    let hintAllowed: Bool
    let onSubmit: (AnswerSubmission) -> Void

    @State private var answer: AnswerSubmission?
    @State private var didSubmit = false

    init(controller: LessonController, exercise: Exercise, hintAllowed: Bool,
         onSubmit: @escaping (AnswerSubmission) -> Void) {
        self.controller = controller
        self.exercise = exercise
        self.hintAllowed = hintAllowed
        self.onSubmit = onSubmit
    }

    /// Prompt card color depends on the exercise type.
    private var pastel: Pastel {
        switch exercise.type {
        case .mcq: return .pink
        case .fillBlank: return .blue
        case .translation: return .yellow
        case .reorder: return .green
        case .match: return .blue
        case .freeAnswer: return .yellow
        }
    }

    var body: some View {
        LessonScaffold {
            VStack(alignment: .leading, spacing: Theme.Spacing.card) {
                Text(exercise.instruction)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)

                promptCard
                    .qAppear(0)
                hintBlock

                ExerciseAnswerArea(
                    exercise: exercise,
                    presentation: controller.presentation,
                    answer: $answer
                )
                .padding(.top, Theme.Spacing.s)
                .qAppear(1)
            }
        } footer: {
            Button("Vérifier", action: submit)
                .buttonStyle(.primary)
                .disabled(answer == nil || didSubmit)
        }
        .onChange(of: exercise.id) { _, _ in
            answer = nil
            didSubmit = false
        }
    }

    // MARK: Blocks

    private var promptCard: some View {
        PastelCard(pastel, padding: 20) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                QPill(text: exercise.type.displayName)
                contextBlock
                promptBlock
                if exercise.promptLanguage != "fr" {
                    QSpeakerButton(text: exercise.prompt)
                }
            }
        }
    }

    @ViewBuilder private var contextBlock: some View {
        if let context = exercise.context, !context.isEmpty {
            Text(context)
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Theme.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .fill(Theme.surface)
                )
                .accessibilityLabel("Contexte : \(context)")
        }
    }

    @ViewBuilder private var promptBlock: some View {
        if exercise.promptLanguage == "fr" {
            Text(exercise.prompt)
                .font(exercise.prompt.containsArabic ? .system(.title) : Theme.Font.prompt)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            TappableSentenceView(text: exercise.prompt, languageCode: exercise.promptLanguage)
                .font(exercise.prompt.containsArabic ? .system(.largeTitle) : Theme.Font.prompt)
                .foregroundStyle(Theme.ink)
        }
    }

    @ViewBuilder private var hintBlock: some View {
        if hintAllowed, let hint = exercise.hint, !hint.isEmpty {
            if controller.hintRevealed {
                QCallout(systemImage: "lightbulb", tint: Theme.ink, fill: Theme.warningSoft) {
                    Text(hint)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Indice : \(hint)")
            } else {
                HStack(spacing: 0) {
                    FilterChip(title: "Voir un indice", icon: .lightbulb, iconFill: Theme.yellow) {
                        controller.revealHint()
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: Actions

    private func submit() {
        guard let current = answer, !didSubmit else { return }
        didSubmit = true
        onSubmit(current)
        // Short debounce against double taps; re-enabled if the caller stays on this exercise.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            didSubmit = false
        }
    }
}

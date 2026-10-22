import SwiftUI
import LearningCore

/// Answer area of an exercise, with its own « Vérifier » primary button.
/// Reused by the onboarding diagnostic. Give it `.id(exercise.id)` when the exercise changes
/// (it also resets itself when `exercise.id` changes).
struct ExerciseInputView: View {
    let exercise: Exercise
    // Module-qualified: SwiftUI also declares a (deprecated) `PresentationMode` type.
    let presentation: LearningCore.PresentationMode
    let onSubmit: (AnswerSubmission) -> Void

    @State private var answer: AnswerSubmission?
    @State private var didSubmit = false

    init(exercise: Exercise, presentation: LearningCore.PresentationMode, onSubmit: @escaping (AnswerSubmission) -> Void) {
        self.exercise = exercise
        self.presentation = presentation
        self.onSubmit = onSubmit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            ExerciseAnswerArea(exercise: exercise, presentation: presentation, answer: $answer)
            Button("Vérifier", action: submit)
                .buttonStyle(.primary)
                .disabled(answer == nil || didSubmit)
        }
        .onChange(of: exercise.id) { _, _ in
            answer = nil
            didSubmit = false
        }
    }

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

// MARK: - Answer area (inputs only, no button)

/// The inputs of an exercise without any button: the lesson screen pins « Vérifier » at the bottom,
/// `ExerciseInputView` keeps it inline. Resets itself when `exercise.id` changes.
struct ExerciseAnswerArea: View {
    let exercise: Exercise
    let presentation: LearningCore.PresentationMode
    @Binding var answer: AnswerSubmission?

    init(exercise: Exercise, presentation: LearningCore.PresentationMode, answer: Binding<AnswerSubmission?>) {
        self.exercise = exercise
        self.presentation = presentation
        self._answer = answer
    }

    var body: some View {
        inputArea
            .id(exercise.id)
    }

    @ViewBuilder private var inputArea: some View {
        switch presentation {
        case .choices:
            if let options = exercise.options, !options.isEmpty {
                ExerciseChoiceInput(
                    exerciseId: exercise.id,
                    options: options,
                    asChips: exercise.type == .fillBlank,
                    answer: $answer
                )
            } else {
                ExerciseTextInput(exercise: exercise, answer: $answer)
            }
        case .typed:
            ExerciseTextInput(exercise: exercise, answer: $answer)
        case .tokens:
            if hasTokens {
                ExerciseReorderInput(exercise: exercise, answer: $answer)
            } else {
                ExerciseTextInput(exercise: exercise, answer: $answer)
            }
        case .pairs:
            if let pairs = exercise.pairs, !pairs.isEmpty {
                ExerciseMatchInput(exercise: exercise, answer: $answer)
            } else {
                ExerciseTextInput(exercise: exercise, answer: $answer)
            }
        }
    }

    private var hasTokens: Bool {
        if let tokens = exercise.tokens, !tokens.isEmpty { return true }
        return !exercise.answer.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - Single choice (mcq list, fill_blank chips)

private struct ExerciseChoiceInput: View {
    let exerciseId: String
    let options: [String]
    let asChips: Bool
    @Binding var answer: AnswerSubmission?

    private var shuffledOptions: [String] {
        options.stableShuffled(seed: exerciseId)
    }

    private var selected: String? {
        if case .choice(let value) = answer { return value }
        return nil
    }

    var body: some View {
        if asChips {
            QFlowLayout() {
                ForEach(Array(shuffledOptions.enumerated()), id: \.offset) { _, option in
                    chip(option)
                }
            }
        } else {
            VStack(spacing: Theme.Spacing.s + 2) {
                ForEach(Array(shuffledOptions.enumerated()), id: \.offset) { _, option in
                    row(option)
                }
            }
        }
    }

    /// White pill, ink once selected, with a check mark (never color alone).
    private func chip(_ option: String) -> some View {
        let isSelected: Bool = selected == option
        return Button {
            answer = .choice(option)
        } label: {
            HStack(spacing: Theme.Spacing.xs + 2) {
                if isSelected {
                    QIconView(icon: .check, size: 14)
                }
                Text(option).arabicAware(option)
            }
        }
        .buttonStyle(QChipButtonStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Full-width white pill, ink once selected, with a check mark on the right.
    private func row(_ option: String) -> some View {
        let isSelected: Bool = selected == option
        return Button {
            answer = .choice(option)
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                Text(option).arabicAware(option)
                    .font(Theme.Font.body(.semibold))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    QIconView(icon: .check, size: 16)
                }
            }
            .padding(.vertical, Theme.Spacing.s)
        }
        .buttonStyle(QChipButtonStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Typed answer (fill_blank typed, translation, free_answer)

private struct ExerciseTextInput: View {
    let exercise: Exercise
    @Binding var answer: AnswerSubmission?

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    init(exercise: Exercise, answer: Binding<AnswerSubmission?>) {
        self.exercise = exercise
        self._answer = answer
    }

    private var isMultiline: Bool {
        exercise.type == .translation || exercise.type == .freeAnswer
    }

    /// The learner answers in French only for translation/free answers prompted in the studied language.
    /// "xx" stands for the studied language: `answerLanguage` only compares against "fr".
    private var answersInFrench: Bool {
        exercise.answerLanguage(studied: "xx") == "fr"
    }

    private var placeholder: String {
        if !isMultiline { return "Écris le mot manquant" }
        return answersInFrench ? "Écris ta réponse en français" : "Écris ta réponse en anglais"
    }

    var body: some View {
        TextField(placeholder, text: $text, axis: isMultiline ? .vertical : .horizontal)
            .lineLimit(isMultiline ? 3...8 : 1...1)
            .focused($isFocused)
            .textInputAutocapitalization(answersInFrench ? .sentences : .never)
            .autocorrectionDisabled(!answersInFrench)
            .submitLabel(.done)
            .accessibilityLabel(answersInFrench ? "Ta réponse en français" : "Ta réponse en anglais")
            .padding(.vertical, isMultiline ? Theme.Spacing.m - 2 : 0)
            .frame(maxWidth: .infinity, minHeight: isMultiline ? 120 : 0, alignment: .topLeading)
            .qField(isFocused: isFocused)
            .onChange(of: text) { _, newValue in update(with: newValue) }
    }

    private func update(with value: String) {
        // The return key ends the entry instead of adding a line break.
        if value.contains("\n") {
            text = value.replacingOccurrences(of: "\n", with: "")
            isFocused = false
            return
        }
        let cleaned: String = value.trimmingCharacters(in: .whitespacesAndNewlines)
        answer = cleaned.isEmpty ? nil : .text(cleaned)
    }
}

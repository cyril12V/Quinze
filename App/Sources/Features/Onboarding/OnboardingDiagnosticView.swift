import SwiftUI
import LearningCore

/// Step 5: adaptive placement test (15–20 questions). The result is a starting point, never a certified level.
struct DiagnosticStepView: View {
    @Environment(AppEnvironment.self) private var env

    let selfAssessed: SelfAssessedLevel
    let onFinished: () -> Void

    private enum Phase {
        case intro
        case question
        case result(DiagnosticResult)
    }

    @State private var phase: Phase = .intro
    @State private var session: DiagnosticSession?
    @State private var current: Exercise?
    @State private var errorMessage: String?

    /// Explicit: the synthesized memberwise init would be private because of the private `@State` properties without initial value.
    init(selfAssessed: SelfAssessedLevel, onFinished: @escaping () -> Void) {
        self.selfAssessed = selfAssessed
        self.onFinished = onFinished
    }

    var body: some View {
        switch phase {
        case .intro: intro
        case .question: question
        case .result(let result): resultView(result)
        }
    }

    // MARK: Intro

    private var intro: some View {
        FlowScreen {
            FlowHeader(title: "Faisons le point",
                       subtitle: "Une quinzaine de questions, environ cinq minutes. Elles s'adaptent à tes réponses.")
            FlowMessage(text: "Ce n'est pas un examen et il n'y a pas de note officielle : on cherche seulement le meilleur point de départ pour toi. Si tu ne sais pas, tu peux deviner.",
                        kind: .info)
            if let errorMessage { FlowMessage(text: errorMessage, kind: .error) }
        } footer: {
            Button("Commencer l'évaluation", action: begin)
                .buttonStyle(.primary)
            FlowLinkButton(title: "Passer cette étape", action: skip)
        }
    }

    private func begin() {
        guard let started = env.store.makeDiagnostic(selfAssessed: selfAssessed) else {
            errorMessage = "L'évaluation n'est pas disponible pour le moment. Tu peux passer cette étape."
            return
        }
        session = started
        showNextQuestion()
    }

    private func skip() {
        env.store.completePlacement(nil, selfAssessed: selfAssessed)
        onFinished()
    }

    // MARK: Questions

    private func showNextQuestion() {
        guard let engine = env.store.engine, var running = session else { return }
        let next = running.nextExercise(engine: engine)
        session = running
        if let next {
            current = next
            phase = .question
        } else {
            finish(running)
        }
    }

    private func finish(_ finished: DiagnosticSession) {
        guard let engine = env.store.engine else { return }
        current = nil
        phase = .result(finished.result(engine: engine))
    }

    private func submit(_ submission: AnswerSubmission) {
        guard let engine = env.store.engine, let exercise = current, var running = session else { return }
        let evaluation = engine.evaluate(exercise, submission: submission)
        running.record(exerciseId: exercise.id, evaluation: evaluation, engine: engine)
        session = running
        if running.isFinished { finish(running) } else { showNextQuestion() }
    }

    private var question: some View {
        FlowScreen {
            progressBlock
            if let exercise = current {
                questionCard(exercise)
                ExerciseInputView(exercise: exercise, presentation: Self.presentation(for: exercise), onSubmit: { submit($0) })
                    .id(exercise.id)
            }
            FlowLinkButton(title: "Arrêter l'évaluation", action: skip)
        }
    }

    /// Thin ink bar + « Question n » (answered questions out of the maximum).
    private var progressBlock: some View {
        let answered = session?.answeredCount ?? 0
        let total = max(session?.maxQuestions ?? 20, 1)
        let ratio = Double(min(answered, total)) / Double(total)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Question \(answered + 1)")
                .font(Theme.Font.caption(.semibold))
                .foregroundStyle(Theme.secondaryText)
            QProgressBar(value: ratio, height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progression de l'évaluation, question \(answered + 1)")
    }

    /// Pastel card holding the instruction, the prompt and the optional context (color follows the exercise type).
    private func questionCard(_ exercise: Exercise) -> some View {
        PastelCard(Self.pastel(for: exercise), radius: Theme.Radius.xl, padding: 22) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(exercise.instruction)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.onPastelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(exercise.prompt)
                    .font(Theme.Font.prompt)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let context = exercise.context {
                    Text(context)
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.onPastelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private static func pastel(for exercise: Exercise) -> Pastel {
        switch exercise.type {
        case .mcq: return .blue
        case .fillBlank: return .yellow
        case .translation, .freeAnswer: return .pink
        case .reorder, .match: return .green
        }
    }

    /// Diagnostic exercises are shown the way the exercise type naturally asks for.
    /// Module-qualified: SwiftUI also declares a (deprecated) `PresentationMode` type.
    static func presentation(for exercise: Exercise) -> LearningCore.PresentationMode {
        switch exercise.type {
        case .mcq: return .choices
        case .fillBlank: return (exercise.options?.isEmpty == false) ? .choices : .typed
        case .translation, .freeAnswer: return .typed
        case .reorder: return .tokens
        case .match: return .pairs
        }
    }

    // MARK: Result

    private func resultView(_ result: DiagnosticResult) -> some View {
        FlowScreen {
            FlowHeader(title: "Ton point de départ")
            PastelCard(.green, radius: Theme.Radius.xl, padding: 22) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    QPill(text: result.levelLabel, icon: .target)
                    if let lesson = env.store.lesson(result.startLessonId) {
                        CardTitle("Tu commenceras par la leçon « \(lesson.title) ».")
                    }
                }
                .accessibilityElement(children: .combine)
            }
            FlowMessage(text: "Ce résultat ne correspond à aucun niveau officiel : il sert seulement à choisir tes premières leçons. Il s'ajustera au fil de tes réponses.",
                        kind: .info)
        } footer: {
            Button("Continuer") {
                env.store.completePlacement(result, selfAssessed: selfAssessed)
                onFinished()
            }
            .buttonStyle(.primary)
        }
    }
}

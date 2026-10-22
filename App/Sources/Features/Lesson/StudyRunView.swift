import SwiftUI

/// A sitting: the lesson of the current subject, then « Continuer : Arabe » to chain the next one.
struct StudyRunView: View {
    let run: StudyRun
    let onClose: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var isAdvancing = false

    var body: some View {
        let step: NextStudyStep? = nextStep
        let onNext: (() -> Void)? = step == nil ? nil : { advance() }
        return LessonFlowView(controller: run.controller,
                              onClose: onClose,
                              stepLabel: run.stepLabel,
                              next: step,
                              onNext: onNext)
            .id(run.controller.id)
            .overlay {
                if isAdvancing {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.background.opacity(0.6))
                }
            }
    }

    private var nextStep: NextStudyStep? {
        run.nextSubject.map { NextStudyStep(subject: $0, minutes: env.settings.study.minutes(for: $0)) }
    }

    private func advance() {
        guard !isAdvancing else { return }
        isAdvancing = true
        Task { @MainActor in
            defer { isAdvancing = false }
            if await run.advance() {
                env.study.focusSubject = run.controller.subject
            } else {
                onClose()
            }
        }
    }
}

import SwiftUI
import LearningCore

/// Correction of the last answer: verdict, answer highlighted, expected answer, explanations.
struct LessonCorrectionView: View {
    let controller: LessonController
    let evaluation: Evaluation
    let exercise: Exercise?
    let isBusy: Bool
    let onExplain: () -> Void
    let onContinue: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var showDetails = false
    @AccessibilityFocusState private var headerFocused: Bool

    init(controller: LessonController, evaluation: Evaluation, exercise: Exercise?, isBusy: Bool,
         onExplain: @escaping () -> Void, onContinue: @escaping () -> Void) {
        self.controller = controller
        self.evaluation = evaluation
        self.exercise = exercise
        self.isBusy = isBusy
        self.onExplain = onExplain
        self.onContinue = onContinue
    }

    // MARK: Verdict style

    private struct Verdict {
        /// Icon in the black round of the verdict card.
        let icon: QIcon
        let title: String
        let subtitle: String?
        /// Card fill: green for a good answer, pink for « à revoir », never an alarm red.
        let fill: Color
        /// Small icon and tint in front of the learner's answer.
        let answerIcon: QIcon
        let answerTint: Color
    }

    private var verdict: Verdict {
        switch evaluation.result {
        case .correct:
            return Verdict(icon: .check, title: "Bonne réponse", subtitle: nil, fill: Theme.greenSoft,
                           answerIcon: .check, answerTint: Theme.success)
        case .correctWithTypo:
            return Verdict(icon: .check, title: "Bonne réponse", subtitle: "À une faute d'orthographe près",
                           fill: Theme.greenSoft, answerIcon: .check, answerTint: Theme.success)
        case .partial:
            return Verdict(icon: .refresh, title: "Pas tout à fait", subtitle: "Tu y es presque",
                           fill: Theme.pinkSoft, answerIcon: .close, answerTint: Theme.error)
        case .incorrect:
            return Verdict(icon: .close, title: "À revoir", subtitle: nil, fill: Theme.pinkSoft,
                           answerIcon: .close, answerTint: Theme.error)
        case .pending:
            return Verdict(icon: .clock, title: "Réponse enregistrée", subtitle: nil, fill: Pastel.blue.soft,
                           answerIcon: .clock, answerTint: Theme.ink)
        }
    }

    private var isPlainCorrect: Bool { evaluation.result == .correct }

    // MARK: Body

    var body: some View {
        LessonScaffold {
            VStack(alignment: .leading, spacing: Theme.Spacing.card) {
                header
                    .qAppear(0)
                if controller.pendingReviewNotice { pendingNotice }
                answerCard
                    .qAppear(1)
                feedbackSection
                detailsSection
                    .qAppear(2)
                if exercise != nil {
                    Button("Explique-moi", action: onExplain)
                        .buttonStyle(.secondary)
                        .padding(.top, Theme.Spacing.s)
                }
            }
        } footer: {
            Button("Continuer", action: onContinue)
                .buttonStyle(.primary)
                .disabled(isBusy)
        }
        .onAppear {
            headerFocused = true
            playHaptic()
        }
    }

    private func playHaptic() {
        let generator = UINotificationFeedbackGenerator()
        switch evaluation.result {
        case .correct, .correctWithTypo: generator.notificationOccurred(.success)
        case .partial: generator.notificationOccurred(.warning)
        case .incorrect: generator.notificationOccurred(.error)
        case .pending: break
        }
    }

    // MARK: Header and notices

    /// Green or pink card with the verdict and its icon in a black round.
    private var header: some View {
        PastelCard(fill: verdict.fill, radius: Theme.Radius.large, padding: 20) {
            HStack(spacing: Theme.Spacing.m) {
                QIconView(icon: verdict.icon, size: 22)
                    .foregroundStyle(Theme.onInk)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Theme.ink))
                VStack(alignment: .leading, spacing: 2) {
                    CardTitle(verdict.title)
                    if let subtitle = verdict.subtitle {
                        Text(subtitle)
                            .font(Theme.Font.callout)
                            .foregroundStyle(Theme.onPastelSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityFocused($headerFocused)
    }

    @ViewBuilder private var pendingNotice: some View {
        if controller.canSelfGrade {
            VStack(alignment: .leading, spacing: 12) {
                QCallout(systemImage: "questionmark.circle", tint: Theme.ink, fill: Theme.warningSoft) {
                    Text("Ta réponse n'a pas pu être vérifiée automatiquement. Compare-la avec la réponse attendue : était-elle juste ?")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                HStack(spacing: Theme.Spacing.s) {
                    Button("Oui, c'était juste") { controller.selfGrade(correct: true) }
                        .buttonStyle(.secondary)
                    Button("Non, je me suis trompé") { controller.selfGrade(correct: false) }
                        .buttonStyle(.secondary)
                }
            }
        } else {
            QCallout(systemImage: "wifi.slash", tint: Theme.ink, fill: Theme.warningSoft) {
                Text("Ta réponse sera vérifiée dès que tu seras en ligne")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.caption(.semibold))
            .foregroundStyle(Theme.tertiaryText)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Learner answer and expected answer (one white card)

    private var answerCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            answerSection
            expectedSection
        }
        .card()
    }

    private var isMatchAnswer: Bool {
        exercise?.type == .match || !evaluation.wrongPairs.isEmpty
    }

    private var hasDiffMarks: Bool {
        evaluation.diff.contains { $0.status != .same }
    }

    private var answerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s + 2) {
            sectionLabel("Ta réponse")
            if isMatchAnswer {
                matchLines(evaluation.userAnswer, flagged: wrongPairLines)
            } else if hasDiffMarks {
                QFlowLayout(spacing: Theme.Spacing.xs + 2, lineSpacing: Theme.Spacing.s) {
                    ForEach(Array(evaluation.diff.enumerated()), id: \.offset) { _, token in
                        DiffTokenView(token: token)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                plainAnswer
            }
        }
    }

    private var wrongPairLines: Set<String> {
        Set(evaluation.wrongPairs.map { "\($0.left) = \($0.right)" })
    }

    private var plainAnswer: some View {
        let text: String = evaluation.userAnswer.isEmpty ? "(aucune réponse)" : evaluation.userAnswer
        return HStack(alignment: .top, spacing: Theme.Spacing.s) {
            QIconView(icon: verdict.answerIcon, size: 18)
                .foregroundStyle(verdict.answerTint)
                .padding(.top, 4)
            Text(text)
                .font(Theme.Font.prompt)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func matchLines(_ text: String, flagged: Set<String>) -> some View {
        let lines: [String] = text.components(separatedBy: " ; ").filter { !$0.isEmpty }
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let isWrong: Bool = flagged.contains(line)
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    QIconView(icon: isWrong ? .close : .check, size: 16)
                        .foregroundStyle(isWrong ? Theme.error : Theme.success)
                        .padding(.top, 2)
                    Text(line)
                        .strikethrough(isWrong, color: Theme.error)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(isWrong ? "\(line), à revoir" : "\(line), juste")
            }
        }
    }

    // MARK: Expected answer

    private var expectedTitle: String? {
        switch evaluation.result {
        case .correct: return nil
        case .correctWithTypo: return "Écriture correcte"
        case .partial, .incorrect: return "Réponse attendue"
        case .pending: return evaluation.expectedAnswer.isEmpty ? nil : "Exemple de réponse"
        }
    }

    @ViewBuilder private var expectedSection: some View {
        if let title = expectedTitle, !evaluation.expectedAnswer.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s + 2) {
                sectionLabel(title)
                if isMatchAnswer {
                    matchLines(evaluation.expectedAnswer, flagged: [])
                } else {
                    expectedSentence
                }
            }
        }
    }

    @ViewBuilder private var expectedSentence: some View {
        let studied: String = env.store.learningLanguageCode
        let language: String = exercise?.answerLanguage(studied: studied) ?? studied
        TappableSentenceView(text: evaluation.expectedAnswer, languageCode: language)
            .font(Theme.Font.prompt)
            .foregroundStyle(Theme.primaryText)
    }

    // MARK: Feedback and details

    @ViewBuilder private var feedbackSection: some View {
        if let note = evaluation.typoNote, !note.isEmpty {
            QCallout(systemImage: "textformat.abc", tint: Theme.ink, fill: Theme.warningSoft) {
                Text(note)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
        if let feedback = evaluation.feedback, !feedback.isEmpty {
            QCallout(systemImage: "info.circle", tint: Theme.ink, fill: Pastel.blue.soft) {
                Text(feedback)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func hasTip(_ exercise: Exercise) -> Bool {
        if let tip = exercise.tip { return !tip.isEmpty }
        return false
    }

    private func hasExplanationContent(_ exercise: Exercise) -> Bool {
        !exercise.explanation.isEmpty || ruleSummary(for: exercise) != nil || exercise.extraExample != nil
    }

    @ViewBuilder private var detailsSection: some View {
        if let exercise {
            if isPlainCorrect {
                if hasExplanationContent(exercise) || hasTip(exercise) {
                    DisclosureGroup("Pour comprendre", isExpanded: $showDetails) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.card) {
                            explanationContent(for: exercise)
                            tipCallout(for: exercise)
                        }
                        .padding(.top, Theme.Spacing.m)
                    }
                    .font(Theme.Font.callout(.semibold))
                    .foregroundStyle(Theme.ink)
                    .tint(Theme.ink)
                    .card()
                }
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.card) {
                    if hasExplanationContent(exercise) {
                        explanationContent(for: exercise)
                            .card()
                    }
                    tipCallout(for: exercise)
                }
            }
        }
    }

    /// Explanation, rule summary and extra example (the white card of the correction).
    private func explanationContent(for exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            if !exercise.explanation.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    sectionLabel("Explication")
                    Text(exercise.explanation)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let summary = ruleSummary(for: exercise) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    sectionLabel("La règle")
                    Text(summary)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let example = exercise.extraExample {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    sectionLabel("Un autre exemple")
                    HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                        TappableSentenceView(text: example.text, languageCode: env.store.learningLanguageCode)
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.primaryText)
                        QSpeakerButton(text: example.text)
                    }
                    Text(example.translation)
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func tipCallout(for exercise: Exercise) -> some View {
        if let tip = exercise.tip, !tip.isEmpty {
            QCallout(systemImage: "lightbulb", tint: Theme.ink, fill: Theme.warningSoft) {
                Text(tip)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Astuce : \(tip)")
        }
    }

    private func ruleSummary(for exercise: Exercise) -> String? {
        guard let unit = env.store.unit(exercise.primaryUnitId), unit.kind == .grammar,
              let summary = unit.rule?.summary, !summary.isEmpty else { return nil }
        return summary
    }
}

// MARK: - Diff token

/// One token of the learner's answer. Non-color cues: underline (solid / dotted / dashed),
/// strike-through for extra words, « + » prefix for missing words, plus the spoken label.
private struct DiffTokenView: View {
    let token: TokenDiff

    private var displayText: String {
        switch token.status {
        case .missing: return "+ " + (token.expected ?? "…")
        default: return token.text
        }
    }

    private var tint: Color {
        switch token.status {
        case .same: return Theme.primaryText
        case .wrong, .extra: return Theme.error
        case .missing, .typo: return Theme.warning
        }
    }

    private var fill: Color {
        switch token.status {
        case .same: return Color.clear
        case .wrong, .extra: return Theme.errorSoft
        case .missing, .typo: return Theme.warningSoft
        }
    }

    private var underlinePattern: Text.LineStyle.Pattern {
        switch token.status {
        case .typo: return .dot
        case .missing: return .dash
        default: return .solid
        }
    }

    private var isUnderlined: Bool {
        token.status == .wrong || token.status == .typo || token.status == .missing
    }

    private var spokenLabel: String {
        switch token.status {
        case .same:
            return token.text
        case .wrong:
            return "\(token.text), mot incorrect" + expectedSuffix
        case .missing:
            return "mot manquant" + expectedSuffix
        case .extra:
            return "\(token.text), mot en trop"
        case .typo:
            return "\(token.text), faute d'orthographe" + expectedSuffix
        }
    }

    private var expectedSuffix: String {
        if let expected = token.expected, !expected.isEmpty { return ", attendu : \(expected)" }
        return ""
    }

    var body: some View {
        Text(displayText)
            .font(Theme.Font.prompt)
            .strikethrough(token.status == .extra, color: Theme.error)
            .underline(isUnderlined, pattern: underlinePattern, color: tint)
            .foregroundStyle(tint)
            .padding(.horizontal, token.status == .same ? 0 : Theme.Spacing.s)
            .padding(.vertical, token.status == .same ? 0 : Theme.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(fill)
            )
            .accessibilityLabel(spokenLabel)
    }
}

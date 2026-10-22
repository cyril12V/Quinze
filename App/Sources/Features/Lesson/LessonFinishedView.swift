import SwiftUI
import LearningCore

/// End of session: what was worked on, important errors, next session, restriction status.
struct LessonFinishedView: View {
    let controller: LessonController
    let summary: SessionSummary
    let onDone: () -> Void
    var next: NextStudyStep? = nil
    var onNext: (() -> Void)? = nil

    @Environment(AppEnvironment.self) private var env
    @AccessibilityFocusState private var titleFocused: Bool

    private let maxVisibleUnits = 8

    init(controller: LessonController, summary: SessionSummary, onDone: @escaping () -> Void,
         next: NextStudyStep? = nil, onNext: (() -> Void)? = nil) {
        self.controller = controller
        self.summary = summary
        self.onDone = onDone
        self.next = next
        self.onNext = onNext
    }

    var body: some View {
        LessonScaffold {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header
                    .qAppear(0)
                verdict
                statsGrid
                    .qAppear(1)
                workedUnits
                importantErrors
                nextSession
                restrictionStatus
                    .qAppear(2)
            }
        } footer: {
            if let next, let onNext {
                VStack(spacing: Theme.Spacing.s) {
                    Button("Continuer : \(next.subject.displayName) · \(next.minutes) min", action: onNext)
                        .buttonStyle(.primary)
                    Button("Plus tard", action: onDone)
                        .buttonStyle(.secondary)
                }
            } else {
                Button("Terminer", action: onDone)
                    .buttonStyle(.primary)
            }
        }
        .task {
            titleFocused = true
            await env.study.refresh()
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s + 2) {
            illustration
                .frame(maxWidth: .infinity)
            ScreenTitle(next == nil ? "Session terminée" : "\(controller.subject.displayName) : terminé !")
                .padding(.top, Theme.Spacing.s)
                .accessibilityFocused($titleFocused)
            ScreenSubtitle(subtitle)
        }
    }

    /// The cut-out portrait when the asset exists, otherwise a green shape with a check.
    @ViewBuilder private var illustration: some View {
        if UIImage(named: "session-done") != nil {
            HeroIllustration(imageName: "session-done", pastel: .green, diameter: 220)
        } else {
            ZStack {
                DiagonalCutCircle()
                    .fill(Pastel.green.color)
                    .frame(width: 150, height: 150)
                QIconView(icon: .check, size: 36)
                    .foregroundStyle(Theme.onInk)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(Theme.ink))
            }
            .padding(.vertical, Theme.Spacing.s)
            .accessibilityHidden(true)
        }
    }

    private var subtitle: String {
        var parts: [String] = [summary.type.displayName]
        if summary.durationSeconds >= 1 {
            parts.append(FrenchLabels.duration(seconds: Int(summary.durationSeconds.rounded())))
        }
        if summary.reviewCount > 0 {
            parts.append(summary.reviewCount > 1 ? "\(summary.reviewCount) révisions" : "\(summary.reviewCount) révision")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Verdict (lesson validated, exam passed)

    @ViewBuilder private var verdict: some View {
        if let outcome = controller.outcome {
            if let passed = outcome.lessonPassed, let score = outcome.lessonScore {
                verdictCard(ok: passed,
                            title: passed ? "Leçon validée" : "Leçon à revoir",
                            text: passed
                                ? "\(FrenchLabels.percent(score)) de bonnes réponses du premier coup. La suite est ouverte."
                                : "\(FrenchLabels.percent(score)) du premier coup, il en faut 80 %. On reprend cette leçon à la prochaine séance, avec le cours : rien n'est perdu.")
            } else if let passed = outcome.examPassed, let score = outcome.examScore {
                verdictCard(ok: passed,
                            title: passed ? "Contrôle réussi" : "Contrôle pas encore réussi",
                            text: passed
                                ? "\(FrenchLabels.percent(score)) : le module est consolidé, le suivant est ouvert."
                                : "\(FrenchLabels.percent(score)), il faut 80 %. Prochaine séance : révision ciblée de ce module, puis tu repasses le contrôle.")
            }
        }
    }

    private func verdictCard(ok: Bool, title: String, text: String) -> some View {
        PastelCard(ok ? .green : .yellow, padding: 18) {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                QIconView(icon: ok ? .check : .refresh, size: 18)
                    .foregroundStyle(Theme.onInk)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.ink))
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    CardTitle(title)
                    Text(text)
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.onPastelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Numbers

    private var statsGrid: some View {
        StatGrid {
            StatMiniCard(icon: .target, value: "\(summary.attemptCount)", label: "Exercices", pastel: .pink)
            StatMiniCard(icon: .check, value: "\(summary.correctCount)", label: "Bonnes réponses", pastel: .blue)
            if let score = summary.score {
                StatMiniCard(icon: .chart, value: FrenchLabels.percent(score), label: "Ton score", pastel: .yellow)
            }
        }
    }

    @ViewBuilder private var workedUnits: some View {
        let titles: [String] = summary.unitIdsWorked.compactMap { controller.unit($0)?.title }
        if !titles.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                QSectionTitle("Ce que tu as travaillé")
                QFlowLayout() {
                    ForEach(Array(titles.prefix(maxVisibleUnits).enumerated()), id: \.offset) { _, title in
                        QPill(text: title)
                    }
                }
                if titles.count > maxVisibleUnits {
                    Text("et \(titles.count - maxVisibleUnits) autres")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
        }
    }

    // MARK: Errors

    @ViewBuilder private var importantErrors: some View {
        if !summary.importantErrors.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                QSectionTitle("À retenir")
                ForEach(Array(summary.importantErrors.enumerated()), id: \.offset) { _, error in
                    errorCard(error)
                }
            }
        }
    }

    private func errorCard(_ error: ImportantError) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(error.prompt)
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.secondaryText)
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                QIconView(icon: .check, size: 16)
                    .foregroundStyle(Theme.success)
                    .padding(.top, 2)
                Text("Attendu : \(error.expected)")
                    .font(Theme.Font.body(.semibold))
                    .foregroundStyle(Theme.primaryText)
            }
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                QIconView(icon: .close, size: 16)
                    .foregroundStyle(Theme.error)
                    .padding(.top, 2)
                Text("Ta réponse : \(error.given.isEmpty ? "aucune" : error.given)")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.primaryText)
            }
            if let category = error.category {
                Text(category.displayName)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    // MARK: Next session and restrictions

    private var nextSessionText: String? {
        if let next {
            return "Ensuite : \(next.subject.displayName). Ta leçon du créneau sera terminée après toutes tes matières."
        }
        let slots: [SlotState] = env.study.today.slots
        guard !slots.isEmpty else { return nil }
        let pending: [SlotState] = slots.filter {
            $0.status == .upcoming || $0.status == .available || $0.status == .inProgress
        }
        if let next = pending.first {
            return "Prochaine leçon : \(next.slot.displayName.lowercased()), à \(next.scheduledTime)"
        }
        return "Tu as terminé tes leçons du jour. À demain !"
    }

    @ViewBuilder private var nextSession: some View {
        if let text = nextSessionText {
            HStack(alignment: .top, spacing: Theme.Spacing.s + 2) {
                QIconView(icon: .calendar, size: 18)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 1)
                Text(text)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Restriction status in an ink card: text in `onInk`, unlock / lock icon in a white round.
    @ViewBuilder private var restrictionStatus: some View {
        if let lifted = controller.restrictionLifted {
            if lifted {
                inkCard(icon: .unlock) {
                    Text("Tes apps sont débloquées")
                        .font(Theme.Font.headline)
                        .foregroundStyle(Theme.onInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                inkCard(icon: .lock) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Tes apps restent verrouillées")
                            .font(Theme.Font.headline)
                            .foregroundStyle(Theme.onInk)
                        Text(remainingText)
                            .font(Theme.Font.callout)
                            .foregroundStyle(Theme.onInk)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Subjects of the slot still to do, from the home blocks.
    private var remainingText: String {
        guard let slot = controller.slot,
              let state = env.study.today.slots.first(where: { $0.slot == slot }) else {
            return "Termine les matières du créneau pour les débloquer, ou utilise le déblocage d'urgence depuis l'accueil."
        }
        let left = state.parts.filter { $0.status != .completed && $0.subject != controller.subject }.map { $0.subject.displayName.lowercased() }
        guard !left.isEmpty else { return "Elles se débloquent dans un instant." }
        return "Il reste : \(left.joined(separator: ", ")). Reviens à l'accueil et touche le bloc suivant."
    }

    private func inkCard<Content: View>(icon: QIcon, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            QIconView(icon: icon, size: 20)
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.onInk))
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Spacing.m + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).fill(Theme.ink)
        )
        .accessibilityElement(children: .combine)
    }
}

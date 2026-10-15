import SwiftUI
import LearningCore

/// End of session: what was worked on, important errors, next session, restriction status.
struct LessonFinishedView: View {
    let controller: LessonController
    let summary: SessionSummary
    let onDone: () -> Void

    @Environment(AppEnvironment.self) private var env
    @AccessibilityFocusState private var titleFocused: Bool

    private let maxVisibleUnits = 8

    init(controller: LessonController, summary: SessionSummary, onDone: @escaping () -> Void) {
        self.controller = controller
        self.summary = summary
        self.onDone = onDone
    }

    var body: some View {
        LessonScaffold {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header
                    .qAppear(0)
                statsGrid
                    .qAppear(1)
                workedUnits
                importantErrors
                nextSession
                restrictionStatus
                    .qAppear(2)
            }
        } footer: {
            Button("Terminer", action: onDone)
                .buttonStyle(.primary)
        }
        .task {
            titleFocused = true
            await env.store.refresh()
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s + 2) {
            illustration
                .frame(maxWidth: .infinity)
            ScreenTitle("Session terminée")
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
        let titles: [String] = summary.unitIdsWorked.compactMap { env.store.unit($0)?.title }
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
        let slots: [SlotState] = env.store.today.slots
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
                        Text("Cette session ne concerne pas le créneau en cours. Termine la leçon du créneau pour les débloquer, ou utilise le déblocage d'urgence depuis l'accueil.")
                            .font(Theme.Font.callout)
                            .foregroundStyle(Theme.onInk)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
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

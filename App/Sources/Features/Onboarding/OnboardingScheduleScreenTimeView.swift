import SwiftUI
import UserNotifications
import LearningCore

/// Step 6: the three daily lesson times + notification permission.
struct ScheduleStepView: View {
    @Environment(AppEnvironment.self) private var env

    let onContinue: () -> Void
    @State private var draft = DailySchedule.default
    @State private var isSaving = false
    @State private var notificationsDenied = false

    private var issues: [DailySchedule.Issue] { draft.validate() }

    var body: some View {
        FlowScreen {
            FlowHero(imageName: "onboarding-schedule", pastel: .yellow, accent: .pink,
                     maxDiameter: 150, reservedHeight: 340)
            FlowHeader(title: "Tes trois leçons du jour",
                       subtitle: "Cinq minutes à chaque horaire. Tu pourras les changer à tout moment dans les réglages.")
            VStack(spacing: 0) {
                ForEach(SessionSlot.allCases) { slot in
                    DatePicker(slot.displayName, selection: binding(for: slot), displayedComponents: .hourAndMinute)
                        .font(Theme.Font.body)
                        .tint(Theme.ink)
                        .frame(minHeight: Theme.minTapSize + 8)
                    if slot != .evening { FlowDivider() }
                }
            }
            .padding(.horizontal, Theme.Spacing.page)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(Theme.surface))

            ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                FlowMessage(text: issue.message, kind: .error)
            }
            FlowMessage(text: "Nous te rappellerons chaque leçon par une notification. Tu peux aussi faire une leçon jusqu'à \(draft.earlyStartMinutes) minutes avant l'heure prévue.",
                        kind: .info)
            if notificationsDenied {
                FlowMessage(text: "Les notifications sont désactivées. Tu pourras les activer plus tard dans les Réglages de l'iPhone : elles ne sont pas nécessaires pour utiliser Quinze.",
                            kind: .info)
            }
        } footer: {
            Button(action: save) {
                FlowButtonLabel(title: "Continuer", isWorking: isSaving)
            }
            .buttonStyle(.primary)
            .disabled(!issues.isEmpty || isSaving)
        }
        .onAppear { draft = env.settings.schedule }
    }

    private func binding(for slot: SessionSlot) -> Binding<Date> {
        Binding(get: { draft.time(for: slot).asDate },
                set: { draft.setTime(TimeOfDay(date: $0), for: slot) })
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            // Permission first, so the reminders registered right after respect the answer.
            let alreadyWarned = notificationsDenied
            let granted = await env.notifications.requestAuthorization()
            notificationsDenied = !granted
            _ = await env.saveSchedule(draft)
            env.settings.markScheduleForSync()
            env.sync.requestSync(.settings)
            // Notifications refused: show the note once; the next tap on « Continuer » moves on.
            if granted || alreadyWarned { onContinue() }
        }
    }
}

/// Step 7: Screen Time (explanation, authorization, app selection). Skippable.
struct ScreenTimeStepView: View {
    @Environment(AppEnvironment.self) private var env

    let onContinue: () -> Void
    @State private var showPicker = false
    @State private var isRequesting = false

    private var authorization: RestrictionAuthorization { env.restrictions.authorization }

    var body: some View {
        FlowScreen {
            FlowHero(imageName: "onboarding-focus", pastel: .green, accent: .yellow,
                     maxDiameter: 170, reservedHeight: 340)
            FlowHeader(title: "Reste concentré",
                       subtitle: "Quinze peut bloquer certaines apps à l'heure de tes leçons, pour t'aider à t'y mettre.")
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                point(.unlock, "Les apps se débloquent dès que ta leçon est terminée.")
                point(.clock, "Dans tous les cas, elles se débloquent \(env.settings.schedule.safetyWindowMinutes) minutes après l'heure de la leçon, même si tu ne l'as pas faite.")
                point(.shield, "Un déblocage d'urgence est toujours disponible dans les réglages.")
                point(.lock, "Ton choix d'apps reste sur ton iPhone : il n'est jamais envoyé sur nos serveurs.")
            }
            .card()
            if authorization == .denied {
                FlowMessage(text: "L'autorisation n'a pas été accordée. Tu pourras la donner plus tard dans Réglages > Restrictions.", kind: .info)
            } else if authorization == .unavailable {
                FlowMessage(text: "Temps d'écran n'est pas disponible sur cet appareil. Tu peux continuer sans restrictions.", kind: .info)
            }
        } footer: {
            switch authorization {
            case .approved:
                Button("Choisir les apps à bloquer") { showPicker = true }
                    .buttonStyle(.primary)
                FlowLinkButton(title: "Plus tard", action: onContinue)
            case .denied, .unavailable:
                Button("Continuer sans restrictions", action: onContinue)
                    .buttonStyle(.primary)
            case .notDetermined:
                Button(action: requestAuthorization) {
                    FlowButtonLabel(title: "Autoriser Temps d'écran", isWorking: isRequesting)
                }
                .buttonStyle(.primary)
                .disabled(isRequesting)
                FlowLinkButton(title: "Plus tard", action: onContinue)
            }
        }
        .sheet(isPresented: $showPicker) {
            AppSelectionView(onDone: pickerDone)
        }
        .onAppear { env.restrictions.refreshAuthorization() }
    }

    /// Thin icon in a soft pastel circle + one short sentence.
    private func point(_ icon: QIcon, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            QIconView(icon: icon, size: 18)
                .foregroundStyle(Theme.ink)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Pastel.green.soft))
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func requestAuthorization() {
        isRequesting = true
        Task {
            defer { isRequesting = false }
            let result = await env.restrictions.requestAuthorization()
            if result == .approved { showPicker = true }
        }
    }

    private func pickerDone() {
        showPicker = false
        if env.restrictions.hasSelection {
            env.restrictions.setEnabled(true, schedule: env.settings.schedule)
        }
        onContinue()
    }
}

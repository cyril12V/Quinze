import SwiftUI
import LearningCore

// Building blocks of the home screen (« dashboard » model of docs/design/direction-artistique.md).
// Tokens and DA components only: no hard-coded fonts, colors, radii, borders or shadows.

// MARK: - Slot vocabulary

extension SlotStatus {
    /// "Terminée", "En cours"… (always shown next to the icon: color never carries the state alone).
    var homeLabel: String {
        switch self {
        case .completed: return "Terminée"
        case .inProgress: return "En cours"
        case .available: return "Disponible"
        case .upcoming: return "À venir"
        case .missed: return "Manquée"
        }
    }

    var homeIcon: QIcon {
        switch self {
        case .completed: return .check
        case .inProgress: return .hourglass
        case .available: return .play
        case .upcoming: return .clock
        case .missed: return .refresh
        }
    }

    /// Two pastels at most on a row of chips: green = done, pink = to do now, neutral = later.
    var homeIconFill: Color {
        switch self {
        case .completed: return Theme.green
        case .inProgress, .available, .missed: return Theme.pink
        case .upcoming: return Theme.separator
        }
    }
}

extension SessionSlot {
    /// One stable pastel per slot: rose (matin), bleu (après-midi), jaune (soir).
    var homePastel: Pastel { Pastel.cycle(index) }
}

// MARK: - Carousel model

enum HomeCardID: Hashable, Sendable {
    case slot(SessionSlot)
    case extra
}

struct HomeCarouselItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case slot(SlotState)
        case extra(allDone: Bool)
    }

    let kind: Kind

    var id: HomeCardID {
        switch kind {
        case .slot(let slot): return .slot(slot.slot)
        case .extra: return .extra
        }
    }
}

enum HomeFeaturedState {
    case loading
    case resume(SlotState)
    case start(SlotState)
    case catchUp(SlotState)
    case waiting(SlotState)
    case extra(allDone: Bool)
}

// MARK: - Error banner

struct HomeErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            QIconView(icon: .warning, size: 18)
                .foregroundStyle(Theme.error)
                .padding(.top, 13)
            Text(message)
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
            RoundIconButton(icon: .close, label: "Fermer le message", action: onDismiss)
        }
        .padding(.leading, 18)
        .padding(.trailing, 4)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(Theme.errorSoft)
        )
    }
}

// MARK: - Lesson cards (carousel)

/// What sits under the text of a lesson card: the black CTA, or a static status for a finished lesson.
enum HomeCardFooter {
    case action(title: String, icon: QIcon, isDisabled: Bool, isDimmed: Bool, accessibilityLabel: String, perform: () -> Void)
    case status(text: String, icon: QIcon)
}

/// Big pastel card: type pill, title, duration, portrait on the right, CTA at the bottom.
struct HomeLessonCard: View {
    let pastel: Pastel
    let pillText: String
    var pillIcon: QIcon? = nil
    let title: String
    var subtitle: String? = nil
    let meta: String
    let footer: HomeCardFooter

    var body: some View {
        PastelCard(pastel) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(alignment: .top, spacing: 12) {
                    textColumn
                    PortraitSlot(imageName: "lesson-cover", width: 120, height: 160)
                }
                footerView
            }
        }
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            QPill(text: pillText, icon: pillIcon)
            CardTitle(title)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.onPastelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                QIconView(icon: .clock, size: 14)
                Text(meta)
                    .font(Theme.Font.caption(.semibold))
            }
            .foregroundStyle(Theme.onPastelSecondary)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var footerView: some View {
        switch footer {
        case .action(let title, let icon, let isDisabled, let isDimmed, let label, let perform):
            CardCTA(title: title, icon: icon, action: perform)
                .disabled(isDisabled)
                .opacity(isDimmed ? 0.45 : 1)
                .accessibilityLabel(label)
        case .status(let text, let icon):
            HStack(spacing: 0) {
                QPill(text: text, icon: icon)
                Spacer(minLength: 0)
            }
            .frame(minHeight: Theme.minTapSize)
        }
    }
}

/// Card of one of today's three slots.
struct HomeSlotCard: View {
    let slot: SlotState
    /// Total length of the sitting (every enabled subject).
    let minutes: Int
    let isStarting: Bool
    let onAction: () -> Void

    /// "Anglais ✓ · Arabe · Culture G"
    private var partsLine: String? {
        guard slot.parts.count > 1 else { return nil }
        return slot.parts.map { part in
            part.status == .completed ? "\(part.subject.shortName) ✓" : part.subject.shortName
        }.joined(separator: " · ")
    }

    private var lessonName: String {
        "Leçon \(FrenchLabels.slotPhrase(slot.slot))"
    }

    private func activeFooter(_ title: String, icon: QIcon) -> HomeCardFooter {
        .action(title: title, icon: icon, isDisabled: isStarting, isDimmed: false,
                accessibilityLabel: "\(title), \(lessonName.lowercased())", perform: onAction)
    }

    private var footer: HomeCardFooter {
        switch slot.status {
        case .completed:
            return .status(text: "Terminée", icon: .check)
        case .inProgress:
            return activeFooter("Reprendre", icon: .play)
        case .available:
            return activeFooter("Commencer", icon: .play)
        case .missed:
            return activeFooter("Rattraper", icon: .refresh)
        case .upcoming:
            return .action(title: "À \(slot.scheduledTime)", icon: .clock, isDisabled: true, isDimmed: true,
                           accessibilityLabel: "\(lessonName), disponible à \(slot.scheduledTime)", perform: onAction)
        }
    }

    var body: some View {
        HomeLessonCard(pastel: slot.slot.homePastel,
                       pillText: slot.slot.defaultSessionType.displayName,
                       title: lessonName,
                       subtitle: partsLine,
                       meta: "\(minutes) min · \(slot.scheduledTime)",
                       footer: footer)
    }
}

/// Card shown first when the 3 daily lessons are done (or when no slot exists): one more practice session.
struct HomeExtraCard: View {
    let allDone: Bool
    let minutes: Int
    let isStarting: Bool
    let onAction: () -> Void

    var body: some View {
        HomeLessonCard(pastel: .green,
                       pillText: SessionType.extra.displayName,
                       pillIcon: .sparkle,
                       title: allDone ? "Journée terminée" : "Réviser maintenant",
                       subtitle: allDone ? "Tes 3 leçons du jour sont faites." : "Une courte série d'exercices, à ton rythme.",
                       meta: "\(minutes) min",
                       footer: .action(title: "Leçon supplémentaire", icon: .play, isDisabled: isStarting, isDimmed: false,
                                       accessibilityLabel: "Leçon supplémentaire", perform: onAction))
    }
}

// MARK: - Resume

struct HomeResumeCard: View {
    let sessionName: String
    let isStarting: Bool
    let onResume: () -> Void

    var body: some View {
        PastelCard(.green) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 10) {
                    QPill(text: "Session en cours", icon: .hourglass)
                    CardTitle(sessionName)
                }
                .accessibilityElement(children: .combine)
                CardCTA(title: "Reprendre", icon: .play, action: onResume)
                    .disabled(isStarting)
                    .accessibilityLabel("Reprendre la session : \(sessionName)")
            }
        }
    }
}

// MARK: - Assessment

struct HomeAssessmentCard: View {
    let isStarting: Bool
    let onStart: () -> Void

    var body: some View {
        PastelCard(.yellow) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 10) {
                    QPill(text: "Quelques minutes", icon: .clock)
                    CardTitle("Test de consolidation")
                    Text("Un court test pour mesurer ce que tu retiens vraiment.")
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.onPastelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                CardCTA(title: "Passer le test", icon: .arrowRight, action: onStart)
                    .disabled(isStarting)
            }
        }
    }
}

// MARK: - Restrictions

struct HomeRestrictionCard: View {
    let activeSlots: [SessionSlot]
    let onUnlock: () -> Void

    private var message: String {
        if activeSlots.count == 1, let slot = activeSlots.first {
            return "Termine la leçon \(FrenchLabels.slotPhrase(slot)) pour les débloquer."
        }
        return "Termine ta leçon pour les débloquer."
    }

    var body: some View {
        PastelCard(fill: Theme.peach) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 10) {
                    QIconView(icon: .lock, size: 18)
                        .foregroundStyle(Theme.onInk)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Theme.ink))
                    CardTitle("Tes apps sont verrouillées")
                    Text(message)
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.onPastelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                Button("Déblocage d'urgence", action: onUnlock)
                    .buttonStyle(.secondary)
            }
        }
    }
}

// MARK: - Day sheet (calendar button)

/// Bottom sheet « Ma journée » : what to do in each lesson, for how long, and when apps get blocked.
struct HomeDaySheet: View {
    let day: LocalDay
    let slots: [SlotState]
    let schedule: DailySchedule
    /// Restrictions configured (switch on, apps chosen, authorization granted).
    let blocking: Bool
    let minutes: [Subject: Int]

    @Environment(\.dismiss) private var dismiss

    init(day: LocalDay, slots: [SlotState], schedule: DailySchedule, blocking: Bool, minutes: [Subject: Int]) {
        self.day = day
        self.slots = slots
        self.schedule = schedule
        self.blocking = blocking
        self.minutes = minutes
    }

    private var dateText: String {
        let text: String = day.startDate().formatted(
            .dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr")))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private var totalMinutes: Int {
        let perSlot = slots.first.map { slot in slot.parts.reduce(0) { $0 + (minutes[$1.subject] ?? 5) } } ?? 0
        return perSlot * slots.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header
                if slots.isEmpty {
                    EmptyStateView(icon: .calendar, pastel: .blue, message: "Aucune leçon n'est prévue pour le moment.")
                } else {
                    VStack(spacing: 10) {
                        ForEach(slots) { slot in
                            HomeDaySheetRow(slot: slot,
                                            window: schedule.restrictionWindow(for: slot.slot),
                                            blocking: blocking,
                                            minutes: minutes)
                        }
                    }
                    footer
                }
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .qSheet()
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: 4) {
                CardTitle("Ma journée")
                Text(totalMinutes > 0 ? "\(dateText) · \(totalMinutes) min au total" : dateText)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.secondaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Spacing.s)
            RoundIconButton(icon: .close, label: "Fermer", fill: Theme.background) { dismiss() }
        }
    }

    private var footer: some View {
        Text(blocking
             ? "À l'heure de chaque leçon, tes apps choisies sont bloquées jusqu'à ce que toutes les matières soient faites (ou jusqu'à la fin de la fenêtre). En plus, « Pratique libre » est dispo quand tu veux pour une 4e séance."
             : "Le blocage des apps est désactivé : active-le dans Réglages > Restreindre les apps. « Pratique libre » est dispo quand tu veux pour une 4e séance.")
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct HomeDaySheetRow: View {
    let slot: SlotState
    let window: (start: TimeOfDay, end: TimeOfDay)
    let blocking: Bool
    let minutes: [Subject: Int]

    private var plan: String {
        guard !slot.parts.isEmpty else { return slot.slot.defaultSessionType.displayName }
        return slot.parts.map { part in
            let mark = part.status == .completed ? " ✓" : ""
            return "\(part.subject.shortName) \(minutes[part.subject] ?? 5) min\(mark)"
        }.joined(separator: " · ")
    }

    private var blockingText: String? {
        guard blocking, slot.status != .completed else { return nil }
        if slot.restrictionActive { return "Apps bloquées jusqu'à \(window.end) au plus tard" }
        if slot.status == .upcoming { return "Apps bloquées de \(window.start) à \(window.end) si pas faite" }
        return nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            QIconView(icon: slot.status.homeIcon, size: 18)
                .foregroundStyle(Theme.ink)
                .frame(width: 42, height: 42)
                .background(Circle().fill(slot.status.homeIconFill))
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(slot.scheduledTime) · \(slot.slot.displayName)")
                        .font(Theme.Font.headline.monospacedDigit())
                        .foregroundStyle(Theme.primaryText)
                    Spacer(minLength: Theme.Spacing.s)
                    Text(slot.status.homeLabel)
                        .font(Theme.Font.caption(.semibold))
                        .foregroundStyle(Theme.ink)
                }
                Text(plan)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let blockingText {
                    Label(blockingText, systemImage: slot.restrictionActive ? "lock.fill" : "lock")
                        .font(Theme.Font.caption.monospacedDigit())
                        .foregroundStyle(slot.restrictionActive ? Theme.error : Theme.tertiaryText)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.background)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Subject block (one per subject of the slot shown)

/// « 🇬🇧 Anglais · 5 min · À faire » with its button. Each subject is started alone and the learner comes back
/// home at the end; the slot is done (apps unblocked) when every block is.
struct HomeSubjectBlock: View {
    let subject: Subject
    let status: SlotStatus
    let scheduledTime: TimeOfDay
    let minutes: Int
    let upNext: String?
    let isStarting: Bool
    let onStart: () -> Void
    let onPractice: () -> Void

    private var pastel: Pastel {
        switch subject {
        case .english: return .blue
        case .arabic: return .yellow
        case .culture: return .pink
        }
    }

    private var statusText: String {
        switch status {
        case .completed: return "Fait ✓"
        case .inProgress: return "En cours"
        case .available: return "À faire"
        case .missed: return "À rattraper"
        case .upcoming: return "À \(scheduledTime)"
        }
    }

    var body: some View {
        PastelCard(pastel, padding: 18) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(alignment: .center, spacing: Theme.Spacing.m) {
                    Text(subject.emoji)
                        .font(.system(size: 34))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        CardTitle(subject.displayName)
                        Text("\(minutes) min · \(statusText)")
                            .font(Theme.Font.callout(.semibold))
                            .foregroundStyle(Theme.onPastelSecondary)
                    }
                    Spacer(minLength: 0)
                    if status == .completed {
                        QIconView(icon: .check, size: 18)
                            .foregroundStyle(Theme.onInk)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Theme.ink))
                            .accessibilityHidden(true)
                    }
                }
                if let upNext, status != .completed {
                    Text("Prochaine leçon : \(upNext)")
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.onPastelSecondary)
                        .lineLimit(2)
                }
                button
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var button: some View {
        switch status {
        case .completed:
            Button("S'entraîner encore", action: onPractice)
                .buttonStyle(.secondary)
                .disabled(isStarting)
        case .upcoming:
            Button("Disponible vers \(scheduledTime)", action: onStart)
                .buttonStyle(.secondary)
                .disabled(true)
        case .inProgress:
            Button("Reprendre", action: onStart)
                .buttonStyle(.primary)
                .disabled(isStarting)
        case .available, .missed:
            Button(status == .missed ? "Rattraper" : "Commencer", action: onStart)
                .buttonStyle(.primary)
                .disabled(isStarting)
        }
    }
}

/// Neutral information line (not an error), dismissable.
struct HomeInfoBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            QIconView(icon: .info, size: 18)
                .foregroundStyle(Theme.ink)
                .padding(.top, 1)
            Text(message)
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                QIconView(icon: .close, size: 14)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: Theme.minTapSize, height: Theme.minTapSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fermer")
        }
        .padding(.leading, Theme.Spacing.m)
        .card()
    }
}

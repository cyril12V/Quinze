import SwiftUI
import LearningCore

/// Top of the home: title, points towards the next title, streak.
struct NofriGameStrip: View {
    let points: Int
    let streakDays: Int
    var onOpenLadder: () -> Void = {}

    var body: some View {
        let rank = NofriGame.rank(points: points)
        let next = NofriGame.nextRank(points: points)
        Button(action: onOpenLadder) {
            PastelCard(.yellow, padding: 18) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack(alignment: .center, spacing: Theme.Spacing.m) {
                        Text(rank.emoji)
                            .font(.system(size: 38))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ton titre")
                                .font(Theme.Font.caption(.semibold))
                                .foregroundStyle(Theme.onPastelSecondary)
                            CardTitle(rank.title)
                        }
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("🔥 \(streakDays)")
                                .font(Theme.Font.headline(.bold))
                                .foregroundStyle(Theme.ink)
                            Text(streakDays > 1 ? "jours d'affilée" : "jour d'affilée")
                                .font(Theme.Font.caption(.medium))
                                .foregroundStyle(Theme.onPastelSecondary)
                        }
                    }
                    QProgressBar(value: NofriGame.progress(points: points), height: 8)
                    Text(next.map { "\(points) points · encore \($0.minPoints - points) pour devenir \($0.title)" }
                         ?? "\(points) points · tu as atteint le dernier titre")
                        .font(Theme.Font.caption(.medium))
                        .foregroundStyle(Theme.onPastelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .buttonStyle(.press)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Affiche tous les titres")
    }
}

/// « Aujourd'hui dans l'Église » : Coptic date, Adam or Watos day, fast. In the evening the Church already enters
/// the next day: its theotokia is the one of tomorrow.
struct TodayInChurchCard: View {
    let date: Date

    private var calendar: Calendar { .current }
    private var coptic: CopticCalendar.CopticDate { CopticCalendar.copticDate(for: date, calendar: calendar) }
    private var isEvening: Bool { calendar.component(.hour, from: date) >= 18 }
    private var tomorrow: Date { calendar.date(byAdding: .day, value: 1, to: date) ?? date }
    private var tomorrowName: String { CopticCalendar.weekdayName(for: tomorrow, calendar: calendar) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            QSectionTitle("Aujourd'hui dans l'Église")
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Text(coptic.formatted)
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.primaryText)
                Text(coptic.monthNameArabic)
                    .font(.system(.callout))
                    .foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 0)
            }
            line(icon: "music.note",
                 text: "Jour \(CopticCalendar.tune(for: date, calendar: calendar).rawValue) (\(CopticCalendar.weekdayName(for: date, calendar: calendar)))")
            if isEvening {
                line(icon: "moon.stars",
                     text: "Ce soir, l'Église entre déjà dans le \(tomorrowName) : on prie la théotokie du \(tomorrowName) (jour \(CopticCalendar.tune(for: tomorrow, calendar: calendar).rawValue)).")
            }
            line(icon: "leaf", text: CopticCalendar.fast(on: date, calendar: calendar) ?? "Pas de jeûne aujourd'hui")
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }

    private func line(icon: String, text: String) -> some View {
        Label {
            Text(text)
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(Theme.ink)
        }
    }
}

/// « Continuer le chemin » and « Défi du jour » : what the learner can do outside the blocked slots.
struct NofriActionsBlock: View {
    let nextLessonTitle: String?
    let lessonsDone: Int
    let lessonsTotal: Int
    let challengeDone: Bool
    let hasLearned: Bool
    let isStarting: Bool
    let onContinue: () -> Void
    let onChallenge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.card) {
            PastelCard(.blue, padding: 20) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    HStack(spacing: Theme.Spacing.s) {
                        QPill(text: "Le chemin", icon: .path)
                        Spacer(minLength: 0)
                        Text("\(lessonsDone)/\(lessonsTotal)")
                            .font(Theme.Font.caption(.semibold))
                            .foregroundStyle(Theme.onPastelSecondary)
                    }
                    CardTitle(nextLessonTitle.map { "Prochaine leçon : \($0)" } ?? "Tu as fini le chemin. Entretiens ta mémoire.")
                    Text("Une carte, une question, et on avance. Il faut 90 % pour valider : une erreur revient jusqu'à ce que ce soit acquis.")
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.onPastelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Continuer le chemin", action: onContinue)
                        .buttonStyle(.primary)
                        .disabled(isStarting)
                }
            }
            PastelCard(challengeDone ? .green : .pink, padding: 20) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    HStack(spacing: Theme.Spacing.s) {
                        QPill(text: "Défi du jour", icon: .target)
                        Spacer(minLength: 0)
                        Text("+\(NofriGame.challengeBonus) points")
                            .font(Theme.Font.caption(.semibold))
                            .foregroundStyle(Theme.onPastelSecondary)
                    }
                    CardTitle(challengeDone ? "Défi relevé aujourd'hui" : "Tout ce que tu sais, en quelques questions")
                    Text(hasLearned
                         ? "Un mélange de tout ce que tu as appris, sans aide. C'est lui qui fait rester les choses."
                         : "Fais d'abord ta première leçon : le défi mélange ce que tu as déjà appris.")
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.onPastelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(challengeDone ? "Rejouer" : "Relever le défi", action: onChallenge)
                        .buttonStyle(.secondary)
                        .disabled(isStarting || !hasLearned)
                }
            }
        }
    }
}

/// The ladder of titles (sheet).
struct NofriLadderSheet: View {
    let points: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QScreen {
                VStack(alignment: .leading, spacing: Theme.Spacing.card) {
                    ScreenTitle("Les titres")
                    ScreenSubtitle("10 points par bonne réponse, \(NofriGame.lessonBonus) par leçon validée, \(NofriGame.flawlessBonus) pour un sans-faute, \(NofriGame.examBonus) par examen réussi, \(NofriGame.challengeBonus) par défi du jour.")
                    ForEach(Array(NofriGame.ranks.enumerated()), id: \.offset) { _, rank in
                        let reached = points >= rank.minPoints
                        HStack(spacing: Theme.Spacing.m) {
                            Text(rank.emoji)
                                .font(.system(size: 28))
                                .opacity(reached ? 1 : 0.35)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rank.title)
                                    .font(Theme.Font.headline)
                                    .foregroundStyle(reached ? Theme.primaryText : Theme.secondaryText)
                                Text("\(rank.minPoints) points")
                                    .font(Theme.Font.caption(.medium))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Spacer(minLength: 0)
                            if reached {
                                QIconView(icon: .check, size: 16)
                                    .foregroundStyle(Theme.ink)
                            } else {
                                QIconView(icon: .lock, size: 16)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                        .padding(Theme.Spacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(rank.title), \(rank.minPoints) points, \(reached ? "atteint" : "pas encore atteint")")
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}

/// End of a session: the points won and the fiches unlocked.
struct NofriRewardCard: View {
    let points: Int
    let fiches: [String]

    var body: some View {
        PastelCard(.yellow, padding: 18) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.s) {
                    Text("✨")
                        .accessibilityHidden(true)
                    CardTitle("+\(points) points")
                }
                if !fiches.isEmpty {
                    Text(fiches.count > 1 ? "Nouvelles fiches dans ta collection :" : "Nouvelle fiche dans ta collection :")
                        .font(Theme.Font.callout(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(fiches.joined(separator: " · "))
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.onPastelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

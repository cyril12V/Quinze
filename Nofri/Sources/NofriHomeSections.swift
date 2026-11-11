import SwiftUI
import LearningCore

/// The main card of the home: the one thing to do now. Burgundy, with a gold button.
struct NofriHeroCard: View {
    let kicker: String
    let title: String
    let detail: String?
    let buttonTitle: String
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(kicker.uppercased())
                .font(Theme.Font.caption(.bold))
                .tracking(0.8)
                .foregroundStyle(Theme.onBurgundy.opacity(0.8))
            Text(title)
                .font(Theme.Font.jakarta(24, .bold, relativeTo: .title2))
                .foregroundStyle(Theme.onBurgundy)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.onBurgundy.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: action) {
                Text(buttonTitle)
                    .font(Theme.Font.jakarta(16, .bold, relativeTo: .headline))
                    .foregroundStyle(Theme.onGold)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.gold))
                    .opacity(isBusy ? 0.6 : 1)
            }
            .buttonStyle(.press)
            .disabled(isBusy)
            .padding(.top, Theme.Spacing.s)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).fill(Theme.burgundy))
    }
}

/// Title, points towards the next title, streak.
struct NofriGameStrip: View {
    let points: Int
    let streakDays: Int
    var onOpenLadder: () -> Void = {}

    var body: some View {
        let rank = NofriGame.rank(points: points)
        let next = NofriGame.nextRank(points: points)
        Button(action: onOpenLadder) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    Text("\(rank.emoji) \(rank.title)")
                        .font(Theme.Font.jakarta(20, .bold, relativeTo: .title3))
                        .foregroundStyle(Theme.primaryText)
                    Spacer(minLength: 0)
                    Text("\(points) points")
                        .font(Theme.Font.caption(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                QProgressBar(value: NofriGame.progress(points: points), height: 8, fill: Theme.yellowStrong)
                Text(next.map { "Encore \($0.minPoints - points) points pour devenir \($0.title)" }
                     ?? "Tu as atteint le dernier titre")
                    .font(Theme.Font.caption(.medium))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card()
        }
        .buttonStyle(.press)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Affiche tous les titres")
    }
}

/// Two small cards side by side: the daily challenge and the collection.
struct NofriShortcuts: View {
    let challengeDone: Bool
    let hasLearned: Bool
    let unlocked: Int
    let total: Int
    let isBusy: Bool
    let onChallenge: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Button(action: onChallenge) {
                tile(label: "Défi du jour",
                     value: challengeDone ? "Relevé ✓" : "10 questions",
                     detail: hasLearned ? (challengeDone ? "Tu peux rejouer" : "+\(NofriGame.challengeBonus) points") : "Après ta 1re leçon")
            }
            .buttonStyle(.press)
            .disabled(isBusy || !hasLearned)
            .accessibilityHint("Lance un mélange de tout ce que tu as appris")
            tile(label: "Collection", value: "\(unlocked) / \(total)", detail: "fiches débloquées")
        }
    }

    private func tile(label: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(Theme.Font.caption(.bold))
                .tracking(0.6)
                .foregroundStyle(Theme.secondaryText)
            Text(value)
                .font(Theme.Font.jakarta(20, .bold, relativeTo: .title3))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(Theme.Font.caption(.medium))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .card()
        .accessibilityElement(children: .combine)
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
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Text("AUJOURD'HUI DANS L'ÉGLISE")
                    .font(Theme.Font.caption(.bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 0)
                Text(coptic.monthNameArabic)
                    .font(.system(.footnote))
                    .foregroundStyle(Theme.secondaryText)
            }
            Text(coptic.formatted)
                .font(Theme.Font.jakarta(20, .bold, relativeTo: .title3))
                .foregroundStyle(Theme.primaryText)
            line(icon: "music.note",
                 text: "Jour \(CopticCalendar.tune(for: date, calendar: calendar).rawValue) (\(CopticCalendar.weekdayName(for: date, calendar: calendar)))")
            if isEvening {
                line(icon: "moon.stars",
                     text: "Ce soir, l'Église entre déjà dans le \(tomorrowName) : on prie la théotokie du \(tomorrowName) (jour \(CopticCalendar.tune(for: tomorrow, calendar: calendar).rawValue)).")
            }
            line(icon: "leaf", text: CopticCalendar.fast(on: date, calendar: calendar) ?? "Pas de jeûne aujourd'hui")
        }
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

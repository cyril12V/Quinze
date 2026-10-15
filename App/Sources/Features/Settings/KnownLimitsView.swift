import SwiftUI

/// « Limites connues » : what Quinze can and cannot guarantee, stated plainly.
/// A calm text page: big title, short subtitle, three white cards.
struct KnownLimitsView: View {
    private struct Limit: Identifiable, Sendable {
        let id: Int
        let title: String
        let detail: String
    }

    private struct LimitGroup: Identifiable, Sendable {
        let id: Int
        let title: String
        let limits: [Limit]
    }

    private static let limits: [Limit] = [
        Limit(id: 0, title: "Temps d'écran peut être retiré",
              detail: "iOS permet à toute personne de retirer l'autorisation dans Réglages > Temps d'écran. Quinze le détecte et te prévient, mais ne peut pas l'empêcher."),
        Limit(id: 1, title: "Les restrictions finissent toujours",
              detail: "Les apps sont débloquées à la fin de l'échéance de sécurité, même si la leçon n'est pas faite. Le déblocage d'urgence reste disponible à tout moment dans les réglages."),
        Limit(id: 2, title: "Certaines choses ne se bloquent pas",
              detail: "Le Téléphone, les appels d'urgence et les réglages de l'iPhone ne peuvent pas être restreints."),
        Limit(id: 3, title: "Simulateur et appareils sans autorisation",
              detail: "Temps d'écran n'est pas disponible sur le simulateur ni si l'autorisation d'Apple manque : les leçons fonctionnent, sans blocage d'apps."),
        Limit(id: 4, title: "Les notifications sont des rappels",
              detail: "Le blocage ne dépend jamais d'une notification. Si tu les désactives, tes leçons et tes restrictions continuent de fonctionner."),
        Limit(id: 5, title: "Hors connexion",
              detail: "Tu peux faire tes leçons sans réseau. Les réponses libres incertaines sont corrigées plus tard, et le professeur IA propose alors des explications enregistrées dans l'application. Ta progression est synchronisée au retour du réseau."),
        Limit(id: 6, title: "Le professeur IA peut se tromper",
              detail: "Il s'appuie sur le contenu validé de l'application, mais reste une aide : en cas de doute, fie-toi à la règle affichée. Un quota quotidien limite son usage."),
        Limit(id: 7, title: "Pas de niveau officiel",
              detail: "L'évaluation initiale et les tests de consolidation donnent un point de départ et un suivi. Ils ne correspondent à aucun niveau certifié (CECRL) et ne remplacent pas un examen."),
        Limit(id: 8, title: "Prononciation",
              detail: "L'audio utilise la voix de synthèse d'iOS (anglais britannique). Sa qualité dépend des voix installées sur ton iPhone."),
        Limit(id: 9, title: "Leçon manquée",
              detail: "Après l'échéance, une leçon non faite reste disponible pour t'entraîner, mais elle ne compte pas comme faite à l'heure prévue."),
        Limit(id: 10, title: "Plusieurs appareils",
              detail: "Si la même donnée est modifiée sur deux appareils, la modification la plus récente est conservée. Le choix des apps à bloquer reste propre à chaque iPhone."),
        Limit(id: 11, title: "Langues",
              detail: "Seul l'anglais est disponible pour l'instant. L'arabe arrive bientôt.")
    ]

    private static let groups: [LimitGroup] = [
        LimitGroup(id: 0, title: "Temps d'écran et rappels", limits: Array(limits[0...4])),
        LimitGroup(id: 1, title: "Apprentissage", limits: Array(limits[5...8])),
        LimitGroup(id: 2, title: "Au quotidien", limits: Array(limits[9...11]))
    ]

    var body: some View {
        QScreen {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    ScreenTitle("Ce que Quinze ne peut pas garantir")
                    ScreenSubtitle("Nous préférons te le dire clairement plutôt que de promettre l'impossible.")
                }
                ForEach(Self.groups) { group in
                    section(group)
                }
            }
        }
        .navigationTitle("Limites connues")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func section(_ group: LimitGroup) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(group.title)
                .font(Theme.Font.caption(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, Theme.Spacing.xs)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(group.limits) { limit in
                    row(limit)
                    if limit.id != group.limits.last?.id { FlowDivider() }
                }
            }
            .padding(.horizontal, Theme.Spacing.page)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .fill(Theme.surface)
            )
        }
    }

    private func row(_ limit: Limit) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(limit.title)
                .font(Theme.Font.headline)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(limit.detail)
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.secondaryText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Spacing.m)
        .accessibilityElement(children: .combine)
    }
}

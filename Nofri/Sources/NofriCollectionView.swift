import SwiftUI
import LearningCore

/// The collection: every fiche of the course, by family. A fiche is unlocked when its lesson is validated.
struct NofriCollectionView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var fiches: [NofriFiche] = []
    @State private var family: NofriCollection?
    @State private var opened: NofriFiche?

    private let columns = [GridItem(.flexible(), spacing: Theme.Spacing.s), GridItem(.flexible(), spacing: Theme.Spacing.s)]

    var body: some View {
        QScreen {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                VStack(alignment: .leading, spacing: 10) {
                    ScreenTitle("Ta collection")
                    ScreenSubtitle(subtitle)
                }
                if fiches.isEmpty {
                    EmptyStateView(icon: .star, pastel: .yellow,
                                   message: "Chaque leçon validée débloque des fiches : saints, conciles, hérésies, lieux…")
                } else {
                    familyChips
                    ForEach(shownFamilies) { item in
                        section(item)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { reload() }
        .refreshable { await env.churchStore.refresh(); reload() }
        .sheet(item: $opened) { fiche in
            NofriFicheSheet(fiche: fiche)
                .presentationDetents([.medium, .large])
        }
    }

    private var unlockedCount: Int { fiches.filter(\.unlocked).count }

    private var subtitle: String {
        fiches.isEmpty ? "Tes fiches apparaîtront ici." : "\(unlockedCount) fiches sur \(fiches.count) débloquées."
    }

    private var families: [NofriCollection] {
        NofriCollection.allCases.filter { item in fiches.contains { $0.family == item } }
    }

    private var shownFamilies: [NofriCollection] {
        family.map { [$0] } ?? families
    }

    private var familyChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.s) {
                FilterChip(title: "Tout", isSelected: family == nil) { family = nil }
                ForEach(families) { item in
                    FilterChip(title: "\(item.emoji) \(item.title)", isSelected: family == item) { family = item }
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, Theme.Spacing.page, for: .scrollContent)
        .padding(.horizontal, -Theme.Spacing.page)
    }

    private func section(_ item: NofriCollection) -> some View {
        let list = fiches.filter { $0.family == item }
        let unlocked = list.filter(\.unlocked).count
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                QSectionTitle("\(item.emoji) \(item.title)")
                Spacer(minLength: 0)
                Text("\(unlocked)/\(list.count)")
                    .font(Theme.Font.caption(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            LazyVGrid(columns: columns, spacing: Theme.Spacing.s) {
                ForEach(list) { fiche in
                    tile(fiche, pastel: item.pastel)
                }
            }
        }
    }

    @ViewBuilder private func tile(_ fiche: NofriFiche, pastel: Pastel) -> some View {
        if fiche.unlocked {
            Button { opened = fiche } label: {
                PastelCard(pastel, radius: Theme.Radius.small, padding: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fiche.item.word)
                            .font(Theme.Font.callout(.semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(fiche.item.translation)
                            .font(Theme.Font.caption(.medium))
                            .foregroundStyle(Theme.onPastelSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                }
            }
            .buttonStyle(.press)
            .accessibilityLabel("\(fiche.item.word), \(fiche.item.translation)")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                QIconView(icon: .lock, size: 14)
                    .foregroundStyle(Theme.secondaryText)
                Text(fiche.lessonTitle.map { "Leçon : \($0)" } ?? "À débloquer")
                    .font(Theme.Font.caption(.medium))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .card()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Fiche à débloquer\(fiche.lessonTitle.map { ", leçon \($0)" } ?? "")")
        }
    }

    private func reload() {
        fiches = env.collectionFiches()
    }
}

/// Detail of one fiche.
struct NofriFicheSheet: View {
    let fiche: NofriFiche

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                QPill(text: "\(fiche.family.emoji) \(fiche.family.title)", fill: fiche.family.pastel.color)
                ScreenTitle(fiche.item.word)
                Text(fiche.item.translation)
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(fiche.item.explanation)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.primaryText)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(fiche.item.examples.enumerated()), id: \.offset) { _, example in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(example.text)
                            .font(Theme.Font.body(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text(example.translation)
                            .font(Theme.Font.callout)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(Theme.Spacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
                if let lesson = fiche.lessonTitle {
                    Text("Débloquée par la leçon « \(lesson) ».")
                        .font(Theme.Font.caption(.medium))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(Theme.Spacing.page)
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

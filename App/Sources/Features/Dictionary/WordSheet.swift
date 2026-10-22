import SwiftUI
import LearningCore

/// Dictionary card of one word, in a bottom sheet.
struct WordSheet: View {
    let item: DictionaryItem

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var isTracked = false
    @State private var isTracking = false
    @State private var tutorRequest: TutorRequest?

    init(item: DictionaryItem) {
        self.item = item
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                topRow
                header
                translations
                explanation
                examples
                confusions
                forms
                actions
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background.ignoresSafeArea())
        .qSheet()
        .presentationDetents([.medium, .large])
        .sheet(item: $tutorRequest) { request in
            TutorSheet(subject: request.subject)
        }
        .task { isTracked = env.store.isWordTracked(item.id) }
    }

    // MARK: Sections

    /// Part of speech on the left, close button on the right.
    private var topRow: some View {
        HStack(spacing: Theme.Spacing.s) {
            QPill(text: item.partOfSpeechLabel, fill: Theme.surface, foreground: Theme.ink)
            Spacer(minLength: Theme.Spacing.s)
            RoundIconButton(icon: .close, label: "Fermer") { dismiss() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            StudiedText(text: item.word, size: .hero)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            if let reading = item.reading {
                Text(reading)
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityLabel("Se lit : \(reading)")
            }
            HStack(spacing: Theme.Spacing.xs) {
                if let ipa = item.ipa, !ipa.isEmpty {
                    Text(ipa)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityLabel("Prononciation : \(ipa)")
                        .padding(.trailing, Theme.Spacing.xs)
                }
                QSpeakerButton(text: item.word)
                QSpeakerButton(text: item.word, slow: true)
                Spacer(minLength: 0)
            }
        }
    }

    private var translations: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(item.translation)
                .font(Theme.Font.title)
                .tracking(Theme.Tracking.title)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let others = item.otherTranslations, !others.isEmpty {
                Text("Aussi : " + others.joined(separator: ", "))
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var explanation: some View {
        if !item.explanation.isEmpty {
            Text(item.explanation)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.primaryText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Examples in a blue pastel card.
    @ViewBuilder private var examples: some View {
        if !item.examples.isEmpty {
            PastelCard(.blue, padding: 20) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    QSectionTitle("Exemples")
                    ForEach(Array(item.examples.enumerated()), id: \.offset) { _, example in
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            TappableSentenceView(text: example.text, languageCode: env.store.learningLanguageCode)
                                .font(Theme.Font.body(.semibold))
                                .foregroundStyle(Theme.ink)
                            if let transliteration = example.transliteration, !transliteration.isEmpty {
                                Text(transliteration)
                                    .font(Theme.Font.callout)
                                    .italic()
                                    .foregroundStyle(Theme.onPastelSecondary)
                            }
                            Text(example.translation)
                                .font(Theme.Font.callout)
                                .foregroundStyle(Theme.onPastelSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    /// « Ne pas confondre » in a yellow pastel card.
    @ViewBuilder private var confusions: some View {
        if let confusions = item.confusions, !confusions.isEmpty {
            PastelCard(.yellow, padding: 20) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    QSectionTitle("Ne pas confondre")
                    ForEach(Array(confusions.enumerated()), id: \.offset) { _, confusion in
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(confusion.word)
                                .font(Theme.Font.body(.semibold))
                                .foregroundStyle(Theme.ink)
                            Text(confusion.note)
                                .font(Theme.Font.callout)
                                .foregroundStyle(Theme.onPastelSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    /// Forms (past, plural…) in a white card.
    @ViewBuilder private var forms: some View {
        let rows: [(label: String, value: String)] = formRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                QSectionTitle("Formes")
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.label)
                            .font(Theme.Font.callout)
                            .foregroundStyle(Theme.secondaryText)
                        Spacer(minLength: Theme.Spacing.m)
                        Text(row.value)
                            .arabicAware(row.value, .title2)
                            .font(Theme.Font.body(.medium))
                            .foregroundStyle(Theme.primaryText)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .card()
        }
    }

    private var formRows: [(label: String, value: String)] {
        guard let forms = item.forms, !forms.isEmpty else { return [] }
        var rows: [(label: String, value: String)] = []
        var used: Set<String> = []
        let shapeLabels = GameQuestionFactory.shapeKeys.map { (key: $0.key, label: $0.label) }
        for entry in FrenchLabels.formLabels + shapeLabels {
            if let value = forms[entry.key], !value.isEmpty {
                rows.append((label: entry.label, value: value))
                used.insert(entry.key)
            }
        }
        for key in forms.keys.sorted() where !used.contains(key) {
            if let value = forms[key], !value.isEmpty {
                rows.append((label: key, value: value))
            }
        }
        return rows
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.s + 2) {
            if isTracked {
                QCallout(systemImage: "checkmark.circle", tint: Theme.ink, fill: Pastel.green.soft) {
                    Text("Dans tes révisions")
                        .font(Theme.Font.body(.semibold))
                        .foregroundStyle(Theme.ink)
                }
                .accessibilityElement(children: .combine)
            } else {
                if item.unitId != nil {
                    Button("Apprendre ce mot", action: track)
                        .buttonStyle(.primary)
                        .disabled(isTracking)
                }
            }
            Button("Explique-moi") {
                tutorRequest = TutorRequest(subject: .word(item.word, sentence: nil))
            }
            .buttonStyle(.secondary)
        }
        .padding(.top, Theme.Spacing.s)
    }

    // MARK: Actions

    private func track() {
        guard !isTracking else { return }
        isTracking = true
        Task { @MainActor in
            await env.store.trackWord(item.id)
            isTracked = env.store.isWordTracked(item.id)
            isTracking = false
        }
    }
}

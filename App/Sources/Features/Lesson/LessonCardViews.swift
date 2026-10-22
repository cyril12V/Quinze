import SwiftUI
import LearningCore

// MARK: - Rule card

/// Rule card: one big blue pastel card with the rule, then « Explique-moi » and the pinned « Continuer ».
struct LessonRuleCard: View {
    let unit: LearningUnit
    let isBusy: Bool
    let onContinue: () -> Void
    let onExplain: () -> Void

    @Environment(AppEnvironment.self) private var env

    init(unit: LearningUnit, isBusy: Bool, onContinue: @escaping () -> Void, onExplain: @escaping () -> Void) {
        self.unit = unit
        self.isBusy = isBusy
        self.onContinue = onContinue
        self.onExplain = onExplain
    }

    var body: some View {
        LessonScaffold {
            VStack(alignment: .leading, spacing: Theme.Spacing.card) {
                ruleCard
                    .qAppear(0)
                Button("Explique-moi", action: onExplain)
                    .buttonStyle(.secondary)
                    .qAppear(1)
            }
        } footer: {
            Button("Continuer", action: onContinue)
                .buttonStyle(.primary)
                .disabled(isBusy)
        }
    }

    private var ruleCard: some View {
        PastelCard(.blue, padding: 20) {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header
                if let rule = unit.rule {
                    ruleContent(rule)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s + 2) {
            QPill(text: "Règle", icon: .book)
            CardTitle(unit.title)
                .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder private func ruleContent(_ rule: GrammarRule) -> some View {
        Text(rule.summary)
            .font(Theme.Font.headline)
            .foregroundStyle(Theme.ink)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)

        if let pattern = rule.pattern, !pattern.isEmpty {
            patternView(pattern)
        }

        if !rule.examples.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                QSectionTitle("Exemples")
                ForEach(Array(rule.examples.enumerated()), id: \.offset) { _, example in
                    exampleRow(example)
                }
            }
        }

        if !rule.commonErrors.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s + 2) {
                QSectionTitle("Erreurs fréquentes")
                ForEach(Array(rule.commonErrors.enumerated()), id: \.offset) { _, error in
                    errorRow(error)
                }
            }
        }

        if let tip = rule.tip, !tip.isEmpty {
            QCallout(systemImage: "lightbulb", tint: Theme.ink, fill: Theme.warningSoft) {
                Text(tip)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Astuce : \(tip)")
        }

        if !rule.explanation.isEmpty {
            DisclosureGroup("Voir l'explication complète") {
                Text(rule.explanation)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Theme.Spacing.s)
            }
            .font(Theme.Font.callout(.semibold))
            .foregroundStyle(Theme.ink)
            .tint(Theme.ink)
        }
    }

    /// White capsule when the pattern fits on one line, white rounded block otherwise.
    private func patternView(_ pattern: String) -> some View {
        ViewThatFits(in: .horizontal) {
            patternText(pattern)
                .fixedSize(horizontal: true, vertical: false)
                .background(Capsule().fill(Theme.surface))
            patternText(pattern)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(Theme.surface))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Schéma : \(pattern)")
    }

    private func patternText(_ pattern: String) -> some View {
        Text(pattern)
            .font(Theme.Font.body(.semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m - 2)
    }

    private func exampleRow(_ example: Example) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                TappableSentenceView(text: example.text, languageCode: env.store.learningLanguageCode)
                    .font(Theme.Font.body(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(example.translation)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.onPastelSecondary)
            }
            Spacer(minLength: 0)
            QSpeakerButton(text: example.text)
        }
    }

    private func errorRow(_ error: CommonError) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs + 2) {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                QIconView(icon: .close, size: 16)
                    .foregroundStyle(Theme.error)
                    .padding(.top, 2)
                Text(error.wrong).arabicAware(error.wrong, .title3)
                    .strikethrough(true, color: Theme.error)
                    .foregroundStyle(Theme.error)
            }
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                QIconView(icon: .check, size: 16)
                    .foregroundStyle(Theme.success)
                    .padding(.top, 2)
                Text(error.right).arabicAware(error.right, .title3)
                    .foregroundStyle(Theme.success)
            }
            Text(error.why)
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.secondaryText)
        }
        .font(Theme.Font.body)
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.surface)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Faux : \(error.wrong). Correct : \(error.right). \(error.why)")
    }
}

// MARK: - Word card

/// Word card: one big pink pastel card (word, pronunciation, translation, example).
struct LessonWordCard: View {
    let unit: LearningUnit
    let isBusy: Bool
    let onContinue: () -> Void

    @Environment(AppEnvironment.self) private var env

    init(unit: LearningUnit, isBusy: Bool, onContinue: @escaping () -> Void) {
        self.unit = unit
        self.isBusy = isBusy
        self.onContinue = onContinue
    }

    private var entry: DictionaryItem? {
        env.store.dictionaryEntry(for: unit.title)
    }

    private var partOfSpeech: String? {
        let raw: String = unit.partOfSpeech ?? entry?.partOfSpeech ?? ""
        return raw.isEmpty ? nil : FrenchLabels.partOfSpeech(raw)
    }

    var body: some View {
        LessonScaffold {
            wordCard
                .qAppear(0)
        } footer: {
            Button("Continuer", action: onContinue)
                .buttonStyle(.primary)
                .disabled(isBusy)
        }
    }

    private var wordCard: some View {
        PastelCard(.pink, padding: 22) {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                pills
                wordHeader
                translationBlock
                exampleBlock
            }
        }
    }

    private var pills: some View {
        QFlowLayout() {
            QPill(text: "Nouveau mot", icon: .sparkle)
            if let partOfSpeech {
                QPill(text: partOfSpeech)
            }
        }
    }

    private var wordHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(unit.title).arabicAware(unit.title, .largeTitle)
                .font(Theme.Font.display)
                .tracking(Theme.Tracking.display)
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: Theme.Spacing.xs) {
                if let ipa = entry?.ipa, !ipa.isEmpty {
                    Text(ipa)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.onPastelSecondary)
                        .accessibilityLabel("Prononciation : \(ipa)")
                        .padding(.trailing, Theme.Spacing.xs)
                }
                if let transliteration = entry?.transliteration, !transliteration.isEmpty {
                    Text(transliteration)
                        .font(Theme.Font.headline)
                        .foregroundStyle(Theme.onPastelSecondary)
                        .accessibilityLabel("Se lit : \(transliteration)")
                        .padding(.trailing, Theme.Spacing.xs)
                }
                QSpeakerButton(text: unit.title)
                QSpeakerButton(text: unit.title, slow: true)
                Spacer(minLength: 0)
            }
        }
    }

    private var translationBlock: some View {
        Text(unit.translation ?? entry?.translation ?? "")
            .font(Theme.Font.title)
            .tracking(Theme.Tracking.title)
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var exampleBlock: some View {
        if let example = entry?.examples.first {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    TappableSentenceView(text: example.text, languageCode: env.store.learningLanguageCode)
                        .font(example.text.containsArabic ? .system(.title2) : Theme.Font.headline)
                        .foregroundStyle(Theme.primaryText)
                    if let transliteration = example.transliteration, !transliteration.isEmpty {
                        Text(transliteration)
                            .font(Theme.Font.callout)
                            .italic()
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Text(example.translation)
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 0)
                QSpeakerButton(text: example.text)
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.surface)
            )
        }
    }
}

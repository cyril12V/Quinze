import SwiftUI
import LearningCore

// « Séries » mode of the dictionary: one series of words per lesson, in the course order. Any series can be
// opened (the ones of lessons not reached yet are marked « À venir »). A series is a fast flow: flashcards,
// a 5-question quiz, then « Ajouter les mots à mes révisions » so that the words come back by spaced repetition.

// MARK: - List

struct WordSeriesListView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var opened: WordSeries?

    init() {}

    var body: some View {
        let store: LearningStore = env.store
        let series: [WordSeries] = store.wordSeries()
        content(series, store: store)
            .fullScreenCover(item: $opened) { entry in
                flow(for: entry)
            }
    }

    private func flow(for entry: WordSeries) -> some View {
        let subject: Subject = Subject.of(entry.lesson.id)
        let store: LearningStore = env.study.store(subject)
        let words: [DictionaryItem] = store.wordGamePools(series: store.wordSeries()).all
        return WordSeriesFlowView(series: entry, subject: subject, allWords: words)
    }

    @ViewBuilder
    private func content(_ series: [WordSeries], store: LearningStore) -> some View {
        if series.isEmpty {
            EmptyStateView(icon: .book, pastel: .blue,
                           message: "Les séries de mots apparaîtront ici dès que les leçons seront prêtes.")
                .qAppear(0)
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.card) {
                ScreenSubtitle(intro(for: store.subject))
                hero(series, store: store)
                QSectionTitle("Toutes les séries")
                    .padding(.top, Theme.Spacing.s)
                ForEach(series) { entry in
                    WordSeriesRow(series: entry, inReviews: reviewCount(entry, store: store)) {
                        opened = entry
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func hero(_ series: [WordSeries], store: LearningStore) -> some View {
        if let next = series.first(where: { $0.state == .current }) {
            WordSeriesHeroCard(series: next, inReviews: reviewCount(next, store: store)) {
                opened = next
            }
            .qAppear(0)
        }
    }

    private func intro(for subject: Subject) -> String {
        switch subject {
        case .english, .arabic:
            return "Une série par leçon, dans l'ordre de ton parcours. Deux minutes : des cartes, un petit quiz, et les mots partent dans tes révisions."
        case .culture:
            return "Une série par leçon : les notions, personnages, lieux et dates à retenir. Des cartes, un petit quiz, puis tes révisions."
        }
    }

    private func reviewCount(_ series: WordSeries, store: LearningStore) -> Int {
        series.words.filter { store.isInReviews($0) }.count
    }
}

// MARK: - Cards of the list

/// Big pastel card of the next series to learn.
struct WordSeriesHeroCard: View {
    let series: WordSeries
    let inReviews: Int
    let action: () -> Void

    var body: some View {
        PastelCard(.pink, padding: 20) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                QFlowLayout() {
                    QPill(text: "Série \(series.number)")
                    QPill(text: "Sur ton parcours", icon: .path)
                }
                VStack(alignment: .leading, spacing: 6) {
                    CardTitle(series.title)
                    Text(WordSeriesRow.detail(series, inReviews: inReviews))
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.onPastelSecondary)
                }
                wordsPreview
                CardCTA(title: "Apprendre la série", action: action)
                    .accessibilityLabel("Apprendre la série \(series.number), \(series.title)")
            }
        }
    }

    private var wordsPreview: some View {
        QFlowLayout() {
            ForEach(Array(series.words.prefix(6))) { item in
                StudiedText(text: item.word, size: .chip)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.surface.opacity(0.7)))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// White row: number, title, a few words, how many are already in the reviews.
struct WordSeriesRow: View {
    let series: WordSeries
    let inReviews: Int
    let action: () -> Void

    /// "8 mots · 3 dans tes révisions"
    static func detail(_ series: WordSeries, inReviews: Int) -> String {
        if inReviews == 0 { return "\(series.countText) · aucun dans tes révisions" }
        if inReviews >= series.words.count { return "\(series.countText) · tous dans tes révisions" }
        return "\(series.countText) · \(inReviews) dans tes révisions"
    }

    var body: some View {
        Button(action: action) {
            rowContent
        }
        .buttonStyle(.press)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
        .accessibilityHint("Ouvre la série : des cartes, puis un petit quiz.")
        .accessibilityAddTraits(.isButton)
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 14) {
            marker
            VStack(alignment: .leading, spacing: 4) {
                Text(series.title)
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.primaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                StudiedText(text: preview, size: .chip)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                Text(Self.detail(series, inReviews: inReviews))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if series.state == .upcoming {
                QPill(text: series.state.label, icon: .clock, fill: Pastel.yellow.color, foreground: Theme.ink)
            }
            QIconView(icon: .chevronRight, size: 14)
                .foregroundStyle(Theme.inactive)
        }
        .card()
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    private var preview: String {
        let words: [String] = series.words.prefix(4).map { $0.word }
        let more: String = series.words.count > 4 ? " …" : ""
        return words.joined(separator: " · ") + more
    }

    private var allInReviews: Bool { inReviews >= series.words.count }

    private var markerFill: Color {
        if allInReviews { return Theme.green }
        switch series.state {
        case .done: return Pastel.green.soft
        case .current: return Theme.ink
        case .upcoming: return Theme.background
        }
    }

    private var markerText: Color {
        if allInReviews { return Theme.ink }
        switch series.state {
        case .done: return Theme.ink
        case .current: return Theme.onInk
        case .upcoming: return Theme.tertiaryText
        }
    }

    private var marker: some View {
        ZStack {
            Circle().fill(markerFill)
            if allInReviews {
                QIconView(icon: .check, size: 16)
                    .foregroundStyle(markerText)
            } else {
                Text("\(series.number)")
                    .font(Theme.Font.caption(.semibold).monospacedDigit())
                    .foregroundStyle(markerText)
            }
        }
        .frame(width: 38, height: 38)
        .accessibilityHidden(true)
    }

    private var spokenSummary: String {
        "Série \(series.number), \(series.title). \(Self.detail(series, inReviews: inReviews)). \(series.state.label)."
    }
}

// MARK: - Series flow (cards → quiz → result)

struct WordSeriesFlowView: View {
    let series: WordSeries
    let subject: Subject
    /// Every word of the subject: distractors of the quiz.
    let allWords: [DictionaryItem]

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Step: Equatable {
        case cards, quiz, result
    }

    /// Questions of the quiz at the end of a series.
    private static let quizLength: Int = 5

    @State private var step: Step = .cards
    @State private var cards: [DictionaryItem]
    @State private var cardIndex: Int = 0
    @State private var flipped: Bool = false
    @State private var knownIds: Set<String> = []
    @State private var reviewIds: Set<String> = []
    @State private var questions: [GameQuestion] = []
    @State private var questionIndex: Int = 0
    @State private var picked: String?
    @State private var quizCorrect: Int = 0
    @State private var quizMissedIds: Set<String> = []

    init(series: WordSeries, subject: Subject, allWords: [DictionaryItem]) {
        self.series = series
        self.subject = subject
        self.allWords = allWords
        self._cards = State(initialValue: series.words)
    }

    var body: some View {
        VStack(spacing: 0) {
            GameTopBar(title: topTitle, progress: progress, progressLabel: progressLabel,
                       closeLabel: "Fermer la série") {
                dismiss()
            }
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: step)
        .onDisappear { env.speech.stop() }
    }

    // MARK: Top bar

    private var topTitle: String {
        switch step {
        case .cards: return "Série \(series.number) · Cartes"
        case .quiz: return "Série \(series.number) · Quiz"
        case .result: return "Série \(series.number)"
        }
    }

    private var progress: Double? {
        switch step {
        case .cards: return Double(cardIndex) / Double(max(cards.count, 1))
        case .quiz: return Double(questionIndex) / Double(max(questions.count, 1))
        case .result: return nil
        }
    }

    private var progressLabel: String? {
        switch step {
        case .cards: return "\(min(cardIndex + 1, cards.count))/\(cards.count)"
        case .quiz: return "\(min(questionIndex + 1, questions.count))/\(questions.count)"
        case .result: return nil
        }
    }

    // MARK: Steps

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .cards:
            cardsStep
        case .quiz:
            quizStep
        case .result:
            resultStep
        }
    }

    private var currentCard: DictionaryItem? {
        cardIndex < cards.count ? cards[cardIndex] : nil
    }

    private var cardsStep: some View {
        LessonScaffold {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text(series.title)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.secondaryText)
                if let item = currentCard {
                    WordFlashcard(item: item, subject: subject, flipped: flipped, pastel: Pastel.cycle(cardIndex)) {
                        flip()
                    }
                    .id(item.id)
                    .transition(.opacity)
                }
            }
        } footer: {
            HStack(spacing: Theme.Spacing.s) {
                Button {
                    answerCard(known: false)
                } label: {
                    Label("À revoir", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(GamePillButtonStyle(fill: Theme.surface, foreground: Theme.ink))
                .accessibilityHint("Le mot sera mis de côté pour la fin de la série.")
                Button {
                    answerCard(known: true)
                } label: {
                    Label("Je savais", systemImage: "checkmark")
                }
                .buttonStyle(GamePillButtonStyle(fill: Theme.ink, foreground: Theme.onInk))
            }
        }
    }

    @ViewBuilder private var quizStep: some View {
        if questionIndex < questions.count {
            ScrollView(.vertical, showsIndicators: false) {
                ChoiceQuestionView(question: questions[questionIndex], picked: picked,
                                   pastel: Pastel.cycle(questionIndex + 1)) { choice in
                    pick(choice)
                }
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.vertical, Theme.Spacing.s)
                .qContentWidth()
            }
            .id(questions[questionIndex].id)
            .transition(.opacity)
        }
    }

    private var resultStep: some View {
        LessonScaffold {
            WordSeriesSummary(series: series, knownCount: knownIds.count, quizCorrect: quizCorrect,
                              quizTotal: questions.count, toReview: toReview)
        } footer: {
            VStack(spacing: Theme.Spacing.s) {
                AddToReviewsButton(items: series.words, subject: subject)
                HStack(spacing: Theme.Spacing.s) {
                    Button("Recommencer") { restart() }
                        .buttonStyle(.secondary)
                    Button("Terminer") { dismiss() }
                        .buttonStyle(.secondary)
                }
            }
        }
    }

    private var toReview: [DictionaryItem] {
        series.words.filter { reviewIds.contains($0.id) || quizMissedIds.contains($0.id) }
    }

    // MARK: Actions

    private func flip() {
        if reduceMotion {
            flipped.toggle()
        } else {
            withAnimation(.easeInOut(duration: 0.25)) { flipped.toggle() }
        }
    }

    private func answerCard(known: Bool) {
        guard let item = currentCard else { return }
        if known {
            knownIds.insert(item.id)
            reviewIds.remove(item.id)
        } else {
            reviewIds.insert(item.id)
            knownIds.remove(item.id)
        }
        if cardIndex + 1 < cards.count {
            flipped = false
            cardIndex += 1
        } else {
            startQuiz()
        }
    }

    private func startQuiz() {
        var built: [GameQuestion] = []
        for item in series.words.shuffled() {
            if built.count >= Self.quizLength { break }
            if let question = GameQuestionFactory.question(for: item, among: allWords, subject: subject, reading: false) {
                built.append(question)
            }
        }
        questions = built
        questionIndex = 0
        picked = nil
        quizCorrect = 0
        quizMissedIds = []
        step = built.isEmpty ? .result : .quiz
    }

    private func pick(_ choice: GameChoice) {
        guard step == .quiz, picked == nil, questionIndex < questions.count else { return }
        let question: GameQuestion = questions[questionIndex]
        picked = choice.id
        let isRight: Bool = choice.id == question.item.id
        if isRight {
            quizCorrect += 1
        } else {
            quizMissedIds.insert(question.item.id)
        }
        // A wrong answer leaves the right one on screen for a second.
        let delay: Duration = isRight ? .milliseconds(600) : .seconds(1)
        let questionId: UUID = question.id
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard step == .quiz, questionIndex < questions.count, questions[questionIndex].id == questionId else { return }
            nextQuestion()
        }
    }

    private func nextQuestion() {
        picked = nil
        if questionIndex + 1 < questions.count {
            questionIndex += 1
        } else {
            questionIndex = questions.count
            step = .result
        }
    }

    private func restart() {
        cards = series.words.shuffled()
        cardIndex = 0
        flipped = false
        knownIds = []
        reviewIds = []
        questions = []
        questionIndex = 0
        picked = nil
        quizCorrect = 0
        quizMissedIds = []
        step = .cards
    }
}

// MARK: - Flashcard

/// Word big (Arabic in a large font with its reading); a tap shows the meaning and an example.
struct WordFlashcard: View {
    let item: DictionaryItem
    let subject: Subject
    let flipped: Bool
    let pastel: Pastel
    let onFlip: () -> Void

    var body: some View {
        Button(action: onFlip) {
            card
        }
        .buttonStyle(.press)
        .accessibilityLabel(spokenText)
        .accessibilityHint(flipped ? "Touche deux fois pour cacher le sens." : "Touche deux fois pour voir le sens.")
        .overlay(alignment: .topTrailing) {
            QSpeakerButton(text: item.word)
                .padding(Theme.Spacing.s)
        }
    }

    private var card: some View {
        PastelCard(pastel, padding: 24) {
            VStack(spacing: Theme.Spacing.m) {
                QPill(text: item.partOfSpeechLabel)
                StudiedText(text: item.word, size: .hero)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                if let reading = item.reading {
                    Text(reading)
                        .font(Theme.Font.headline)
                        .foregroundStyle(Theme.onPastelSecondary)
                }
                if flipped {
                    back
                } else {
                    Text("Touche la carte pour voir le sens")
                        .font(Theme.Font.caption(.semibold))
                        .foregroundStyle(Theme.onPastelSecondary)
                        .padding(.top, Theme.Spacing.s)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 300)
        }
    }

    private var back: some View {
        VStack(spacing: Theme.Spacing.s + 2) {
            Rectangle()
                .fill(Theme.ink.opacity(0.12))
                .frame(height: 1)
                .padding(.vertical, Theme.Spacing.xs)
            Text(item.translation)
                .font(Theme.Font.title)
                .tracking(Theme.Tracking.title)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if subject == .culture && !item.explanation.isEmpty {
                Text(item.explanation)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.onPastelSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let example = item.examples.first {
                exampleBlock(example)
            }
        }
        .transition(.opacity)
    }

    private func exampleBlock(_ example: Example) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            StudiedText(text: example.text, size: .option)
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
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.surface.opacity(0.6)))
    }

    private var spokenText: String {
        var parts: [String] = [item.word]
        if let reading = item.reading { parts.append("se lit \(reading)") }
        if flipped {
            parts.append("veut dire \(item.translation)")
            if let example = item.examples.first { parts.append("Exemple : \(example.text), \(example.translation)") }
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Result

struct WordSeriesSummary: View {
    let series: WordSeries
    let knownCount: Int
    let quizCorrect: Int
    let quizTotal: Int
    let toReview: [DictionaryItem]

    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            header
                .qAppear(0)
            StatGrid {
                StatMiniCard(icon: .check, value: "\(knownCount)/\(series.words.count)",
                             label: "Mots que tu savais", pastel: .green)
                StatMiniCard(icon: .target, value: quizTotal > 0 ? "\(quizCorrect)/\(quizTotal)" : "–",
                             label: "Bonnes réponses au quiz", pastel: .blue)
            }
            .qAppear(1)
            QCallout(systemImage: "arrow.triangle.2.circlepath", tint: Theme.ink, fill: Pastel.yellow.soft) {
                Text("Pour que ça rentre : ajoute la série à tes révisions. Chaque mot reviendra juste avant que tu l'oublies.")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .qAppear(2)
            if !toReview.isEmpty {
                MissedWordsSection(title: "À revoir", items: toReview)
                    .qAppear(3)
            }
        }
        .onAppear { titleFocused = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s + 2) {
            ZStack {
                DiagonalCutCircle()
                    .fill(Pastel.green.color)
                    .frame(width: 120, height: 120)
                QIconView(icon: .check, size: 32)
                    .foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
            ScreenTitle("Série terminée !")
                .accessibilityFocused($titleFocused)
            ScreenSubtitle("Série \(series.number) · \(series.title)")
        }
    }
}

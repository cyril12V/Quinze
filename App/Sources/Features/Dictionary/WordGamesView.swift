import SwiftUI
import LearningCore

// « Jeux » mode of the dictionary: when there is no lesson to do, play with lots of words so that they stick.
// The words come from the series already reached on the path (or every word of the subject).

extension WordGameKind {
    var icon: QIcon {
        switch self {
        case .association: return .sparkle
        case .flashQuiz: return .hourglass
        case .trueFalse: return .check
        case .reading: return .book
        }
    }

    var pastel: Pastel {
        switch self {
        case .association: return .pink
        case .flashQuiz: return .yellow
        case .trueFalse: return .green
        case .reading: return .blue
        }
    }
}

// MARK: - Hub

struct WordGamesView: View {
    @Environment(AppEnvironment.self) private var env

    private enum PoolChoice: Equatable {
        case reached, all
    }

    /// nil = automatic: the reached series when they hold enough words.
    @State private var poolChoice: PoolChoice?
    @State private var activeGame: WordGameSetup?
    /// Bumped when a game closes, so that the best scores (kept in UserDefaults) are read again.
    @State private var recordsVersion: Int = 0

    init() {}

    var body: some View {
        let store: LearningStore = env.store
        let pools: WordGamePools = store.wordGamePools(series: store.wordSeries())
        content(pools: pools, subject: store.subject)
            .fullScreenCover(item: $activeGame, onDismiss: { recordsVersion += 1 }) { setup in
                WordGamePlayView(setup: setup)
            }
            .onChange(of: env.study.focusSubject) { _, _ in
                poolChoice = nil
            }
    }

    private func resolvedChoice(_ pools: WordGamePools) -> PoolChoice {
        if let poolChoice { return poolChoice }
        return pools.reached.count >= WordGameKind.minimumWords ? .reached : .all
    }

    @ViewBuilder
    private func content(pools: WordGamePools, subject: Subject) -> some View {
        if pools.all.isEmpty {
            EmptyStateView(icon: .sparkle, pastel: .yellow,
                           message: "Les jeux arriveront avec les premiers mots de tes leçons.")
                .qAppear(0)
        } else {
            let choice: PoolChoice = resolvedChoice(pools)
            let pool: [DictionaryItem] = choice == .reached ? pools.reached : pools.all
            VStack(alignment: .leading, spacing: Theme.Spacing.card) {
                ScreenSubtitle("Pas de leçon en ce moment ? Joue avec plein de mots : c'est comme ça qu'ils rentrent.")
                poolPicker(pools, choice: choice)
                games(pool: pool, all: pools.all, subject: subject)
            }
        }
    }

    private func poolPicker(_ pools: WordGamePools, choice: PoolChoice) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            QFlowLayout() {
                FilterChip(title: "Mes séries · \(pools.reached.count) mots", icon: .path,
                           iconFill: Pastel.pink.color, isSelected: choice == .reached) {
                    poolChoice = .reached
                }
                .accessibilityHint("Les mots des leçons que tu as déjà atteintes.")
                FilterChip(title: "Tous les mots · \(pools.all.count)", icon: .dictionary,
                           iconFill: Pastel.blue.color, isSelected: choice == .all) {
                    poolChoice = .all
                }
                .accessibilityHint("Tous les mots de la matière, même ceux des leçons à venir.")
            }
            Text(choice == .reached ? "Les mots des séries déjà atteintes sur ton parcours."
                                    : "Tous les mots de la matière, y compris ceux des leçons à venir.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.tertiaryText)
        }
    }

    private func games(pool: [DictionaryItem], all: [DictionaryItem], subject: Subject) -> some View {
        let kinds: [WordGameKind] = WordGameKind.available(for: subject)
        // Read so that the cards (and their best scores) are refreshed when a game closes.
        _ = recordsVersion
        return VStack(spacing: Theme.Spacing.card) {
            ForEach(Array(kinds.enumerated()), id: \.element) { offset, game in
                gameCard(game, pool: pool, all: all, subject: subject)
                    .qAppear(offset)
            }
        }
    }

    private func gameCard(_ game: WordGameKind, pool: [DictionaryItem], all: [DictionaryItem],
                          subject: Subject) -> some View {
        let playable: [DictionaryItem] = game.playable(pool)
        let distractors: [DictionaryItem] = game.playable(all)
        let canPlay: Bool = playable.count >= WordGameKind.minimumWords
        return WordGameCard(game: game, subject: subject, best: WordGameRecords.best(game, subject: subject),
                            isPlayable: canPlay) {
            activeGame = WordGameSetup(game: game, subject: subject, pool: playable, allWords: distractors)
        }
    }
}

/// Pastel card of one game: icon, record, rules, « Jouer ».
struct WordGameCard: View {
    let game: WordGameKind
    let subject: Subject
    let best: Int
    let isPlayable: Bool
    let action: () -> Void

    var body: some View {
        PastelCard(game.pastel, padding: 20) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(alignment: .top) {
                    QIconView(icon: game.icon, size: 18)
                        .foregroundStyle(Theme.onInk)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Theme.ink))
                        .accessibilityHidden(true)
                    Spacer(minLength: Theme.Spacing.s)
                    QPill(text: best > 0 ? "Record : \(best)" : "Pas encore de record", icon: .star)
                }
                VStack(alignment: .leading, spacing: 6) {
                    CardTitle(game.title)
                    Text(game.summary(for: subject))
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.onPastelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                playButton
            }
        }
    }

    @ViewBuilder private var playButton: some View {
        if isPlayable {
            CardCTA(title: "Jouer", action: action)
                .accessibilityLabel("Jouer à \(game.title)")
        } else {
            Text("Il faut au moins \(WordGameKind.minimumWords) mots : choisis « Tous les mots ».")
                .font(Theme.Font.caption(.semibold))
                .foregroundStyle(Theme.onPastelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Playing

/// Full screen: the game, then its result (score, best score, missed words).
struct WordGamePlayView: View {
    let setup: WordGameSetup

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var outcome: WordGameOutcome?
    @State private var record: WordGameRecord?
    @State private var run: Int = 0

    init(setup: WordGameSetup) {
        self.setup = setup
    }

    var body: some View {
        VStack(spacing: 0) {
            GameTopBar(title: setup.game.title, closeLabel: "Fermer le jeu") {
                dismiss()
            }
            screen
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .onDisappear { env.speech.stop() }
    }

    @ViewBuilder private var screen: some View {
        if let outcome, let record {
            WordGameResultView(setup: setup, outcome: outcome, record: record,
                               onReplay: { replay() }, onDone: { dismiss() })
        } else {
            game
                .id(run)
        }
    }

    @ViewBuilder private var game: some View {
        switch setup.game {
        case .association:
            AssociationGameView(setup: setup, onFinish: { finish($0) })
        case .flashQuiz, .reading:
            ChoiceGameView(setup: setup, onFinish: { finish($0) })
        case .trueFalse:
            TrueFalseGameView(setup: setup, onFinish: { finish($0) })
        }
    }

    private func finish(_ result: WordGameOutcome) {
        guard outcome == nil else { return }
        record = WordGameRecords.save(result.score, game: setup.game, subject: setup.subject)
        outcome = result
    }

    private func replay() {
        outcome = nil
        record = nil
        run += 1
    }
}

// MARK: - Result

struct WordGameResultView: View {
    let setup: WordGameSetup
    let outcome: WordGameOutcome
    let record: WordGameRecord
    let onReplay: () -> Void
    let onDone: () -> Void

    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        LessonScaffold {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header
                    .qAppear(0)
                StatGrid {
                    StatMiniCard(icon: .star, value: "\(outcome.score)", label: scoreLabel, pastel: .yellow)
                    StatMiniCard(icon: .flame, value: "\(record.best)", label: "Ton record", pastel: .pink)
                }
                .qAppear(1)
                missedSection
                    .qAppear(2)
            }
        } footer: {
            footer
        }
        .onAppear { titleFocused = true }
    }

    private var scoreLabel: String {
        setup.game == .association ? "Points" : "Bonnes réponses"
    }

    private var summary: String {
        switch setup.game {
        case .association:
            let pairs: String = outcome.correct > 1 ? "\(outcome.correct) paires trouvées" : "\(outcome.correct) paire trouvée"
            return "\(pairs) · \(outcome.score) points"
        case .flashQuiz, .trueFalse, .reading:
            return "\(outcome.correct) bonnes réponses sur \(outcome.answered)"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s + 2) {
            ZStack {
                DiagonalCutCircle()
                    .fill(record.isNewRecord ? Pastel.yellow.color : setup.game.pastel.color)
                    .frame(width: 120, height: 120)
                QIconView(icon: .star, size: 32)
                    .foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
            ScreenTitle(record.isNewRecord ? "Nouveau record !" : "Partie terminée")
                .accessibilityFocused($titleFocused)
            ScreenSubtitle(summary)
        }
    }

    @ViewBuilder private var missedSection: some View {
        if !outcome.missed.isEmpty {
            MissedWordsSection(title: outcome.missed.count > 1 ? "Les mots ratés" : "Le mot raté", items: outcome.missed)
        } else if outcome.answered > 0 {
            QCallout(systemImage: "checkmark.circle", tint: Theme.ink, fill: Pastel.green.soft) {
                Text("Sans faute ! Rejoue pour battre ton record.")
                    .font(Theme.Font.callout(.semibold))
                    .foregroundStyle(Theme.ink)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: Theme.Spacing.s) {
            if !outcome.missed.isEmpty {
                AddToReviewsButton(items: outcome.missed, subject: setup.subject,
                                   title: "Ajouter les mots ratés à mes révisions")
            }
            HStack(spacing: Theme.Spacing.s) {
                Button("Rejouer") { onReplay() }
                    .buttonStyle(.secondary)
                Button("Autres jeux") { onDone() }
                    .buttonStyle(.secondary)
            }
        }
    }
}

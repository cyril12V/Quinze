import SwiftUI
import LearningCore

// Building blocks shared by the word series and the dictionary games.

extension DictionaryItem {
    /// French name of the part of speech, including the Arabic and culture G categories.
    var partOfSpeechLabel: String {
        let key: String = partOfSpeech.trimmingCharacters(in: .whitespaces).lowercased()
        switch key {
        case "letter": return "lettre"
        case "particle": return "particule"
        case "concept": return "notion"
        case "person": return "personnage"
        case "place": return "lieu"
        case "event": return "événement"
        case "work": return "œuvre"
        case "date": return "date"
        case "organization": return "organisation"
        default: return FrenchLabels.partOfSpeech(partOfSpeech)
        }
    }
}

// MARK: - Word text

/// A word of the studied subject. Arabic is drawn with the system font about 1.5× larger than the Latin
/// text around it, laid out right to left; other words keep the app font.
struct StudiedText: View {
    enum Size {
        /// Flashcard, game prompt.
        case hero
        /// Smaller prompt (true or false card).
        case prompt
        /// Dictionary row, word line.
        case row
        /// Answer button, association tile.
        case option
        /// Small chip.
        case chip
    }

    let text: String
    var size: Size = .row

    @ScaledMetric(relativeTo: .largeTitle) private var heroArabic: CGFloat = 60
    @ScaledMetric(relativeTo: .title) private var promptArabic: CGFloat = 40
    @ScaledMetric(relativeTo: .headline) private var rowArabic: CGFloat = 26
    @ScaledMetric(relativeTo: .body) private var optionArabic: CGFloat = 24
    @ScaledMetric(relativeTo: .caption) private var chipArabic: CGFloat = 19

    init(text: String, size: Size = .row) {
        self.text = text
        self.size = size
    }

    var body: some View {
        if text.containsArabic {
            Text(text)
                .font(.system(size: arabicSize))
                .lineSpacing(4)
                .environment(\.layoutDirection, .rightToLeft)
        } else {
            Text(text)
                .font(latinFont)
                .tracking(size == .hero ? Theme.Tracking.display : 0)
        }
    }

    private var arabicSize: CGFloat {
        switch size {
        case .hero: return heroArabic
        case .prompt: return promptArabic
        case .row: return rowArabic
        case .option: return optionArabic
        case .chip: return chipArabic
        }
    }

    private var latinFont: Font {
        switch size {
        case .hero: return Theme.Font.display
        case .prompt: return Theme.Font.title
        case .row: return Theme.Font.headline
        case .option: return Theme.Font.body(.semibold)
        case .chip: return Theme.Font.caption(.semibold)
        }
    }
}

/// A word with its reading (Arabic) and its meaning, on one white line, with a listen button.
struct WordLine: View {
    let item: DictionaryItem
    var showsSpeaker: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                StudiedText(text: item.word, size: .row)
                    .foregroundStyle(Theme.primaryText)
                if let reading = item.reading {
                    Text(reading)
                        .font(Theme.Font.caption(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                Text(item.translation)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if showsSpeaker {
                QSpeakerButton(text: item.word)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s + 2)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.surface))
    }
}

// MARK: - Top bar & timer

/// Close button, title and an optional progress bar, at the top of a full-screen series or game.
struct GameTopBar: View {
    let title: String
    var progress: Double? = nil
    var progressLabel: String? = nil
    var closeLabel: String = "Fermer"
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            RoundIconButton(icon: .close, label: closeLabel, action: onClose)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Font.caption(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                if let progress {
                    HStack(spacing: Theme.Spacing.m) {
                        QProgressBar(value: progress)
                        if let progressLabel {
                            Text(progressLabel)
                                .font(Theme.Font.caption(.semibold).monospacedDigit())
                                .foregroundStyle(Theme.tertiaryText)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(progressLabel ?? "")
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.top, Theme.Spacing.xs)
        .frame(minHeight: Theme.minTapSize)
        .qContentWidth()
    }
}

/// Countdown bar of a timed game. Calls `onExpire` once when the time is up. Give it a new `.id` to restart it.
struct GameCountdown: View {
    let seconds: Int
    let onExpire: () -> Void

    @State private var remaining: Double

    init(seconds: Int, onExpire: @escaping () -> Void) {
        self.seconds = seconds
        self.onExpire = onExpire
        self._remaining = State(initialValue: Double(seconds))
    }

    private var fraction: Double {
        seconds > 0 ? remaining / Double(seconds) : 0
    }

    private var secondsLeft: Int {
        Int(remaining.rounded(.up))
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            QIconView(icon: .hourglass, size: 16)
                .foregroundStyle(Theme.ink)
            QProgressBar(value: fraction, fill: secondsLeft <= 5 ? Theme.error : Theme.ink)
            Text("\(secondsLeft) s")
                .font(Theme.Font.caption(.semibold).monospacedDigit())
                .foregroundStyle(secondsLeft <= 5 ? Theme.error : Theme.secondaryText)
                .frame(minWidth: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Temps restant")
        .accessibilityValue("\(secondsLeft) secondes")
        .task { await run() }
    }

    private func run() async {
        let start: Date = .now
        let total: Double = Double(seconds)
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(200))
            if Task.isCancelled { return }
            let left: Double = total - Date.now.timeIntervalSince(start)
            remaining = max(left, 0)
            if left <= 0 {
                onExpire()
                return
            }
        }
    }
}

/// Countdown + score, above a timed game.
struct GameHUD: View {
    let seconds: Int
    let score: Int
    var caption: String? = nil
    let onExpire: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.m) {
                GameCountdown(seconds: seconds, onExpire: onExpire)
                QPill(text: "\(score)", icon: .star, fill: Pastel.yellow.color, foreground: Theme.ink)
                    .accessibilityLabel("Score : \(score)")
            }
            if let caption {
                Text(caption)
                    .font(Theme.Font.caption(.semibold))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
    }
}

// MARK: - Buttons

/// 58 pt pill, used two by two (« À revoir » / « Je savais », « Faux » / « Vrai »): same height side by side.
struct GamePillButtonStyle: ButtonStyle {
    let fill: Color
    let foreground: Color
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.button)
            .frame(maxWidth: .infinity, minHeight: Theme.primaryButtonHeight)
            .padding(.horizontal, Theme.Spacing.s)
            .foregroundStyle(foreground)
            .background(Capsule().fill(fill))
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

// MARK: - Multiple choice

enum GameChoiceState: Equatable {
    case idle
    case correct
    case wrong
    case dimmed
}

/// The question card (instruction, word, listen button) and its answers. Once `picked` is set, the right
/// answer turns green and a wrong pick pink, and every button is disabled.
struct ChoiceQuestionView: View {
    let question: GameQuestion
    /// Answer picked by the learner (nil while answering).
    let picked: String?
    var pastel: Pastel = .blue
    let onPick: (GameChoice) -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            promptCard
            VStack(spacing: Theme.Spacing.s + 2) {
                ForEach(question.choices) { choice in
                    GameChoiceButton(choice: choice, state: state(of: choice)) {
                        onPick(choice)
                    }
                }
            }
        }
    }

    /// The listen button would give the reading away before the answer.
    private var showsSpeaker: Bool {
        question.kind == .meaning || picked != nil
    }

    private var promptCard: some View {
        PastelCard(pastel, padding: 20) {
            VStack(spacing: Theme.Spacing.s) {
                Text(question.instruction)
                    .font(Theme.Font.caption(.semibold))
                    .foregroundStyle(Theme.onPastelSecondary)
                StudiedText(text: question.prompt, size: .hero)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                if let caption = question.caption {
                    Text(caption)
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.onPastelSecondary)
                }
                if showsSpeaker {
                    QSpeakerButton(text: question.item.word)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
    }

    private func state(of choice: GameChoice) -> GameChoiceState {
        guard let picked else { return .idle }
        if choice.id == question.item.id { return .correct }
        if choice.id == picked { return .wrong }
        return .dimmed
    }
}

/// White answer button; green with a check when right, pink with a cross when wrongly picked.
struct GameChoiceButton: View {
    let choice: GameChoice
    let state: GameChoiceState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(.press)
        .disabled(state != .idle)
        .accessibilityLabel(spokenLabel)
        .accessibilityValue(spokenState)
    }

    private var label: some View {
        HStack(spacing: Theme.Spacing.s) {
            VStack(spacing: 2) {
                StudiedText(text: choice.text, size: .option)
                if let detail = choice.detail {
                    Text(detail)
                        .font(Theme.Font.caption(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            if let icon = stateIcon {
                QIconView(icon: icon, size: 16)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(fill))
        .opacity(state == .dimmed ? 0.55 : 1)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
    }

    private var fill: Color {
        switch state {
        case .idle, .dimmed: return Theme.surface
        case .correct: return Pastel.green.color
        case .wrong: return Theme.pinkSoft
        }
    }

    private var stateIcon: QIcon? {
        switch state {
        case .correct: return .check
        case .wrong: return .close
        case .idle, .dimmed: return nil
        }
    }

    private var spokenLabel: String {
        if let detail = choice.detail { return "\(choice.text), \(detail)" }
        return choice.text
    }

    private var spokenState: String {
        switch state {
        case .correct: return "Bonne réponse"
        case .wrong: return "Mauvaise réponse"
        case .idle, .dimmed: return ""
        }
    }
}

// MARK: - Adding words to reviews

/// « Ajouter les mots à mes révisions »: tracks every word that is not scheduled yet (spaced repetition),
/// then confirms. Shows a short note when every word is already in the reviews.
struct AddToReviewsButton: View {
    let items: [DictionaryItem]
    let subject: Subject
    var title: String = "Ajouter les mots à mes révisions"

    @Environment(AppEnvironment.self) private var env
    @State private var isWorking = false
    @State private var addedCount: Int?

    private var store: LearningStore { env.study.store(subject) }

    private var pending: [DictionaryItem] {
        items.filter { store.canAddToReviews($0) }
    }

    var body: some View {
        let missing: [DictionaryItem] = pending
        let added: Int = addedCount ?? 0
        if added > 0 {
            note(addedText(added))
        } else if missing.isEmpty {
            note("Ces mots sont déjà dans tes révisions.")
        } else {
            Button(missing.count == items.count ? title : "\(title) (\(missing.count))") {
                add(missing)
            }
            .buttonStyle(.primary)
            .disabled(isWorking)
            .accessibilityHint("Les mots reviendront dans tes séances de révision.")
        }
    }

    private func addedText(_ count: Int) -> String {
        if count > 1 {
            return "\(count) mots ajoutés : ils reviendront dans tes révisions, juste avant que tu les oublies."
        }
        return "Mot ajouté : il reviendra dans tes révisions, juste avant que tu l'oublies."
    }

    private func note(_ text: String) -> some View {
        QCallout(systemImage: "checkmark.circle", tint: Theme.ink, fill: Pastel.green.soft) {
            Text(text)
                .font(Theme.Font.callout(.semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func add(_ words: [DictionaryItem]) {
        guard !isWorking else { return }
        isWorking = true
        let target: LearningStore = store
        let ids: [String] = words.map { $0.id }
        Task { @MainActor in
            var added: Int = 0
            for id in ids {
                await target.trackWord(id)
                if target.isWordTracked(id) { added += 1 }
            }
            addedCount = added
            isWorking = false
        }
    }
}

/// Words to look at again, as white lines.
struct MissedWordsSection: View {
    let title: String
    let items: [DictionaryItem]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            QSectionTitle(title)
            VStack(spacing: Theme.Spacing.s) {
                ForEach(items) { item in
                    WordLine(item: item)
                }
            }
        }
    }
}

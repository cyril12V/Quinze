import SwiftUI
import LearningCore

// The dictionary games themselves. Each one reports a `WordGameOutcome` through `onFinish` (once);
// `WordGamePlayView` keeps the best score and shows the result. A wrong answer always leaves the right
// one on screen for a second.

// MARK: - Quiz éclair & Lecture rapide

/// 60 seconds, one word after another, 4 answers. « Lecture rapide » asks for the reading of vowelled Arabic
/// words, and which letter a shape is.
struct ChoiceGameView: View {
    let setup: WordGameSetup
    let onFinish: (WordGameOutcome) -> Void

    @State private var question: GameQuestion?
    @State private var picked: String?
    @State private var number: Int = 0
    @State private var outcome = WordGameOutcome()
    @State private var recent: [String] = []
    @State private var finished = false

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            GameHUD(seconds: setup.game.seconds, score: outcome.correct) {
                finish()
            }
            .padding(.horizontal, Theme.Spacing.page)
            .qContentWidth()
            ScrollView(.vertical, showsIndicators: false) {
                questionView
                    .padding(.horizontal, Theme.Spacing.page)
                    .padding(.bottom, Theme.Spacing.l)
                    .qContentWidth()
            }
        }
        .padding(.top, Theme.Spacing.s)
        .onAppear {
            if question == nil { nextQuestion() }
        }
        .sensoryFeedback(.success, trigger: outcome.correct)
        .sensoryFeedback(.error, trigger: outcome.wrong)
    }

    @ViewBuilder private var questionView: some View {
        if let question {
            ChoiceQuestionView(question: question, picked: picked, pastel: Pastel.cycle(number)) { choice in
                pick(choice)
            }
            .id(question.id)
        }
    }

    private func pick(_ choice: GameChoice) {
        guard !finished, picked == nil, let current = question else { return }
        picked = choice.id
        outcome.answered += 1
        let isRight: Bool = choice.id == current.item.id
        if isRight {
            outcome.correct += 1
            outcome.score += 1
        } else {
            outcome.miss(current.item)
        }
        let delay: Duration = isRight ? .milliseconds(350) : .seconds(1)
        let questionId: UUID = current.id
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !finished, question?.id == questionId else { return }
            nextQuestion()
        }
    }

    private func nextQuestion() {
        let reading: Bool = setup.game == .reading
        for _ in 0..<8 {
            guard let item = GameQuestionFactory.pick(from: setup.pool, avoiding: recent) else { break }
            remember(item.id)
            if let next = GameQuestionFactory.question(for: item, among: setup.allWords, subject: setup.subject,
                                                       reading: reading) {
                picked = nil
                number += 1
                question = next
                return
            }
        }
        finish()
    }

    private func remember(_ id: String) {
        recent.append(id)
        let limit: Int = GameQuestionFactory.memory(for: setup.pool)
        if recent.count > limit {
            recent.removeFirst(recent.count - limit)
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish(outcome)
    }
}

// MARK: - Vrai ou faux

/// 60 seconds: a word and a proposed translation. Swipe right (or « Vrai ») when it is right, left
/// (or « Faux ») when it is not.
struct TrueFalseGameView: View {
    let setup: WordGameSetup
    let onFinish: (WordGameOutcome) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var question: TrueFalseQuestion?
    /// Whether the learner was right, while the answer is shown (nil while answering).
    @State private var verdict: Bool?
    @State private var number: Int = 0
    @State private var outcome = WordGameOutcome()
    @State private var recent: [String] = []
    @State private var finished = false
    @State private var dragOffset: CGFloat = 0

    private let swipeThreshold: CGFloat = 90

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            GameHUD(seconds: setup.game.seconds, score: outcome.correct,
                    caption: "Glisse la carte à droite pour vrai, à gauche pour faux.") {
                finish()
            }
            Spacer(minLength: 0)
            if let question {
                card(question)
            }
            feedback
                .frame(minHeight: 70)
            Spacer(minLength: 0)
            answerButtons
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.m)
        .qContentWidth()
        .onAppear {
            if question == nil { nextQuestion() }
        }
        .sensoryFeedback(.success, trigger: outcome.correct)
        .sensoryFeedback(.error, trigger: outcome.wrong)
    }

    private var connector: String {
        setup.subject == .culture ? "c'est…" : "veut dire…"
    }

    private var cardFill: Color {
        guard let verdict else { return Pastel.cycle(number).color }
        return verdict ? Pastel.green.color : Theme.pinkSoft
    }

    private func card(_ question: TrueFalseQuestion) -> some View {
        PastelCard(fill: cardFill, padding: 24) {
            VStack(spacing: Theme.Spacing.m) {
                StudiedText(text: question.item.word, size: .hero)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                if let reading = question.item.reading {
                    Text(reading)
                        .font(Theme.Font.headline)
                        .foregroundStyle(Theme.onPastelSecondary)
                }
                Text(connector)
                    .font(Theme.Font.caption(.semibold))
                    .foregroundStyle(Theme.onPastelSecondary)
                Text(question.proposed)
                    .font(Theme.Font.title)
                    .tracking(Theme.Tracking.title)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 240)
        }
        .offset(x: dragOffset)
        .rotationEffect(.degrees(reduceMotion ? 0 : Double(dragOffset / 25)))
        .gesture(swipe)
        .id(question.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(question.item.word) \(connector) \(question.proposed)")
        .accessibilityHint("Réponds avec les boutons Vrai ou Faux.")
        .accessibilityAction(named: "Vrai") { answer(true) }
        .accessibilityAction(named: "Faux") { answer(false) }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard verdict == nil else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                let width: CGFloat = value.translation.width
                if verdict == nil && width > swipeThreshold {
                    answer(true)
                } else if verdict == nil && width < -swipeThreshold {
                    answer(false)
                }
                if reduceMotion {
                    dragOffset = 0
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragOffset = 0 }
                }
            }
    }

    @ViewBuilder private var feedback: some View {
        if let verdict, let question {
            if verdict {
                Label("Juste !", systemImage: "checkmark")
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.success)
            } else {
                VStack(spacing: Theme.Spacing.xs) {
                    Text(question.isTrue ? "Non, c'était vrai :" : "Non, c'était faux :")
                        .font(Theme.Font.callout(.semibold))
                        .foregroundStyle(Theme.error)
                    Text("\(question.item.word) = \(question.item.translation)")
                        .font(Theme.Font.headline)
                        .foregroundStyle(Theme.primaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var answerButtons: some View {
        HStack(spacing: Theme.Spacing.s) {
            verdictButton(title: "Faux", icon: .close, value: false, fill: Theme.pink)
            verdictButton(title: "Vrai", icon: .check, value: true, fill: Pastel.green.color)
        }
    }

    private func verdictButton(title: String, icon: QIcon, value: Bool, fill: Color) -> some View {
        Button {
            answer(value)
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                QIconView(icon: icon, size: 18)
                Text(title)
            }
        }
        .buttonStyle(GamePillButtonStyle(fill: fill, foreground: Theme.ink))
        .disabled(verdict != nil)
        .accessibilityLabel(title)
        .accessibilityHint(value ? "La traduction proposée est juste." : "La traduction proposée est fausse.")
    }

    private func answer(_ value: Bool) {
        guard !finished, verdict == nil, let current = question else { return }
        let isRight: Bool = value == current.isTrue
        verdict = isRight
        outcome.answered += 1
        if isRight {
            outcome.correct += 1
            outcome.score += 1
        } else {
            outcome.miss(current.item)
        }
        let delay: Duration = isRight ? .milliseconds(450) : .seconds(1)
        let questionId: UUID = current.id
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !finished, question?.id == questionId else { return }
            nextQuestion()
        }
    }

    private func nextQuestion() {
        guard let item = GameQuestionFactory.pick(from: setup.pool, avoiding: recent) else {
            finish()
            return
        }
        recent.append(item.id)
        let limit: Int = GameQuestionFactory.memory(for: setup.pool)
        if recent.count > limit {
            recent.removeFirst(recent.count - limit)
        }
        verdict = nil
        dragOffset = 0
        number += 1
        question = GameQuestionFactory.trueFalse(for: item, among: setup.allWords)
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish(outcome)
    }
}

// MARK: - Association

/// 3 timed rounds: link 5 words to their meaning. 10 points per pair, plus the seconds left when a round is
/// cleared.
struct AssociationGameView: View {
    let setup: WordGameSetup
    let onFinish: (WordGameOutcome) -> Void

    private struct Mismatch: Equatable {
        let word: String
        let meaning: String
    }

    @State private var rounds: [[DictionaryItem]] = []
    @State private var roundIndex: Int = 0
    @State private var words: [DictionaryItem] = []
    @State private var meanings: [DictionaryItem] = []
    @State private var selectedWord: String?
    @State private var selectedMeaning: String?
    @State private var matched: Set<String> = []
    @State private var mismatch: Mismatch?
    @State private var roundStart: Date = .now
    @State private var outcome = WordGameOutcome()
    @State private var started = false
    @State private var betweenRounds = false
    @State private var finished = false

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            GameHUD(seconds: setup.game.seconds, score: outcome.score, caption: roundCaption) {
                endRound(timedOut: true)
            }
            .id(roundIndex)
            .padding(.horizontal, Theme.Spacing.page)
            .qContentWidth()
            ScrollView(.vertical, showsIndicators: false) {
                board
                    .padding(.horizontal, Theme.Spacing.page)
                    .padding(.bottom, Theme.Spacing.l)
                    .qContentWidth()
            }
        }
        .padding(.top, Theme.Spacing.s)
        .onAppear { start() }
        .sensoryFeedback(.success, trigger: outcome.correct)
        .sensoryFeedback(.error, trigger: outcome.wrong)
    }

    private var roundCaption: String {
        guard !rounds.isEmpty else { return "" }
        let target: String = setup.subject == .culture ? "sa définition" : "son sens"
        return "Manche \(roundIndex + 1)/\(rounds.count) · relie chaque mot à \(target)"
    }

    private var board: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            VStack(spacing: Theme.Spacing.s) {
                ForEach(words) { item in
                    MatchTile(text: item.word, isWord: true, state: wordState(item.id)) {
                        tapWord(item.id)
                    }
                }
            }
            VStack(spacing: Theme.Spacing.s) {
                ForEach(meanings) { item in
                    MatchTile(text: item.translation, isWord: false, state: meaningState(item.id)) {
                        tapMeaning(item.id)
                    }
                }
            }
        }
        .opacity(betweenRounds ? 0.4 : 1)
    }

    // MARK: Tile states

    private func wordState(_ id: String) -> MatchTileState {
        if matched.contains(id) { return .matched }
        if let mismatch, mismatch.word == id { return .wrong }
        if selectedWord == id { return .selected }
        return .idle
    }

    private func meaningState(_ id: String) -> MatchTileState {
        if matched.contains(id) { return .matched }
        if let mismatch {
            if mismatch.meaning == id { return .wrong }
            // The meaning that went with the word: shown for a second.
            if mismatch.word == id { return .hint }
        }
        if selectedMeaning == id { return .selected }
        return .idle
    }

    // MARK: Actions

    private var canPlay: Bool {
        !finished && !betweenRounds && mismatch == nil
    }

    private func tapWord(_ id: String) {
        guard canPlay, !matched.contains(id) else { return }
        selectedWord = selectedWord == id ? nil : id
        check()
    }

    private func tapMeaning(_ id: String) {
        guard canPlay, !matched.contains(id) else { return }
        selectedMeaning = selectedMeaning == id ? nil : id
        check()
    }

    private func check() {
        guard let word = selectedWord, let meaning = selectedMeaning else { return }
        selectedWord = nil
        selectedMeaning = nil
        outcome.answered += 1
        if word == meaning {
            matched.insert(word)
            outcome.correct += 1
            outcome.score += 10
            if matched.count >= words.count {
                endRound(timedOut: false)
            }
        } else {
            if let item = words.first(where: { $0.id == word }) {
                outcome.miss(item)
            }
            let shown = Mismatch(word: word, meaning: meaning)
            mismatch = shown
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                if mismatch == shown { mismatch = nil }
            }
        }
    }

    private func start() {
        guard !started else { return }
        started = true
        rounds = GameQuestionFactory.associationRounds(from: setup.pool, rounds: WordGameKind.associationRounds,
                                                       pairs: WordGameKind.associationPairs)
        if rounds.isEmpty {
            finish()
        } else {
            startRound(0)
        }
    }

    private func startRound(_ index: Int) {
        guard index < rounds.count else {
            finish()
            return
        }
        let round: [DictionaryItem] = rounds[index]
        roundIndex = index
        words = round.shuffled()
        meanings = round.shuffled()
        matched = []
        selectedWord = nil
        selectedMeaning = nil
        mismatch = nil
        roundStart = .now
        betweenRounds = false
    }

    private func endRound(timedOut: Bool) {
        guard !finished, !betweenRounds, !words.isEmpty else { return }
        if timedOut {
            for item in words where !matched.contains(item.id) {
                outcome.miss(item)
            }
        } else {
            let elapsed: Int = Int(Date.now.timeIntervalSince(roundStart))
            outcome.score += max(0, setup.game.seconds - elapsed)
        }
        guard roundIndex + 1 < rounds.count else {
            finish()
            return
        }
        betweenRounds = true
        let next: Int = roundIndex + 1
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !finished else { return }
            startRound(next)
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish(outcome)
    }
}

enum MatchTileState: Equatable {
    case idle, selected, matched, wrong, hint
}

/// One tile of « Association »: a word (left) or a meaning (right).
struct MatchTile: View {
    let text: String
    let isWord: Bool
    let state: MatchTileState
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(.press)
        .disabled(state == .matched)
        .accessibilityLabel(isWord ? "Mot : \(text)" : "Sens : \(text)")
        .accessibilityValue(spokenState)
        .accessibilityAddTraits(state == .selected ? .isSelected : [])
    }

    private var label: some View {
        tileText
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(state == .selected ? Theme.onInk : Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(shape.fill(fill))
            .overlay {
                shape.strokeBorder(state == .hint ? Theme.success : Color.clear, lineWidth: 2)
            }
            .overlay(alignment: .topTrailing) {
                if state == .matched {
                    QIconView(icon: .check, size: 12)
                        .foregroundStyle(Theme.ink)
                        .padding(6)
                }
            }
            .opacity(state == .matched ? 0.55 : 1)
            .contentShape(shape)
    }

    @ViewBuilder private var tileText: some View {
        if isWord {
            StudiedText(text: text, size: .option)
        } else {
            Text(text)
                .font(Theme.Font.callout(.semibold))
        }
    }

    private var fill: Color {
        switch state {
        case .idle: return Theme.surface
        case .selected: return Theme.ink
        case .matched: return Pastel.green.color
        case .wrong: return Theme.pinkSoft
        case .hint: return Pastel.green.soft
        }
    }

    private var spokenState: String {
        switch state {
        case .idle: return ""
        case .selected: return "Sélectionné"
        case .matched: return "Trouvé"
        case .wrong: return "Ne va pas ensemble"
        case .hint: return "La bonne réponse"
        }
    }
}

import Foundation
import LearningCore

// Logic of the dictionary games and of the series quiz: game kinds, question generation, best scores.
// Foundation only: the views live in WordGamesView, WordGamePlayViews and WordGameComponents.

// MARK: - Games

enum WordGameKind: String, CaseIterable, Identifiable, Sendable {
    case association
    case flashQuiz
    case trueFalse
    case reading

    var id: String { rawValue }

    var title: String {
        switch self {
        case .association: return "Association"
        case .flashQuiz: return "Quiz éclair"
        case .trueFalse: return "Vrai ou faux"
        case .reading: return "Lecture rapide"
        }
    }

    func summary(for subject: Subject) -> String {
        let meaning: String = subject == .culture ? "définition" : "traduction"
        switch self {
        case .association:
            return "Relie 5 mots à leur \(meaning). 3 manches de \(seconds) secondes."
        case .flashQuiz:
            return "\(seconds) secondes : trouve la bonne \(meaning) parmi 4."
        case .trueFalse:
            return "\(seconds) secondes : la \(meaning) proposée est-elle juste ? Glisse ou touche."
        case .reading:
            return "Lis le mot vocalisé (ou la lettre) et choisis sa lecture, le plus vite possible."
        }
    }

    /// Length of the game, or of one round for « Association ».
    var seconds: Int {
        switch self {
        case .association: return 30
        case .flashQuiz, .trueFalse, .reading: return 60
        }
    }

    /// Rounds of « Association ».
    static let associationRounds: Int = 3
    static let associationPairs: Int = 5

    /// "points" or "bonnes réponses" (unit of the score).
    var scoreUnit: String {
        switch self {
        case .association: return "points"
        case .flashQuiz, .trueFalse, .reading: return "bonnes réponses"
        }
    }

    /// Below this many usable words, the game is not offered.
    static let minimumWords: Int = 4

    /// Games of a subject: « Lecture rapide » is for Arabic only.
    static func available(for subject: Subject) -> [WordGameKind] {
        allCases.filter { $0 != .reading || subject == .arabic }
    }

    /// Words of a pool this game can ask about.
    func playable(_ items: [DictionaryItem]) -> [DictionaryItem] {
        switch self {
        case .reading:
            return items.filter { item in
                if item.isLetter { return GameQuestionFactory.letterShapes(of: item).isEmpty == false }
                return item.reading != nil
            }
        case .association, .flashQuiz, .trueFalse:
            return items.filter { !$0.translation.trimmingCharacters(in: .whitespaces).isEmpty }
        }
    }
}

/// What a game needs: its words (pool) and every word of the subject (distractors).
struct WordGameSetup: Identifiable, Sendable {
    let id: UUID = UUID()
    let game: WordGameKind
    let subject: Subject
    let pool: [DictionaryItem]
    let allWords: [DictionaryItem]
}

/// Result of one game.
struct WordGameOutcome: Sendable, Equatable {
    var score: Int = 0
    var correct: Int = 0
    var answered: Int = 0
    /// Words answered wrong or not found in time, in order, without duplicates.
    private(set) var missed: [DictionaryItem] = []

    var wrong: Int { max(answered - correct, 0) }

    mutating func miss(_ item: DictionaryItem) {
        if !missed.contains(where: { $0.id == item.id }) { missed.append(item) }
    }
}

struct WordGameRecord: Sendable, Equatable {
    let best: Int
    let isNewRecord: Bool
}

/// Best score per subject and game, kept on this iPhone.
enum WordGameRecords {
    private static func key(_ game: WordGameKind, _ subject: Subject) -> String {
        "quinze.wordGames.best.\(subject.code).\(game.rawValue)"
    }

    static func best(_ game: WordGameKind, subject: Subject) -> Int {
        UserDefaults.standard.integer(forKey: key(game, subject))
    }

    /// Keeps the score when it beats the best one.
    static func save(_ score: Int, game: WordGameKind, subject: Subject) -> WordGameRecord {
        let previous: Int = best(game, subject: subject)
        guard score > previous else { return WordGameRecord(best: previous, isNewRecord: false) }
        UserDefaults.standard.set(score, forKey: key(game, subject))
        return WordGameRecord(best: score, isNewRecord: true)
    }
}

// MARK: - Questions

/// One answer of a question. `id` is the dictionary item it stands for: the answer is right when it is the
/// question's item.
struct GameChoice: Identifiable, Hashable, Sendable {
    let id: String
    let text: String
    /// Small line under the answer (Latin reading of an Arabic letter).
    let detail: String?
}

/// A question with up to 4 answers.
struct GameQuestion: Identifiable, Hashable, Sendable {
    enum Kind: Sendable, Hashable {
        /// Word → its translation (definition for culture G).
        case meaning
        /// Vowelled Arabic word → its Latin reading.
        case reading
        /// One shape of an Arabic letter → the letter.
        case letter
    }

    let id: UUID
    let kind: Kind
    let item: DictionaryItem
    let instruction: String
    /// Text shown big: the word, or one shape of a letter.
    let prompt: String
    /// Small line under the prompt ("Forme initiale").
    let caption: String?
    let choices: [GameChoice]

    var answer: GameChoice? { choices.first { $0.id == item.id } }
}

/// A word and a proposed translation: right or wrong?
struct TrueFalseQuestion: Identifiable, Hashable, Sendable {
    let id: UUID
    let item: DictionaryItem
    let proposed: String
    let isTrue: Bool
}

enum GameQuestionFactory {
    /// Shapes of a letter, in the order they are taught.
    static let shapeKeys: [(key: String, label: String)] = [
        (key: "isolated", label: "Forme isolée"),
        (key: "initial", label: "Forme du début"),
        (key: "medial", label: "Forme du milieu"),
        (key: "final", label: "Forme de la fin"),
    ]

    static func letterShapes(of item: DictionaryItem) -> [(key: String, label: String, value: String)] {
        guard let forms = item.forms else { return [] }
        var shapes: [(key: String, label: String, value: String)] = []
        for shape in shapeKeys {
            if let value = forms[shape.key]?.trimmingCharacters(in: .whitespaces), !value.isEmpty {
                shapes.append((key: shape.key, label: shape.label, value: value))
            }
        }
        return shapes
    }

    /// The question that fits a word: letters are asked by their shape, Arabic words by their reading when
    /// `reading` is set, everything else by its meaning. nil when no distractor can be found.
    static func question(for item: DictionaryItem, among words: [DictionaryItem], subject: Subject,
                         reading: Bool) -> GameQuestion? {
        if item.isLetter, let question = letter(for: item, among: words) { return question }
        if reading {
            return self.reading(for: item, among: words)
        }
        return meaning(for: item, among: words, subject: subject)
    }

    static func meaning(for item: DictionaryItem, among words: [DictionaryItem], subject: Subject) -> GameQuestion? {
        let label: (DictionaryItem) -> String? = { candidate in
            let text: String = candidate.translation.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        guard let right = label(item) else { return nil }
        let others: [DictionaryItem] = distractors(for: item, among: words, count: 3, label: label)
        guard !others.isEmpty else { return nil }
        var choices: [GameChoice] = [GameChoice(id: item.id, text: right, detail: nil)]
        for other in others {
            choices.append(GameChoice(id: other.id, text: label(other) ?? "", detail: nil))
        }
        let instruction: String = subject == .culture ? "Quelle est la bonne définition ?" : "Que veut dire ce mot ?"
        return GameQuestion(id: UUID(), kind: .meaning, item: item, instruction: instruction, prompt: item.word,
                            caption: nil, choices: choices.shuffled())
    }

    static func reading(for item: DictionaryItem, among words: [DictionaryItem]) -> GameQuestion? {
        let label: (DictionaryItem) -> String? = { $0.reading }
        guard let right = label(item) else { return nil }
        let others: [DictionaryItem] = distractors(for: item, among: words, count: 3, label: label)
        guard !others.isEmpty else { return nil }
        var choices: [GameChoice] = [GameChoice(id: item.id, text: right, detail: nil)]
        for other in others {
            choices.append(GameChoice(id: other.id, text: label(other) ?? "", detail: nil))
        }
        return GameQuestion(id: UUID(), kind: .reading, item: item, instruction: "Comment se lit ce mot ?",
                            prompt: item.word, caption: nil, choices: choices.shuffled())
    }

    /// Shows one shape of the letter. An attached shape (début, milieu, fin) is preferred: recognising
    /// them is the hard part. The answers are then the isolated letters with their reading; for the
    /// isolated shape, the answers are the readings only.
    static func letter(for item: DictionaryItem, among words: [DictionaryItem]) -> GameQuestion? {
        let shapes = letterShapes(of: item)
        let attached = shapes.filter { $0.key != "isolated" }
        guard let shape = (attached.isEmpty ? shapes : attached).randomElement() else { return nil }
        let showsGlyphs: Bool = shape.key != "isolated"
        let letters: [DictionaryItem] = words.filter { $0.isLetter }
        let candidates: [DictionaryItem] = letters.count >= 4 ? letters : words
        let name: (DictionaryItem) -> String? = { $0.reading ?? nonEmpty($0.translation) }
        let glyph: (DictionaryItem) -> String? = { nonEmpty($0.forms?["isolated"] ?? $0.word) }
        let label: (DictionaryItem) -> String? = showsGlyphs ? glyph : name
        guard let right = label(item) else { return nil }
        let others: [DictionaryItem] = distractors(for: item, among: candidates, count: 3, label: label)
        guard !others.isEmpty else { return nil }
        var choices: [GameChoice] = [GameChoice(id: item.id, text: right, detail: showsGlyphs ? name(item) : nil)]
        for other in others {
            choices.append(GameChoice(id: other.id, text: label(other) ?? "", detail: showsGlyphs ? name(other) : nil))
        }
        return GameQuestion(id: UUID(), kind: .letter, item: item, instruction: "Quelle est cette lettre ?",
                            prompt: shape.value, caption: shape.label, choices: choices.shuffled())
    }

    /// The right translation half of the time, otherwise another word's.
    static func trueFalse(for item: DictionaryItem, among words: [DictionaryItem]) -> TrueFalseQuestion {
        if Bool.random() {
            let label: (DictionaryItem) -> String? = { nonEmpty($0.translation) }
            if let other = distractors(for: item, among: words, count: 1, label: label).first {
                return TrueFalseQuestion(id: UUID(), item: item, proposed: other.translation, isTrue: false)
            }
        }
        return TrueFalseQuestion(id: UUID(), item: item, proposed: item.translation, isTrue: true)
    }

    /// Up to `count` other words whose label differs from the item's and from each other's: same part of
    /// speech first, then any word of the subject.
    static func distractors(for item: DictionaryItem, among words: [DictionaryItem], count: Int,
                            label: (DictionaryItem) -> String?) -> [DictionaryItem] {
        var seen: Set<String> = []
        if let own = label(item) { seen.insert(normalized(own)) }
        let others: [DictionaryItem] = words.filter { $0.id != item.id }
        let samePart: [DictionaryItem] = others.filter { $0.partOfSpeech == item.partOfSpeech }.shuffled()
        let rest: [DictionaryItem] = others.filter { $0.partOfSpeech != item.partOfSpeech }.shuffled()
        var result: [DictionaryItem] = []
        for candidate in samePart + rest {
            if result.count >= count { break }
            guard let text = label(candidate) else { continue }
            let key: String = normalized(text)
            if key.isEmpty || seen.contains(key) { continue }
            seen.insert(key)
            result.append(candidate)
        }
        return result
    }

    /// Next word of a timed game: random, avoiding the last ones asked.
    static func pick(from pool: [DictionaryItem], avoiding recent: [String]) -> DictionaryItem? {
        let fresh: [DictionaryItem] = pool.filter { !recent.contains($0.id) }
        return (fresh.isEmpty ? pool : fresh).randomElement()
    }

    /// How many recent words to avoid repeating.
    static func memory(for pool: [DictionaryItem]) -> Int {
        max(0, min(pool.count - 2, 6))
    }

    /// Rounds of « Association »: `pairs` words per round with distinct words and translations, new words first.
    static func associationRounds(from pool: [DictionaryItem], rounds: Int, pairs: Int) -> [[DictionaryItem]] {
        guard !pool.isEmpty else { return [] }
        var result: [[DictionaryItem]] = []
        var queue: [DictionaryItem] = pool.shuffled()
        for _ in 0..<rounds {
            var round: [DictionaryItem] = []
            var words: Set<String> = []
            var meanings: Set<String> = []
            var attempts: Int = 0
            let maxAttempts: Int = max(pool.count, pairs) * 3
            while round.count < pairs && attempts < maxAttempts {
                attempts += 1
                if queue.isEmpty { queue = pool.shuffled() }
                let item: DictionaryItem = queue.removeFirst()
                let word: String = normalized(item.word)
                let meaning: String = normalized(item.translation)
                if word.isEmpty || meaning.isEmpty || words.contains(word) || meanings.contains(meaning) { continue }
                words.insert(word)
                meanings.insert(meaning)
                round.append(item)
            }
            if round.count >= 2 { result.append(round) }
        }
        return result
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

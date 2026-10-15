import Foundation

/// Closed word classes used to recognise grammatical variants (docs: "Évaluation, niveau 1").
enum ClosedWordSets {
    struct WordSet {
        let name: String
        let category: ErrorCategory
        let words: Set<String>
    }

    static let sets: [WordSet] = [
        WordSet(name: "pronouns", category: .grammar, words: [
            "i", "me", "my", "mine", "myself", "you", "your", "yours", "yourself", "he", "him", "his", "himself",
            "she", "her", "hers", "herself", "it", "its", "itself", "we", "us", "our", "ours", "they", "them",
            "their", "theirs"]),
        WordSet(name: "articles", category: .grammar, words: ["a", "an", "the"]),
        WordSet(name: "demonstratives", category: .grammar, words: ["this", "that", "these", "those"]),
        WordSet(name: "quantifiers", category: .grammar, words: [
            "much", "many", "some", "any", "few", "little", "lot", "lots", "more", "most", "no", "every", "each",
            "all", "both", "enough", "several"]),
        WordSet(name: "prepositions", category: .preposition, words: [
            "in", "on", "at", "to", "for", "from", "of", "with", "by", "about", "into", "under", "over", "between",
            "after", "before", "up", "down", "out", "off", "through", "during", "across", "behind", "near", "next",
            "around", "without", "against", "among", "inside", "outside", "above", "below", "beside", "until",
            "since", "towards", "toward", "along", "opposite"]),
        WordSet(name: "modals", category: .grammar, words: [
            "can", "could", "will", "would", "shall", "should", "must", "may", "might"]),
        WordSet(name: "questionWords", category: .grammar, words: [
            "what", "who", "whom", "whose", "where", "when", "why", "how", "which"]),
        WordSet(name: "conjunctions", category: .grammar, words: ["and", "or", "but", "because", "so", "if"]),
        WordSet(name: "toBe", category: .conjugation, words: ["am", "is", "are", "was", "were", "be", "been", "being"]),
        WordSet(name: "toDo", category: .conjugation, words: ["do", "does", "did", "done", "doing"]),
        WordSet(name: "toHave", category: .conjugation, words: ["have", "has", "had", "having"]),
    ]

    /// Pairs that learners confuse (wordConfusion).
    static let confusions: [Set<String>] = [
        ["than", "then"], ["there", "their", "theirs"], ["to", "too", "two"], ["your", "youre"], ["its", "it's"],
        ["whose", "who's"], ["where", "were", "wear"], ["for", "four"], ["no", "know"], ["write", "right"],
        ["buy", "by", "bye"], ["hear", "here"], ["see", "sea"], ["son", "sun"], ["one", "won"],
    ]

    static let allWords: Set<String> = {
        var all = Set<String>()
        for s in sets { all.formUnion(s.words) }
        for c in confusions { all.formUnion(c) }
        all.formUnion(["not", "never", "and", "or", "yes", "no", "please", "thanks", "ok", "okay"])
        return all
    }()

    /// auxiliary families with a tense tag, to tell conjugation from tense errors.
    static let auxiliaries: [String: (family: String, form: String)] = [
        "am": ("be", "present"), "is": ("be", "present"), "are": ("be", "present"), "be": ("be", "base"),
        "was": ("be", "past"), "were": ("be", "past"), "been": ("be", "participle"), "being": ("be", "ing"),
        "do": ("do", "present"), "does": ("do", "present"), "did": ("do", "past"), "done": ("do", "participle"),
        "doing": ("do", "ing"),
        "have": ("have", "present"), "has": ("have", "present"), "had": ("have", "past"), "having": ("have", "ing"),
    ]
}

/// Relation between two words: used for the "grammatical variant" detection of the evaluator.
struct WordClassifier: Sendable {
    let tables: ContentIndexTables

    // MARK: Variant detection

    /// Category when `user` and `expected` are two forms of the same word or belong to the same closed class.
    /// nil when they are unrelated.
    func variantCategory(user: String, expected: String) -> ErrorCategory? {
        if user == expected { return nil }
        for c in ClosedWordSets.confusions where c.contains(user) && c.contains(expected) { return .wordConfusion }
        if let a = ClosedWordSets.auxiliaries[user], let b = ClosedWordSets.auxiliaries[expected], a.family == b.family {
            return Self.tenseOrAgreement(a.form, b.form)
        }
        if let c = dictionaryFormCategory(user, expected) { return c }
        if let c = suffixCategory(user, expected) { return c }
        for set in ClosedWordSets.sets where set.words.contains(user) && set.words.contains(expected) {
            return set.category
        }
        return nil
    }

    /// Category of a missing / extra token.
    func unpairedCategory(_ token: String) -> (category: ErrorCategory, closedClass: Bool) {
        if let aux = ClosedWordSets.auxiliaries[token] { _ = aux; return (.grammar, true) }
        for set in ClosedWordSets.sets where set.words.contains(token) { return (set.category == .conjugation ? .grammar : set.category, true) }
        if token == "not" || token == "never" { return (.grammar, true) }
        return (.vocabulary, false)
    }

    /// Category of two unrelated words.
    func substitutionCategory(user: String, expected: String) -> ErrorCategory {
        if tables.dictionaryWords.contains(user) && tables.dictionaryWords.contains(expected) { return .wordConfusion }
        return .vocabulary
    }

    /// True when a learner token could be a misspelling: not a known word of the language.
    func isUnknownWord(_ token: String) -> Bool { !tables.knownWords.contains(token) }

    // MARK: Helpers

    private static func tenseOrAgreement(_ a: String, _ b: String) -> ErrorCategory {
        if a == b { return .conjugation }
        let present: Set<String> = ["present", "base"]
        return present.contains(a) && present.contains(b) ? .conjugation : .verbTense
    }

    private func dictionaryFormCategory(_ a: String, _ b: String) -> ErrorCategory? {
        guard let ea = tables.formEntries[a], let eb = tables.formEntries[b] else { return nil }
        for x in ea {
            for y in eb where x.itemId == y.itemId && x.kind != y.kind {
                return Self.kindsCategory(x.kind, y.kind)
            }
        }
        return nil
    }

    private static func kindsCategory(_ a: String, _ b: String) -> ErrorCategory {
        let kinds: Set<String> = [a, b]
        if kinds == ["base", "thirdPerson"] { return .conjugation }
        let tenseKinds: Set<String> = ["past", "pastParticiple", "ing"]
        if !kinds.isDisjoint(with: tenseKinds) { return .verbTense }
        return .grammar
    }

    /// Regular inflection candidates: (lemma, kind) with kind "s", "ed" or "ing".
    private func lemmaCandidates(_ w: String) -> [(String, String)] {
        var out: [(String, String)] = []
        let chars = Array(w)
        func add(_ s: String, _ k: String) { if s.count >= 2 { out.append((s, k)) } }
        if w.hasSuffix("ies"), w.count > 4 { add(String(w.dropLast(3)) + "y", "s") }
        if w.hasSuffix("es"), w.count > 3 { add(String(w.dropLast(2)), "s") }
        if w.hasSuffix("s"), !w.hasSuffix("ss"), w.count > 3 { add(String(w.dropLast(1)), "s") }
        if w.hasSuffix("ied"), w.count > 4 { add(String(w.dropLast(3)) + "y", "ed") }
        if w.hasSuffix("ed"), w.count > 4 {
            add(String(w.dropLast(2)), "ed"); add(String(w.dropLast(1)), "ed")
            if chars.count > 5, chars[chars.count - 3] == chars[chars.count - 4] { add(String(w.dropLast(3)), "ed") }
        }
        if w.hasSuffix("ing"), w.count > 5 {
            add(String(w.dropLast(3)), "ing"); add(String(w.dropLast(3)) + "e", "ing")
            if chars.count > 6, chars[chars.count - 4] == chars[chars.count - 5] { add(String(w.dropLast(4)), "ing") }
        }
        return out
    }

    private func suffixCategory(_ a: String, _ b: String) -> ErrorCategory? {
        guard a.count >= 3, b.count >= 3 else { return nil }
        let ca = lemmaCandidates(a) + [(a, "base")]
        let cb = lemmaCandidates(b) + [(b, "base")]
        for (la, ka) in ca {
            for (lb, kb) in cb where la == lb && ka != kb && (ka != "base" || kb != "base") {
                // Both words must be plausible: at least one is a known word.
                guard tables.knownWords.contains(a) || tables.knownWords.contains(b) else { continue }
                let kinds: Set<String> = [ka, kb]
                if kinds.contains("ed") || kinds.contains("ing") { return .verbTense }
                if kinds == ["base", "s"] {
                    let noun = tables.formEntries[la]?.contains(where: { tables.dictionaryById[$0.itemId]?.partOfSpeech.contains("noun") == true
                        && tables.dictionaryById[$0.itemId]?.partOfSpeech.contains("verb") != true }) ?? false
                    return noun ? .grammar : .conjugation
                }
                return .grammar
            }
        }
        return nil
    }
}

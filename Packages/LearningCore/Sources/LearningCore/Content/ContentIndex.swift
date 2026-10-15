import Foundation

/// One way a word can be written for a dictionary entry: the headword ("base") or one of its `forms`.
struct FormEntry: Sendable, Hashable {
    let itemId: String
    /// "base", "thirdPerson", "past", "pastParticiple", "ing", "plural", "comparative", "superlative".
    let kind: String
}

struct DictionarySearchRow: Sendable {
    let item: DictionaryItem
    let foldedWord: String
    let foldedTranslations: [String]
}

/// Precomputed lookup tables of a content bundle. Immutable, built once per `ContentIndex`.
struct ContentIndexTables: Sendable {
    let unitsById: [String: LearningUnit]
    let lessonsById: [String: Lesson]
    let lessonsInOrder: [Lesson]
    let exercisesById: [String: Exercise]
    let lessonExercisesByUnit: [String: [Exercise]]
    let dictionaryById: [String: DictionaryItem]
    let dictionaryByForm: [String: DictionaryItem]
    /// Normalized word -> forms entries (for same-lemma detection).
    let formEntries: [String: [FormEntry]]
    /// Words known to be valid in the studied language (typo detection never treats them as typos).
    let knownWords: Set<String>
    /// Words that are dictionary headwords or inflected forms.
    let dictionaryWords: Set<String>
    let introducingLessonId: [String: String]
    let lessonSequence: [String: Int]
    let lessonIndexById: [String: Int]
    let exercisesByLesson: [String: [Exercise]]
    let diagnosticExercises: [Exercise]
    let assessmentExercises: [Exercise]
    let searchRows: [DictionarySearchRow]
    let unitsInOrder: [LearningUnit]

    init(bundle: ContentBundle) {
        var units: [String: LearningUnit] = [:]
        for u in bundle.units where units[u.id] == nil { units[u.id] = u }
        unitsById = units
        unitsInOrder = bundle.units

        let ordered = bundle.lessons.sorted { ($0.sequence, $0.id) < ($1.sequence, $1.id) }
        lessonsInOrder = ordered
        var lessons: [String: Lesson] = [:]
        var seq: [String: Int] = [:]
        var lidx: [String: Int] = [:]
        var intro: [String: String] = [:]
        for (i, l) in ordered.enumerated() {
            if lessons[l.id] == nil { lessons[l.id] = l }
            seq[l.id] = l.sequence
            lidx[l.id] = i
            for u in l.introduces where intro[u] == nil { intro[u] = l.id }
        }
        lessonsById = lessons
        lessonSequence = seq
        lessonIndexById = lidx
        introducingLessonId = intro

        var all: [String: Exercise] = [:]
        var byUnit: [String: [Exercise]] = [:]
        var byLesson: [String: [Exercise]] = [:]
        for e in bundle.exercises {
            if all[e.id] == nil { all[e.id] = e }
            for u in e.unitIds { byUnit[u, default: []].append(e) }
            if let l = e.lessonId { byLesson[l, default: []].append(e) }
        }
        for e in bundle.diagnostic where all[e.id] == nil { all[e.id] = e }
        for e in bundle.assessment where all[e.id] == nil { all[e.id] = e }
        exercisesById = all
        lessonExercisesByUnit = byUnit
        exercisesByLesson = byLesson
        diagnosticExercises = bundle.diagnostic.filter { $0.deprecated != true }
        assessmentExercises = bundle.assessment.filter { $0.deprecated != true }

        var dict: [String: DictionaryItem] = [:]
        var byForm: [String: DictionaryItem] = [:]
        var forms: [String: [FormEntry]] = [:]
        var dictWords = Set<String>()
        for item in bundle.dictionary where dict[item.id] == nil { dict[item.id] = item }
        for item in bundle.dictionary {
            let w = TextNormalizer.normalize(item.word)
            if byForm[w] == nil { byForm[w] = item }
            forms[w, default: []].append(FormEntry(itemId: item.id, kind: "base"))
            dictWords.insert(w)
        }
        for item in bundle.dictionary {
            for key in (item.forms ?? [:]).keys.sorted() {
                guard let value = item.forms?[key] else { continue }
                for variant in value.split(separator: "/").map({ String($0) }) {
                    let w = TextNormalizer.normalize(variant)
                    if w.isEmpty { continue }
                    if byForm[w] == nil { byForm[w] = item }
                    forms[w, default: []].append(FormEntry(itemId: item.id, kind: key))
                    dictWords.insert(w)
                }
            }
        }
        dictionaryById = dict
        dictionaryByForm = byForm
        formEntries = forms
        dictionaryWords = dictWords

        var known = dictWords
        for u in bundle.units {
            for f in u.functionWords ?? [] { known.formUnion(TextNormalizer.tokens(f)) }
            if u.kind == .vocabulary { known.formUnion(TextNormalizer.tokens(u.title)) }
        }
        let language = bundle.language.code
        func addTokens(_ text: String) {
            for t in TextNormalizer.canonicalVariants(text, english: language == "en").first ?? [] { known.insert(t) }
        }
        for item in bundle.dictionary {
            for ex in item.examples { addTokens(ex.text) }
        }
        for e in bundle.exercises + bundle.diagnostic + bundle.assessment where e.answerLanguage(studied: language) == language {
            addTokens(e.answer)
            for a in e.acceptedAnswers { addTokens(a) }
            if let ex = e.extraExample { addTokens(ex.text) }
        }
        for e in bundle.exercises + bundle.diagnostic + bundle.assessment where e.promptLanguage == language {
            addTokens(e.prompt.replacingOccurrences(of: "___", with: " "))
        }
        known.formUnion(ClosedWordSets.allWords)
        knownWords = known

        searchRows = bundle.dictionary.map { item in
            let translations = [item.translation] + (item.otherTranslations ?? [])
            return DictionarySearchRow(item: item,
                                       foldedWord: TextNormalizer.foldAccents(TextNormalizer.normalize(item.word)),
                                       foldedTranslations: translations.map { TextNormalizer.foldAccents($0.lowercased()) })
        }
    }
}

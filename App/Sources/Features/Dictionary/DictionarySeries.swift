import Foundation
import LearningCore

// Word series of the dictionary: one series per lesson of the subject, in the course order, made of the
// words the lesson introduces. Everything is computed from the content bundle and the learner: nothing
// is stored. The « Séries » and « Jeux » modes of the dictionary are built on it.

/// Where a series stands on the learner's path. Every series can be opened, whatever its state.
enum WordSeriesState: Sendable, Hashable {
    /// Its lesson is done (or skipped thanks to the placement test).
    case done
    /// Its lesson is the next one to learn (or a lesson before it that is not done yet).
    case current
    /// Its lesson is not reached yet.
    case upcoming

    var label: String {
        switch self {
        case .done: return "Leçon faite"
        case .current: return "En cours"
        case .upcoming: return "À venir"
        }
    }
}

struct WordSeries: Identifiable, Hashable, Sendable {
    let lesson: Lesson
    /// 1-based position of the series in the course.
    let number: Int
    let words: [DictionaryItem]
    let state: WordSeriesState

    var id: String { lesson.id }
    var title: String { lesson.title }
    /// The learner's path already reached this series (its words feed the games).
    var isReached: Bool { state != .upcoming }

    /// "8 mots"
    var countText: String {
        words.count > 1 ? "\(words.count) mots" : "\(words.count) mot"
    }
}

/// Words the games draw from: the series already reached, or every word of the subject.
struct WordGamePools: Sendable {
    let reached: [DictionaryItem]
    let all: [DictionaryItem]
}

extension DictionaryItem {
    /// An Arabic letter: its `forms` hold the isolated, initial, medial and final shapes.
    var isLetter: Bool {
        partOfSpeech.trimmingCharacters(in: .whitespaces).lowercased() == "letter"
    }

    /// Latin reading of an Arabic word or letter, when the content gives one.
    var reading: String? {
        guard let value = transliteration?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

/// Pure computations (no store, no UI), kept apart so they stay easy to test.
enum WordSeriesBuilder {
    static func series(engine: LearningEngine, learner: LearnerSnapshot, now: Date) -> [WordSeries] {
        let index: ContentIndex = engine.index
        let lessons: [Lesson] = index.lessonsInOrder
        var unitsByLesson: [String: [LearningUnit]] = [:]
        for unit in index.bundle.units where unit.kind == .vocabulary && unit.deprecated != true {
            if let lessonId = unit.lessonId {
                unitsByLesson[lessonId, default: []].append(unit)
            }
        }
        let done: Set<String> = learner.completedLessonIds.union(learner.placedLessonIds)
        let next: Lesson? = engine.nextLesson(for: learner, now: now) ?? lessons.first { !done.contains($0.id) }
        let frontier: Int = next.flatMap { lesson in lessons.firstIndex { $0.id == lesson.id } } ?? lessons.count

        var result: [WordSeries] = []
        for (position, lesson) in lessons.enumerated() {
            let words: [DictionaryItem] = self.words(of: lesson, units: unitsByLesson[lesson.id] ?? [], index: index)
            guard !words.isEmpty else { continue }
            let state: WordSeriesState
            if done.contains(lesson.id) {
                state = .done
            } else if position <= frontier {
                state = .current
            } else {
                state = .upcoming
            }
            result.append(WordSeries(lesson: lesson, number: result.count + 1, words: words, state: state))
        }
        return result
    }

    /// Vocabulary of a lesson: the words it introduces (in its order), then any other unit attached to it.
    static func words(of lesson: Lesson, units: [LearningUnit], index: ContentIndex) -> [DictionaryItem] {
        var ordered: [LearningUnit] = []
        var seenUnits: Set<String> = []
        for unitId in lesson.introduces {
            guard let unit = index.unitsById[unitId], unit.kind == .vocabulary, unit.deprecated != true else { continue }
            if seenUnits.insert(unit.id).inserted { ordered.append(unit) }
        }
        for unit in units where seenUnits.insert(unit.id).inserted {
            ordered.append(unit)
        }
        var items: [DictionaryItem] = []
        var seenItems: Set<String> = []
        for unit in ordered {
            guard let itemId = unit.dictionaryItemId, let item = index.dictionaryById[itemId] else { continue }
            if seenItems.insert(item.id).inserted { items.append(item) }
        }
        return items
    }

    /// Words of the reached series, and every word of the subject (series first, then the rest of the dictionary).
    static func pools(series: [WordSeries], dictionary: [DictionaryItem]) -> WordGamePools {
        var reached: [DictionaryItem] = []
        var all: [DictionaryItem] = []
        var seen: Set<String> = []
        for entry in series {
            for item in entry.words where seen.insert(item.id).inserted {
                all.append(item)
                if entry.isReached { reached.append(item) }
            }
        }
        if all.isEmpty {
            all = dictionary.filter { !$0.translation.isEmpty }
        }
        return WordGamePools(reached: reached, all: all)
    }
}

@MainActor
extension LearningStore {
    /// One series per lesson that introduces words, in the course order.
    func wordSeries(now: Date = .now) -> [WordSeries] {
        guard let engine else { return [] }
        return WordSeriesBuilder.series(engine: engine, learner: learner, now: now)
    }

    /// Word pools of the games, from the series of this subject.
    func wordGamePools(series: [WordSeries]) -> WordGamePools {
        WordSeriesBuilder.pools(series: series, dictionary: engine?.index.bundle.dictionary ?? [])
    }

    /// The word is already scheduled for reviews: added from the dictionary, or learned in a lesson.
    func isInReviews(_ item: DictionaryItem) -> Bool {
        if isWordTracked(item.id) { return true }
        guard let unitId = item.unitId else { return false }
        return learner.memoryStates[unitId] != nil
    }

    /// The word can be added to reviews (it has a learnable unit and is not scheduled yet).
    func canAddToReviews(_ item: DictionaryItem) -> Bool {
        item.unitId != nil && !isInReviews(item)
    }
}

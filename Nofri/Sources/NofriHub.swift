import Foundation
import LearningCore
import WidgetKit

/// Nofri's layer over the shared app environment: points, daily challenge, collection, widget data.
extension AppEnvironment {
    var churchStore: LearningStore { study.store(.church) }

    private static let challengeDaysKey = "nofri.challengeDays"

    /// ISO days on which the daily challenge was completed.
    var challengeDays: [String] {
        UserDefaults.standard.stringArray(forKey: Self.challengeDaysKey) ?? []
    }

    var challengeDoneToday: Bool { challengeDays.contains(NofriWidgetData.isoDay(.now)) }

    func markChallengeDone(now: Date = .now) {
        let day = NofriWidgetData.isoDay(now)
        var days = challengeDays
        guard !days.contains(day) else { return }
        days.append(day)
        UserDefaults.standard.set(days, forKey: Self.challengeDaysKey)
    }

    var nofriPoints: Int {
        NofriGame.points(sessions: local.sessions(), challengeDays: challengeDays.count)
    }

    /// Fiches of the collection: every vocabulary fiche of the course, with whether the learner unlocked it
    /// (its lesson is validated, or the notion was already met).
    func collectionFiches() -> [NofriFiche] {
        guard let engine = churchStore.engine else { return [] }
        let learner = churchStore.learner
        var lessonOfUnit: [String: Lesson] = [:]
        for lesson in engine.index.lessonsInOrder {
            for unit in lesson.introduces where lessonOfUnit[unit] == nil { lessonOfUnit[unit] = lesson }
        }
        var out: [NofriFiche] = []
        for item in engine.index.bundle.dictionary {
            guard let unitId = item.unitId, let family = item.collection.flatMap(NofriCollection.init(rawValue:)) else { continue }
            let lesson = lessonOfUnit[unitId]
            let unlocked = (lesson.map { learner.completedLessonIds.contains($0.id) } ?? false) || learner.memoryStates[unitId] != nil
            out.append(NofriFiche(item: item, family: family, lessonTitle: lesson?.title, sequence: lesson?.sequence ?? 0,
                                  unlocked: unlocked))
        }
        return out.sorted { ($0.sequence, $0.item.word) < ($1.sequence, $1.item.word) }
    }

    /// Publishes what the lock-screen widgets show, then asks WidgetKit to redraw them.
    func publishWidgetData(now: Date = .now) {
        guard let engine = churchStore.engine else { return }
        let learner = churchStore.learner
        var facts: [String] = []
        for lesson in engine.index.lessonsInOrder where learner.completedLessonIds.contains(lesson.id) {
            for card in lesson.course ?? [] {
                if let fact = card.keyFact, !fact.isEmpty { facts.append(fact) }
            }
        }
        let points = nofriPoints
        let lastDay = local.sessions()
            .filter { $0.status == .completed && $0.subjectCode == Subject.church.code }
            .compactMap(\.completedAt).max().map { NofriWidgetData.isoDay($0) }
        let data = NofriWidgetData(facts: Array(facts.suffix(120)), streakDays: study.today.streakDays,
                                   rankTitle: NofriGame.rank(points: points).title, points: points,
                                   lastStudyDay: lastDay, nextLessonTitle: churchStore.upNextTitle)
        if data != NofriWidgetData.load() {
            data.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

struct NofriFiche: Identifiable, Hashable {
    let item: DictionaryItem
    let family: NofriCollection
    let lessonTitle: String?
    let sequence: Int
    let unlocked: Bool

    var id: String { item.id }
}

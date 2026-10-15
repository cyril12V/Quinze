import Foundation

/// Mastery score and level of a unit (docs/05-moteur-pedagogique.md, "Maîtrise").
struct MasteryCalculator: Sendable {
    let configuration: EngineConfiguration
    let fsrs: FSRS

    init(configuration: EngineConfiguration) {
        self.configuration = configuration
        self.fsrs = FSRS(configuration: configuration)
    }

    func retrievability(_ state: MemoryState, now: Date) -> Double {
        let reference = state.lastReviewAt ?? state.firstSeenAt
        return fsrs.retrievability(elapsedDays: max(0, now.timeIntervalSince(reference)) / 86_400, stability: state.stability)
    }

    /// score = 0.35 min(1, S/21) + 0.20 precision + 0.15 [production success] + 0.15 min(1, delayed/2)
    ///       + 0.10 min(1, types/3) + 0.05 min(1, noHint/3)
    func score(_ state: MemoryState) -> Double {
        let precision = state.recentResults.isEmpty ? 0 : Double(state.recentResults.filter { $0 }.count) / Double(state.recentResults.count)
        let s = 0.35 * min(1, state.stability / 21)
            + 0.20 * precision
            + 0.15 * (state.productionSuccessCount >= 1 ? 1 : 0)
            + 0.15 * min(1, Double(state.delayedSuccessCount) / 2)
            + 0.10 * min(1, Double(state.successfulExerciseTypes.count) / 3)
            + 0.05 * min(1, Double(state.noHintSuccessCount) / 3)
        return min(max(s, 0), 1)
    }

    func level(_ state: MemoryState, score: Double, retrievability r: Double) -> MasteryLevel {
        let eligible = score >= configuration.masteredThreshold
            && state.productionSuccessCount >= 1 && state.delayedSuccessCount >= 1
        if eligible && r >= EngineTuning.retrievabilityForMastered { return .mastered }
        if score >= configuration.fragileThreshold || eligible { return .fragile }
        return .learning
    }

    func report(unitId: String, state: MemoryState?, now: Date) -> MasteryReport {
        guard let state else {
            return MasteryReport(unitId: unitId, score: 0, level: .notStarted, retrievability: 0, nextReviewAt: nil)
        }
        let r = retrievability(state, now: now)
        let sc = score(state)
        return MasteryReport(unitId: unitId, score: sc, level: level(state, score: sc, retrievability: r),
                             retrievability: r, nextReviewAt: state.nextReviewAt)
    }
}

/// Error-category statistics over the most recent attempts (gap analysis, §13.2).
struct ErrorStats {
    /// Graded attempts of the window.
    let gradedCount: Int
    let counts: [ErrorCategory: Int]
    /// Errors per unit restricted to weak categories.
    let weakUnitErrors: [String: Int]
    let weakCategories: Set<ErrorCategory>

    init(attempts: [AttemptRecord], window: Int = EngineTuning.errorWindow) {
        let recent = attempts.suffix(window).filter { $0.result != .pending }
        var counts: [ErrorCategory: Int] = [:]
        for a in recent where !a.result.countsAsSuccess {
            if let c = a.errorCategory { counts[c, default: 0] += 1 }
        }
        let total = recent.count
        var weak = Set<ErrorCategory>()
        for (c, n) in counts where n >= EngineTuning.weakCategoryMinimumErrors && total > 0
            && Double(n) / Double(total) >= EngineTuning.weakCategoryRate { weak.insert(c) }
        var perUnit: [String: Int] = [:]
        for a in recent where !a.result.countsAsSuccess {
            if let c = a.errorCategory, weak.contains(c) {
                for u in a.unitIds { perUnit[u, default: 0] += 1 }
            }
        }
        gradedCount = total
        self.counts = counts
        weakUnitErrors = perUnit
        weakCategories = weak
    }

    func stats() -> [ErrorCategoryStat] {
        counts.keys.sorted { $0.rawValue < $1.rawValue }
            .map { ErrorCategoryStat(category: $0, errorCount: counts[$0] ?? 0,
                                     rate: gradedCount == 0 ? 0 : Double(counts[$0] ?? 0) / Double(gradedCount)) }
            .sorted { ($0.rate, $1.category.rawValue) > ($1.rate, $0.category.rawValue) }
    }
}

/// Recent success rate (last 30 graded attempts) used by the adaptation (§13.1). nil without enough data.
func recentPerformance(_ attempts: [AttemptRecord]) -> Double? {
    let graded = attempts.filter { $0.result != .pending }.suffix(EngineTuning.performanceWindow)
    guard graded.count >= EngineTuning.performanceMinimumAttempts else { return nil }
    return Double(graded.filter { $0.result.countsAsSuccess }.count) / Double(graded.count)
}

// MARK: - Progress

/// Share of the content learned in one module (see docs/05-moteur-pedagogique.md, "Pourcentages de progression").
public struct ModuleProgress: Codable, Hashable, Sendable, Identifiable {
    public var id: Int { module }
    public let module: Int
    public let unitsTotal: Int
    public let unitsStudied: Int
    public let unitsMastered: Int
    /// Mean mastery score over *all* units of the module (not started = 0), 0...1.
    public let fraction: Double
}

extension LearningEngine {
    var masteryCalculator: MasteryCalculator { MasteryCalculator(configuration: configuration) }

    func masteryReport(of unitId: String, learner: LearnerSnapshot, now: Date) -> MasteryReport {
        masteryCalculator.report(unitId: unitId, state: learner.memoryStates[unitId], now: now)
    }

    func buildProgress(learner: LearnerSnapshot, now: Date) -> ProgressReport {
        let calc = masteryCalculator
        let tables = index.tables
        var wordsStudied = 0, wordsMastered = 0, rulesStudied = 0, rulesMastered = 0
        var perCategory: [ProgressCategory: (total: Int, studied: Int, mastered: Int, sum: Double)] = [:]
        for cat in ProgressCategory.allCases { perCategory[cat] = (0, 0, 0, 0) }
        for unit in tables.unitsInOrder where unit.deprecated != true {
            var entry = perCategory[unit.category] ?? (0, 0, 0, 0)
            entry.total += 1
            if let state = learner.memoryStates[unit.id] {
                let report = calc.report(unitId: unit.id, state: state, now: now)
                entry.studied += 1
                entry.sum += report.score
                let mastered = report.level == .mastered
                if mastered { entry.mastered += 1 }
                if unit.kind == .vocabulary {
                    wordsStudied += 1
                    if mastered { wordsMastered += 1 }
                } else {
                    rulesStudied += 1
                    if mastered { rulesMastered += 1 }
                }
            }
            perCategory[unit.category] = entry
        }
        let graded = learner.recentAttempts.filter { $0.result != .pending }
        let successes = graded.filter { $0.result.countsAsSuccess }.count
        let calendar = Calendar.current
        var reviewsDone = 0
        for a in learner.recentAttempts {
            guard let first = a.unitIds.first, let state = learner.memoryStates[first] else { continue }
            if !calendar.isDate(state.firstSeenAt, inSameDayAs: a.answeredAt) && state.firstSeenAt < a.answeredAt { reviewsDone += 1 }
        }
        let due = learner.memoryStates.values.filter { $0.nextReviewAt <= now }.count
        let done = learner.completedLessonIds.union(learner.placedLessonIds).filter { tables.lessonsById[$0] != nil }.count
        let categories = ProgressCategory.allCases.map { cat -> CategoryProgress in
            let e = perCategory[cat] ?? (0, 0, 0, 0)
            return CategoryProgress(category: cat, unitsTotal: e.total, unitsStudied: e.studied, unitsMastered: e.mastered,
                                    averageMastery: e.studied == 0 ? 0 : e.sum / Double(e.studied))
        }
        let errors = ErrorStats(attempts: learner.recentAttempts)
        return ProgressReport(
            wordsStudied: wordsStudied, wordsMastered: wordsMastered, rulesStudied: rulesStudied, rulesMastered: rulesMastered,
            attemptCount: learner.recentAttempts.count,
            successRate: graded.isEmpty ? 0 : Double(successes) / Double(graded.count),
            reviewsDone: reviewsDone, dueReviewCount: due,
            lessonsCompleted: done, lessonsTotal: tables.lessonsInOrder.count,
            categories: categories, weakErrorCategories: errors.stats())
    }

    /// Mean mastery over all the units of each module (0 for units not started).
    public func moduleProgress(learner: LearnerSnapshot, now: Date) -> [ModuleProgress] {
        let calc = masteryCalculator
        var byModule: [Int: (total: Int, studied: Int, mastered: Int, sum: Double)] = [:]
        for unit in index.tables.unitsInOrder where unit.deprecated != true {
            var e = byModule[unit.module] ?? (0, 0, 0, 0)
            e.total += 1
            if let state = learner.memoryStates[unit.id] {
                let r = calc.report(unitId: unit.id, state: state, now: now)
                e.studied += 1
                e.sum += r.score
                if r.level == .mastered { e.mastered += 1 }
            }
            byModule[unit.module] = e
        }
        return byModule.keys.sorted().map { m in
            let e = byModule[m]!
            return ModuleProgress(module: m, unitsTotal: e.total, unitsStudied: e.studied, unitsMastered: e.mastered,
                                  fraction: e.total == 0 ? 0 : e.sum / Double(e.total))
        }
    }

    /// Global progress, 0...1: mean mastery over every unit of the content (not started = 0).
    public func overallProgress(learner: LearnerSnapshot, now: Date) -> Double {
        let total = index.tables.unitsInOrder.filter { $0.deprecated != true }.count
        guard total > 0 else { return 0 }
        let calc = masteryCalculator
        let sum = learner.memoryStates.values.reduce(0.0) { acc, st in
            index.tables.unitsById[st.unitId] == nil ? acc : acc + calc.score(st)
        }
        return min(1, sum / Double(total))
    }
}

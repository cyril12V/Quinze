import Foundation

/// Builds the sessions (docs/05-moteur-pedagogique.md, "Planification des sessions").
struct SessionPlanner {
    let engine: LearningEngine
    let learner: LearnerSnapshot
    let now: Date
    let day: LocalDay
    let calendar: Calendar
    var rng: SplitMix64

    // Derived state
    private let index: ContentIndex
    private let config: EngineConfiguration
    private let scores: [String: Double]
    private let retrievability: [String: Double]
    private let doneLessonIds: Set<String>
    /// Exercises answered today (or planned for another slot of the day): avoided unless the pool is too small.
    private let exercisesToday: Set<String>
    private let exercisesRecent: Set<String>
    private let typesTodayByUnit: [String: Set<ExerciseType>]
    private let lastTypeByUnit: [String: ExerciseType]
    private let performance: Double?
    private let errors: ErrorStats
    private(set) var unitsToday: [String]
    /// True when the learner already answered something today (in any session).
    let hadAttemptsToday: Bool
    private var used: Set<String>
    private var primaryUse: [String: Int] = [:]
    /// Last resort when the pool is too small: exercises already seen today may be served again (never twice in a session).
    private var allowRepeats = false

    init(engine: LearningEngine, learner: LearnerSnapshot, now: Date, day: LocalDay, seed: UInt64,
         salt: String, excluded: Set<String> = [], calendar: Calendar = .current) {
        self.engine = engine
        self.learner = learner
        self.now = now
        self.day = day
        self.calendar = calendar
        self.index = engine.index
        self.config = engine.configuration
        self.rng = SplitMix64(seed: seed ^ stableHash(salt))
        self.used = []
        let calc = engine.masteryCalculator
        var sc: [String: Double] = [:], rt: [String: Double] = [:]
        for (id, st) in learner.memoryStates { sc[id] = calc.score(st); rt[id] = calc.retrievability(st, now: now) }
        scores = sc
        retrievability = rt
        doneLessonIds = learner.completedLessonIds.union(learner.placedLessonIds)

        let today = learner.recentAttempts.filter { LocalDay(date: $0.answeredAt, calendar: calendar) == day }
        exercisesToday = Set(today.map { $0.exerciseId }).union(excluded)
        hadAttemptsToday = !today.isEmpty
        let since = now.addingTimeInterval(-Double(EngineTuning.recentDays) * 86_400)
        exercisesRecent = Set(learner.recentAttempts.filter { $0.answeredAt >= since }.map { $0.exerciseId })
        var types: [String: Set<ExerciseType>] = [:]
        for a in today { for u in a.unitIds { types[u, default: []].insert(a.exerciseType) } }
        typesTodayByUnit = types
        var last: [String: ExerciseType] = [:]
        for a in learner.recentAttempts { for u in a.unitIds { last[u] = a.exerciseType } }
        lastTypeByUnit = last
        performance = recentPerformance(learner.recentAttempts)
        errors = ErrorStats(attempts: learner.recentAttempts)

        var todayUnits: [String] = learner.memoryStates.values
            .filter { LocalDay(date: $0.firstSeenAt, calendar: calendar) == day }
            .sorted { ($0.firstSeenAt, $0.unitId) < ($1.firstSeenAt, $1.unitId) }
            .map { $0.unitId }
        for a in today { for u in a.unitIds.prefix(1) where !todayUnits.contains(u) && learner.memoryStates[u] != nil { todayUnits.append(u) } }
        unitsToday = todayUnits
    }

    // MARK: Situation

    /// Reviews that have been due for longer than the grace period.
    var overdueCount: Int {
        let limit = now.addingTimeInterval(-EngineTuning.overdueGraceHours * 3600)
        return learner.memoryStates.values.filter { $0.nextReviewAt <= limit }.count
    }

    var isFlooded: Bool { overdueCount > config.overdueThresholdToPauseNewMaterial }

    /// True when a lesson was completed today (its units were first seen today).
    var lessonLearnedToday: Bool {
        learner.memoryStates.values.contains { st in
            guard st.source == .lesson, LocalDay(date: st.firstSeenAt, calendar: calendar) == day,
                  let lessonId = index.tables.introducingLessonId[st.unitId] else { return false }
            return learner.completedLessonIds.contains(lessonId)
        }
    }

    private var struggling: Bool { (performance ?? 1) < EngineTuning.lowPerformance }
    private var excelling: Bool { (performance ?? 0) > EngineTuning.highPerformance }

    private func score(_ unitId: String) -> Double { scores[unitId] ?? 0 }

    /// Mastery adjusted by the recent success rate (adaptation).
    private func adaptedMastery(_ unitId: String) -> Double {
        let shift = excelling ? 0.1 : (struggling ? -0.15 : 0)
        return min(max(score(unitId) + shift, 0), 1)
    }

    // MARK: Unit pools

    private enum Age { case today, recent, old }

    private func age(of state: MemoryState) -> Age {
        let d = LocalDay(date: state.firstSeenAt, calendar: calendar)
        if d == day { return .today }
        let diff = d.days(until: day, calendar: calendar)
        return diff <= EngineTuning.recentDays ? .recent : .old
    }

    private func priorityOrder(_ states: [MemoryState]) -> [MemoryState] {
        func key(_ s: MemoryState) -> (Int, Double, String) {
            let weak = Double(min(3, errors.weakUnitErrors[s.unitId] ?? 0)) * 0.12
            return (s.nextReviewAt <= now ? 0 : 1, (retrievability[s.unitId] ?? 1) - weak, s.unitId)
        }
        return states.sorted { key($0) < key($1) }
    }

    private func pool(_ ages: Set<Age>, dueOnly: Bool, excluding: Set<String> = []) -> [String] {
        let states = learner.memoryStates.values.filter { st in
            ages.contains(age(of: st)) && !excluding.contains(st.unitId) && index.unitsById[st.unitId] != nil
                && (!dueOnly || st.nextReviewAt <= now)
        }
        return priorityOrder(Array(states)).map { $0.unitId }
    }

    private func fragileUnits(excluding: Set<String>) -> [String] {
        let calc = engine.masteryCalculator
        let states = learner.memoryStates.values.filter { st in
            guard !excluding.contains(st.unitId), index.unitsById[st.unitId] != nil else { return false }
            let level = calc.level(st, score: score(st.unitId), retrievability: retrievability[st.unitId] ?? 1)
            return level == .fragile || level == .learning && (retrievability[st.unitId] ?? 1) < 0.85
        }
        return priorityOrder(Array(states)).map { $0.unitId }
    }

    // MARK: Exercise choice

    private enum SkillMode { case byMastery, practice, production }

    private func targetSkill(_ unitId: String, _ mode: SkillMode) -> ExerciseSkill {
        let m = adaptedMastery(unitId)
        switch mode {
        case .byMastery: return m < 0.3 ? .recognition : (m < 0.6 ? .recall : .production)
        case .practice: return m < 0.3 ? .recall : .production
        case .production: return .production
        }
    }

    private func rank(_ s: ExerciseSkill) -> Int { s == .recognition ? 0 : (s == .recall ? 1 : 2) }

    private static func guidance(_ t: ExerciseType) -> Int {
        switch t {
        case .match: return 0
        case .mcq: return 1
        case .fillBlank: return 2
        case .reorder: return 3
        case .translation: return 4
        case .freeAnswer: return 5
        }
    }

    private func eligible(_ ex: Exercise, lessons: Set<String>) -> Bool {
        ex.deprecated != true && ex.pool == .lesson && !used.contains(ex.id) && (allowRepeats || !exercisesToday.contains(ex.id))
            && (ex.lessonId.map { lessons.contains($0) } ?? false)
    }

    private mutating func pickExercise(unitId: String, skill: ExerciseSkill, lessons: Set<String>,
                                       focus: Set<String> = [], requireProduction: Bool = false) -> Exercise? {
        var cands = (index.tables.lessonExercisesByUnit[unitId] ?? []).filter { eligible($0, lessons: lessons) }
        if requireProduction {
            let production = cands.filter { $0.skill == .production }
            if !production.isEmpty { cands = production }
        }
        guard !cands.isEmpty else { return nil }
        let due = Set(learner.memoryStates.values.filter { $0.nextReviewAt <= now }.map { $0.unitId })
        let targetDifficulty = 1 + 3 * adaptedMastery(unitId)
        var best: (Exercise, Double)?
        for ex in cands {
            var s = -2.0 * Double(abs(rank(ex.skill) - rank(skill)))
            if ex.primaryUnitId == unitId { s += 1.0 }
            if lastTypeByUnit[unitId] == ex.type { s -= 1.5 }
            if typesTodayByUnit[unitId]?.contains(ex.type) == true { s -= 2.0 }
            if exercisesRecent.contains(ex.id) { s -= 3.0 }
            let others = ex.unitIds.filter { $0 != unitId && (due.contains($0) || focus.contains($0)) }.count
            s += 0.6 * Double(min(others, 2))
            s -= 0.4 * abs(Double(ex.difficulty) - targetDifficulty)
            s -= 1.0 * Double(primaryUse[ex.primaryUnitId] ?? 0)
            s += rng.nextDouble() * 0.3
            if best == nil || s > best!.1 { best = (ex, s) }
        }
        return best?.0
    }

    private mutating func makeItem(_ ex: Exercise, role: ItemRole, noHint: Bool) -> SessionItem {
        used.insert(ex.id)
        primaryUse[ex.primaryUnitId, default: 0] += 1
        let m = adaptedMastery(ex.primaryUnitId)
        let presentation: PresentationMode
        switch ex.type {
        case .mcq: presentation = .choices
        case .match: presentation = .pairs
        case .reorder: presentation = .tokens
        case .fillBlank: presentation = (!noHint && m < 0.3 && ex.options != nil) ? .choices : .typed
        case .translation, .freeAnswer: presentation = .typed
        }
        let hint = !noHint && m < 0.6 && role != .activeRecall
        return SessionItem(id: rng.nextUUID(), kind: .exercise(exerciseId: ex.id), role: role,
                           presentation: presentation, hintAllowed: hint)
    }

    private mutating func card(_ kind: SessionItem.Kind, role: ItemRole) -> SessionItem {
        SessionItem(id: rng.nextUUID(), kind: kind, role: role, presentation: .typed, hintAllowed: false)
    }

    /// Up to `count` exercises on the given units (round robin), each of them a different exercise.
    private mutating func fillGroup(units: [String], count: Int, role: ItemRole, mode: SkillMode, lessons: Set<String>,
                                    noHint: Bool = false, focus: Set<String> = [], requireProduction: Bool = false) -> [SessionItem] {
        var out: [SessionItem] = []
        guard count > 0, !units.isEmpty else { return out }
        var round = 0
        while out.count < count && round < max(3, count) {
            var progressed = false
            for u in units {
                if out.count >= count { break }
                guard let ex = pickExercise(unitId: u, skill: targetSkill(u, mode), lessons: lessons, focus: focus,
                                            requireProduction: requireProduction) else { continue }
                out.append(makeItem(ex, role: role, noHint: noHint))
                progressed = true
            }
            if !progressed { break }
            round += 1
        }
        return out
    }

    private func sortGuided(_ items: [SessionItem]) -> [SessionItem] {
        items.sorted { a, b in
            guard let ea = a.exerciseId.flatMap({ index.exercisesById[$0] }),
                  let eb = b.exerciseId.flatMap({ index.exercisesById[$0] }) else { return false }
            return (Self.guidance(ea.type), ea.difficulty) < (Self.guidance(eb.type), eb.difficulty)
        }
    }

    // MARK: Sizing

    private var averageExerciseSeconds: Int {
        let values = ExerciseType.allCases.compactMap { config.estimatedSeconds[$0.rawValue] }
        return values.isEmpty ? 25 : max(1, values.reduce(0, +) / values.count)
    }

    private func exerciseCount(cardSeconds: Int) -> Int {
        let n = (config.targetSessionSeconds - cardSeconds) / averageExerciseSeconds
        return min(max(n, config.minInteractions), config.maxInteractions)
    }

    /// Largest-remainder allocation of `total` over weights.
    private func allocate(_ weights: [Double], total: Int) -> [Int] {
        let sum = weights.reduce(0, +)
        guard sum > 0, total > 0 else { return weights.map { _ in 0 } }
        let raw = weights.map { $0 / sum * Double(total) }
        var counts = raw.map { Int($0) }
        var remainder = total - counts.reduce(0, +)
        let order = raw.indices.sorted { (raw[$0] - Double(counts[$0]), -Double($0)) > (raw[$1] - Double(counts[$1]), -Double($1)) }
        for i in order where remainder > 0 { counts[i] += 1; remainder -= 1 }
        return counts
    }

    func estimatedSeconds(_ items: [SessionItem]) -> Int {
        items.reduce(0) { acc, item in
            switch item.kind {
            case .ruleCard: return acc + (config.estimatedSeconds["ruleCard"] ?? 45)
            case .wordCard: return acc + (config.estimatedSeconds["wordCard"] ?? 12)
            case .exercise(let id):
                let t = index.exercisesById[id]?.type.rawValue ?? "mcq"
                return acc + (config.estimatedSeconds[t] ?? 25)
            }
        }
    }

    private mutating func makePlan(type: SessionType, slot: SessionSlot?, lessonId: String?, newUnitIds: [String],
                                   items: [SessionItem]) -> SessionPlan {
        SessionPlan(id: rng.nextUUID(), type: type, slot: slot, day: day, lessonId: lessonId, newUnitIds: newUnitIds,
                    items: items, estimatedSeconds: estimatedSeconds(items), createdAt: now)
    }

    private func exerciseItemCount(_ items: [SessionItem]) -> Int { items.filter { $0.exerciseId != nil }.count }

    // MARK: Learning session (new lesson)

    mutating func planLearning(lesson: Lesson, slot: SessionSlot?) -> SessionPlan {
        let lessons = doneLessonIds.union([lesson.id])
        let newUnits = lesson.introduces
        var cards: [SessionItem] = []
        if lesson.introducesGrammar {
            cards.append(card(.ruleCard(unitId: lesson.grammarUnitId), role: .newMaterial))
        } else if index.unitsById[lesson.grammarUnitId] != nil, score(lesson.grammarUnitId) < 0.6 {
            cards.append(card(.ruleCard(unitId: lesson.grammarUnitId), role: .oldReview))
        }
        var words = newUnits.filter { index.unitsById[$0]?.kind == .vocabulary }
        if struggling { words = Array(words.prefix(3)) }
        for w in words { cards.append(card(.wordCard(unitId: w), role: .newMaterial)) }
        let cardSeconds = estimatedSeconds(cards)
        let n = exerciseCount(cardSeconds: cardSeconds)
        let nOld = max(1, Int((0.15 * Double(n)).rounded()))
        let nRecall = max(1, Int((0.15 * Double(n)).rounded()))

        // Warm-up: oldest due reviews.
        let lessonUnitSet = Set(newUnits)
        let warmUnits = pool([.old, .recent], dueOnly: true, excluding: lessonUnitSet)
        let warm = fillGroup(units: Array(warmUnits.prefix(nOld * 2)), count: nOld, role: .oldReview, mode: .byMastery, lessons: lessons)

        // Exercises of the lesson: cover every new unit, from the most guided to the most demanding.
        let lessonPool = (index.tables.exercisesByLesson[lesson.id] ?? []).filter { eligible($0, lessons: lessons) }
        let baseTarget = 1.0 + 3.0 * (excelling ? 0.7 : (struggling ? 0.1 : 0.4))
        var remaining = lessonPool
        var chosen: [Exercise] = []
        var covered = Set<String>()
        let nLesson = max(n - warm.count - nRecall, 1)
        let maxExtra = max(0, min(3, config.maxInteractions - (warm.count + nLesson + nRecall)))
        while !remaining.isEmpty {
            let uncovered = lessonUnitSet.subtracting(covered)
            let wantMore = chosen.count < nLesson || (!uncovered.isEmpty && chosen.count < nLesson + maxExtra)
            if !wantMore { break }
            var best: (Int, Double)?
            for (i, ex) in remaining.enumerated() {
                let gain = Set(ex.unitIds).intersection(uncovered).count
                if chosen.count >= nLesson && gain == 0 { continue }
                var s = Double(gain) * 3.0 - 0.5 * abs(Double(ex.difficulty) - baseTarget)
                if chosen.isEmpty { s += (ex.type == .mcq || ex.type == .match) ? 1.0 : 0 }
                s += rng.nextDouble() * 0.2
                if best == nil || s > best!.1 { best = (i, s) }
            }
            guard let pick = best else { break }
            let ex = remaining.remove(at: pick.0)
            chosen.append(ex)
            covered.formUnion(ex.unitIds)
        }
        var lessonItems = chosen.map { makeItem($0, role: .practice, noHint: false) }

        // Active recall: production on earlier notions.
        let recallUnits = pool([.recent, .old], dueOnly: false, excluding: lessonUnitSet.union(warm.compactMap { $0.exerciseId.flatMap { index.exercisesById[$0]?.primaryUnitId } }))
        let recall = fillGroup(units: Array(recallUnits.prefix(nRecall * 3)), count: nRecall, role: .activeRecall,
                               mode: .production, lessons: lessons, noHint: true, requireProduction: true)

        // Complete with more material when a group was short (first days).
        var fallback: [SessionItem] = []
        var guardCount = 0
        func total() -> Int { warm.count + lessonItems.count + recall.count + fallback.count }
        while total() < n && guardCount < 12 {
            guardCount += 1
            if let ex = remaining.first(where: { eligible($0, lessons: lessons) }) {
                remaining.removeAll { $0.id == ex.id }
                lessonItems.append(makeItem(ex, role: .practice, noHint: false))
                continue
            }
            let units = pool([.today, .recent, .old], dueOnly: false, excluding: [])
            let extra = fillGroup(units: Array(units.prefix(6)), count: 1, role: .practice, mode: .byMastery, lessons: lessons)
            if !extra.isEmpty { fallback += extra; continue }
            if allowRepeats { break }
            allowRepeats = true
            remaining = (index.tables.exercisesByLesson[lesson.id] ?? []).filter { eligible($0, lessons: lessons) }
        }
        lessonItems = sortGuided(lessonItems)
        let firstCount = max(1, (lessonItems.count + 2) / 3)
        lessonItems = lessonItems.enumerated().map { (i, item) in
            i < firstCount ? SessionItem(id: item.id, kind: item.kind, role: .newMaterial, presentation: item.presentation, hintAllowed: item.hintAllowed) : item
        }
        let ordered = warm + cards + lessonItems + sortGuided(fallback) + recall
        return makePlan(type: .learning, slot: slot, lessonId: lesson.id, newUnitIds: newUnits, items: ordered)
    }

    // MARK: Prerequisite remediation (instead of new material)

    mutating func planPrerequisiteRemediation(unitId: String, slot: SessionSlot?) -> SessionPlan {
        let lessons = doneLessonIds.union(index.tables.introducingLessonId[unitId].map { [$0] } ?? [])
        var cards: [SessionItem] = [card(.ruleCard(unitId: unitId), role: .oldReview)]
        if index.unitsById[unitId]?.kind == .vocabulary { cards = [card(.wordCard(unitId: unitId), role: .oldReview)] }
        let n = exerciseCount(cardSeconds: estimatedSeconds(cards))
        var items = fillGroup(units: [unitId], count: n, role: .oldReview, mode: .byMastery, lessons: lessons)
        if exerciseItemCount(items) < n {
            allowRepeats = true
            items += fillGroup(units: [unitId], count: n - exerciseItemCount(items), role: .oldReview, mode: .byMastery, lessons: lessons)
        }
        if exerciseItemCount(items) < n {
            let others = pool([.today, .recent, .old], dueOnly: false, excluding: [unitId])
            items += fillGroup(units: Array(others.prefix(8)), count: n - exerciseItemCount(items), role: .practice, mode: .byMastery, lessons: lessons)
        }
        return makePlan(type: .learning, slot: slot, lessonId: nil, newUnitIds: [], items: cards + sortGuided(items))
    }

    // MARK: Application / consolidation / extra

    private func recentNotions() -> [String] {
        let states = learner.memoryStates.values.filter { index.unitsById[$0.unitId] != nil }
            .sorted { ($1.firstSeenAt, $0.unitId) < ($0.firstSeenAt, $1.unitId) }
        return states.prefix(6).map { $0.unitId }
    }

    mutating func planDaily(type: SessionType, slot: SessionSlot?, flooded: Bool) -> SessionPlan {
        let lessons = doneLessonIds
        let n = exerciseCount(cardSeconds: 0)
        let today = unitsToday.isEmpty ? recentNotions() : unitsToday
        let todaySet = Set(unitsToday)
        // weights: practice (today), recent, old, fragile, recall
        var weights: [Double]
        switch type {
        case .consolidation: weights = [0.4, 0.0, 0.2, 0.2, 0.2]
        case .extra: weights = [0.3, 0.2, 0.5, 0.0, 0.0]
        default: weights = [0.4, 0.2, 0.2, 0.0, 0.2]
        }
        if flooded {
            let oldShare = 0.5
            let rest = max(0.0001, 1 - weights[2])
            weights = weights.enumerated().map { $0.offset == 2 ? oldShare : $0.element * (1 - oldShare) / rest }
        }
        let counts = allocate(weights, total: n)
        let noHint = type == .consolidation
        let practiceMode: SkillMode = type == .extra ? .byMastery : .practice

        var practiceUnits = today.sorted { (score($0), $0) < (score($1), $1) }
        if type == .extra { practiceUnits = fragileUnits(excluding: []) }
        var practice = fillGroup(units: practiceUnits, count: counts[0], role: .practice, mode: practiceMode, lessons: lessons,
                                 noHint: noHint, focus: todaySet)
        let recentUnits = pool([.recent], dueOnly: false, excluding: todaySet)
        var recent = fillGroup(units: recentUnits, count: counts[1], role: .recentReview, mode: .byMastery, lessons: lessons, noHint: noHint)
        let oldDue = pool([.old, .recent], dueOnly: true, excluding: todaySet)
        var old = fillGroup(units: oldDue, count: counts[2], role: .oldReview, mode: .byMastery, lessons: lessons, noHint: noHint)
        let fragile = fragileUnits(excluding: todaySet)
        let fragileItems = fillGroup(units: fragile, count: counts[3], role: .recentReview, mode: .practice, lessons: lessons, noHint: true)
        var recallPool = pool([.recent, .old], dueOnly: false, excluding: todaySet)
        if recallPool.isEmpty { recallPool = today }
        let recall = fillGroup(units: recallPool, count: counts[4], role: .activeRecall, mode: .production, lessons: lessons,
                               noHint: true, requireProduction: true)

        // Fill what a group could not provide.
        func total() -> Int { practice.count + recent.count + old.count + fragileItems.count + recall.count }
        for pass in 0..<2 where total() < n {
            if pass == 1 { allowRepeats = true }
            let before = total()
            practice += fillGroup(units: today.sorted { (score($0), $0) < (score($1), $1) }, count: n - total(), role: .practice, mode: practiceMode,
                                  lessons: lessons, noHint: noHint, focus: todaySet)
            if total() < n { recent += fillGroup(units: pool([.recent, .old], dueOnly: false, excluding: []), count: n - total(), role: .recentReview,
                                                 mode: .byMastery, lessons: lessons, noHint: noHint) }
            if total() < n { old += fillGroup(units: priorityOrder(Array(learner.memoryStates.values)).map { $0.unitId }, count: n - total(),
                                              role: .oldReview, mode: .byMastery, lessons: lessons, noHint: noHint) }
            _ = before
        }
        // Interleave the groups, most guided first inside a group.
        var queues = [sortGuided(practice), sortGuided(recent), sortGuided(old), sortGuided(fragileItems), recall]
        var items: [SessionItem] = []
        while queues.contains(where: { !$0.isEmpty }) {
            for i in queues.indices where !queues[i].isEmpty { items.append(queues[i].removeFirst()) }
        }
        return makePlan(type: type, slot: slot, lessonId: nil, newUnitIds: [], items: items)
    }

    // MARK: Focused practice

    mutating func planFocused(unitId: String) -> SessionPlan {
        var lessons = doneLessonIds
        if let l = index.tables.introducingLessonId[unitId] { lessons.insert(l) }
        let isRule = index.unitsById[unitId]?.kind != .vocabulary
        let cards = [card(isRule ? .ruleCard(unitId: unitId) : .wordCard(unitId: unitId), role: .practice)]
        let target = 8
        var items = fillGroup(units: [unitId], count: target, role: .practice, mode: .byMastery, lessons: lessons)
        if items.count < 6 { allowRepeats = true; items += fillGroup(units: [unitId], count: target - items.count, role: .practice, mode: .byMastery, lessons: lessons) }
        if items.count < 6 {
            let others = pool([.today, .recent, .old], dueOnly: false, excluding: [unitId])
            items += fillGroup(units: Array(others.prefix(4)), count: 6 - items.count, role: .practice, mode: .byMastery, lessons: lessons)
        }
        return makePlan(type: .extra, slot: nil, lessonId: nil, newUnitIds: [], items: cards + sortGuided(items))
    }

    // MARK: Assessment

    mutating func planAssessment() -> SessionPlan {
        let count = config.assessmentQuestionCount
        let tracked = Set(learner.memoryStates.keys)
        let seenIds = Set(learner.recentAttempts.map { $0.exerciseId })
        func studied(_ ex: Exercise) -> Bool {
            guard let first = ex.unitIds.first, tracked.contains(first) else { return false }
            let n = ex.unitIds.filter { tracked.contains($0) }.count
            return n * 2 >= ex.unitIds.count
        }
        var chosen: [Exercise] = []
        var chosenUnits = Set<String>()
        func take(_ candidates: [Exercise], oneByUnit: Bool) {
            var c = candidates
            // Seeded shuffle (Fisher-Yates).
            if c.count > 1 { for i in stride(from: c.count - 1, to: 0, by: -1) { c.swapAt(i, rng.nextInt(i + 1)) } }
            for ex in c where chosen.count < count && !used.contains(ex.id) && !exercisesToday.contains(ex.id) {
                if oneByUnit && chosenUnits.contains(ex.primaryUnitId) { continue }
                chosen.append(ex); used.insert(ex.id); chosenUnits.insert(ex.primaryUnitId)
            }
        }
        let assessmentPool = index.tables.assessmentExercises.filter(studied)
        take(assessmentPool.filter { !seenIds.contains($0.id) }, oneByUnit: true)
        let lessonPool = index.tables.exercisesByLesson.keys.sorted()
            .filter { doneLessonIds.contains($0) }
            .flatMap { index.tables.exercisesByLesson[$0] ?? [] }
            .filter { $0.deprecated != true && studied($0) }
        let production = lessonPool.filter { $0.skill == .production }
        let others = lessonPool.filter { $0.skill != .production }
        take(production.filter { !seenIds.contains($0.id) }, oneByUnit: true)
        take(others.filter { !seenIds.contains($0.id) }, oneByUnit: true)
        take(assessmentPool, oneByUnit: true)
        take(production, oneByUnit: true)
        take(lessonPool.filter { !seenIds.contains($0.id) }, oneByUnit: false)
        take(assessmentPool + lessonPool, oneByUnit: false)
        var items: [SessionItem] = []
        for ex in chosen {
            let presentation: PresentationMode
            switch ex.type {
            case .mcq: presentation = .choices
            case .match: presentation = .pairs
            case .reorder: presentation = .tokens
            default: presentation = .typed
            }
            items.append(SessionItem(id: rng.nextUUID(), kind: .exercise(exerciseId: ex.id), role: .assessment,
                                     presentation: presentation, hintAllowed: false))
        }
        return makePlan(type: .assessment, slot: nil, lessonId: nil, newUnitIds: [], items: items)
    }
}

// MARK: - Facade

extension LearningEngine {
    func nextLessonImpl(for learner: LearnerSnapshot, now: Date) -> Lesson? {
        LessonSelector(engine: self).nextLesson(learner, now: now)
    }

    func planSessionImpl(type: SessionType, slot: SessionSlot?, day: LocalDay,
                         learner: LearnerSnapshot, now: Date, seed: UInt64) -> SessionPlan {
        if type == .assessment { return planAssessmentImpl(day: day, learner: learner, now: now, seed: seed) }
        return planInternal(requested: type, slot: slot, day: day, learner: learner, now: now, seed: seed, excluded: [])
    }

    func planInternal(requested: SessionType, slot: SessionSlot?, day: LocalDay, learner: LearnerSnapshot,
                      now: Date, seed: UInt64, excluded: Set<String>) -> SessionPlan {
        let selector = LessonSelector(engine: self)
        // Probe planner: facts about the day (it is cheap and not used to build items).
        let probe = SessionPlanner(engine: self, learner: learner, now: now, day: day, seed: seed, salt: "probe")
        let flooded = probe.isFlooded
        let learnedToday = probe.lessonLearnedToday
        let pending = selector.firstPending(learner)
        var blocker: String?
        var lesson: Lesson?
        if let p = pending {
            if let weakest = selector.blockers(of: p, learner: learner, now: now).first { blocker = weakest.unitId } else { lesson = p }
        }
        // A prerequisite remediation only replaces the first session of the day (the others practise as usual).
        let canTeach = !flooded && (lesson != nil || (blocker != nil && !probe.hadAttemptsToday))

        var effective = requested
        switch requested {
        case .learning, .application, .consolidation:
            if !learnedToday && canTeach { effective = .learning }
            else if requested == .learning { effective = .application }
        case .extra, .diagnostic, .assessment:
            effective = .extra
        }
        // Consolidation planned from the same snapshot as an afternoon session must not repeat it.
        var exclusions = excluded
        if effective == .consolidation && slot == .evening {
            let afternoon = planInternal(requested: .application, slot: .afternoon, day: day, learner: learner, now: now, seed: seed, excluded: excluded)
            if afternoon.type == .application { exclusions.formUnion(afternoon.items.compactMap { $0.exerciseId }) }
        }
        var planner = SessionPlanner(engine: self, learner: learner, now: now, day: day, seed: seed,
                                     salt: effective.rawValue, excluded: exclusions)
        switch effective {
        case .learning:
            if let lesson { return planner.planLearning(lesson: lesson, slot: slot) }
            if let blocker { return planner.planPrerequisiteRemediation(unitId: blocker, slot: slot) }
            return planner.planDaily(type: requested == .extra ? .extra : .application, slot: slot, flooded: flooded)
        case .application, .consolidation:
            var plan = planner.planDaily(type: effective, slot: slot, flooded: flooded)
            if requested == .learning && plan.type != .learning { plan = relabel(plan, as: .learning) }
            return plan
        default:
            return planner.planDaily(type: .extra, slot: slot, flooded: flooded)
        }
    }

    private func relabel(_ plan: SessionPlan, as type: SessionType) -> SessionPlan {
        SessionPlan(id: plan.id, type: type, slot: plan.slot, day: plan.day, lessonId: plan.lessonId, newUnitIds: plan.newUnitIds,
                    items: plan.items, estimatedSeconds: plan.estimatedSeconds, createdAt: plan.createdAt)
    }

    func planFocusedPracticeImpl(unitId: String, day: LocalDay, learner: LearnerSnapshot,
                                 now: Date, seed: UInt64) -> SessionPlan {
        var planner = SessionPlanner(engine: self, learner: learner, now: now, day: day, seed: seed, salt: "focus:" + unitId)
        return planner.planFocused(unitId: unitId)
    }

    func isAssessmentDueImpl(learner: LearnerSnapshot, now: Date) -> Bool {
        guard !learner.memoryStates.isEmpty else { return false }
        let reference = learner.lastAssessmentAt ?? learner.startedAt
            ?? learner.memoryStates.values.map { $0.firstSeenAt }.min()
        guard let reference else { return false }
        return now.timeIntervalSince(reference) >= Double(configuration.assessmentIntervalDays) * 86_400
    }

    func planAssessmentImpl(day: LocalDay, learner: LearnerSnapshot, now: Date, seed: UInt64) -> SessionPlan {
        var planner = SessionPlanner(engine: self, learner: learner, now: now, day: day, seed: seed, salt: "assessment")
        return planner.planAssessment()
    }

    func dueReviewsImpl(learner: LearnerSnapshot, now: Date) -> [MemoryState] {
        let calc = masteryCalculator
        return learner.memoryStates.values
            .filter { $0.nextReviewAt <= now }
            .sorted {
                let ra = calc.retrievability($0, now: now), rb = calc.retrievability($1, now: now)
                return (ra, $0.nextReviewAt, $0.unitId) < (rb, $1.nextReviewAt, $1.unitId)
            }
    }

    func similarExerciseImpl(to exerciseId: String, learner: LearnerSnapshot,
                             excluding: Set<String>, seed: UInt64) -> Exercise? {
        guard let original = index.exercisesById[exerciseId] else { return nil }
        let unitId = original.primaryUnitId
        var allowed = learner.completedLessonIds.union(learner.placedLessonIds)
        if let l = original.lessonId { allowed.insert(l) }
        if let l = index.tables.introducingLessonId[unitId] { allowed.insert(l) }
        var rng = SplitMix64(seed: seed ^ stableHash("similar:" + exerciseId))
        var best: (Exercise, Double)?
        for ex in index.tables.lessonExercisesByUnit[unitId] ?? [] {
            guard ex.id != original.id, ex.deprecated != true, !excluding.contains(ex.id),
                  let lid = ex.lessonId, allowed.contains(lid) else { continue }
            var s = ex.primaryUnitId == unitId ? 2.0 : 0
            s += ex.skill <= original.skill ? 1.5 : -1.0
            if ex.type != original.type { s += 1.0 }
            s -= 0.3 * Double(max(0, ex.difficulty - original.difficulty))
            s += rng.nextDouble() * 0.3
            if best == nil || s > best!.1 { best = (ex, s) }
        }
        return best?.0
    }

    /// Records the completion of a session in the learner snapshot: the lesson taught by a learning session becomes
    /// "completed", an assessment sets `lastAssessmentAt`. The app calls this when the learner finishes a session.
    public func registerCompletion(of plan: SessionPlan, to learner: inout LearnerSnapshot, now: Date) {
        if learner.startedAt == nil { learner.startedAt = now }
        if plan.type == .learning, let lessonId = plan.lessonId { learner.completedLessonIds.insert(lessonId) }
        if plan.type == .assessment { learner.lastAssessmentAt = now }
    }
}

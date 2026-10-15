import Foundation

/// Dictionary lookup, search and "Apprendre ce mot" (docs/05-moteur-pedagogique.md, "Dictionnaire").
extension LearningEngine {
    private var english: Bool { index.bundle.language.code == "en" }

    func lookupImpl(_ word: String) -> DictionaryItem? {
        let normalized = TextNormalizer.normalize(word)
        guard !normalized.isEmpty else { return nil }
        let byForm = index.dictionaryByForm
        if let item = byForm[normalized] { return item }
        // A phrase typed with the apostrophe-less or hyphen variants.
        let hyphenless = normalized.replacingOccurrences(of: "-", with: " ")
        if let item = byForm[hyphenless] { return item }
        guard english, !normalized.contains(" ") else { return nil }

        // Possessive 's: "tom's" -> "tom" (only when the stem exists), then "is".
        if normalized.hasSuffix("'s"), normalized.count > 2 {
            let stem = String(normalized.dropLast(2))
            if let item = byForm[stem] { return item }
        }
        // Contractions that have no entry of their own: look the auxiliary / main verb up.
        let variants = TextNormalizer.canonicalVariants(normalized, english: true)
        for v in variants where v.count == 2 {
            for token in [v[1], v[0]] where token != normalized {
                if let item = byForm[token] { return item }
            }
        }
        // Regular inflections.
        for candidate in Self.lemmaCandidates(normalized) {
            if let item = byForm[candidate] { return item }
        }
        return nil
    }

    /// Plausible base forms of a regular English inflection (-s, -es, -ies, -ed, -d, -ing, doubled consonant, silent e).
    static func lemmaCandidates(_ w: String) -> [String] {
        var out: [String] = []
        let chars = Array(w)
        func add(_ s: String) { if s.count >= 2 && s != w && !out.contains(s) { out.append(s) } }
        if w.hasSuffix("ies"), w.count > 4 { add(String(w.dropLast(3)) + "y") }
        if w.hasSuffix("ied"), w.count > 4 { add(String(w.dropLast(3)) + "y") }
        if w.hasSuffix("es"), w.count > 3 { add(String(w.dropLast(2))) }
        if w.hasSuffix("s"), !w.hasSuffix("ss"), w.count > 2 { add(String(w.dropLast(1))) }
        if w.hasSuffix("ed"), w.count > 3 {
            add(String(w.dropLast(2))); add(String(w.dropLast(1)))
            if chars.count > 4, chars[chars.count - 3] == chars[chars.count - 4] { add(String(w.dropLast(3))) }
        }
        if w.hasSuffix("ing"), w.count > 4 {
            add(String(w.dropLast(3))); add(String(w.dropLast(3)) + "e")
            if chars.count > 5, chars[chars.count - 4] == chars[chars.count - 5] { add(String(w.dropLast(4))) }
        }
        if w.hasSuffix("er"), w.count > 3 { add(String(w.dropLast(2))); add(String(w.dropLast(1))) }
        if w.hasSuffix("est"), w.count > 4 { add(String(w.dropLast(3))); add(String(w.dropLast(2))) }
        if w.hasSuffix("ly"), w.count > 3 { add(String(w.dropLast(2))) }
        return out
    }

    func searchDictionaryImpl(_ query: String, limit: Int) -> [DictionaryItem] {
        let q = TextNormalizer.foldAccents(TextNormalizer.normalize(query))
        guard !q.isEmpty, limit > 0 else { return [] }
        let rows = index.tables.searchRows
        var out: [DictionaryItem] = []
        var seen = Set<String>()
        func add(_ r: DictionarySearchRow) { if seen.insert(r.item.id).inserted { out.append(r.item) } }
        for r in rows where r.foldedWord.hasPrefix(q) { add(r) }
        for r in rows where r.foldedWord.contains(q) { add(r) }
        for r in rows where r.foldedTranslations.contains(where: { $0.hasPrefix(q) }) { add(r) }
        for r in rows where r.foldedTranslations.contains(where: { $0.contains(q) }) { add(r) }
        return Array(out.prefix(limit))
    }

    func trackWordImpl(dictionaryItemId: String, learner: inout LearnerSnapshot, now: Date) -> MemoryState? {
        guard let item = index.dictionaryById[dictionaryItemId], let unitId = item.unitId,
              index.unitsById[unitId] != nil else { return nil }
        if let existing = learner.memoryStates[unitId] { return existing }
        let state = MemoryState(unitId: unitId, stability: EngineTuning.dictionaryStability, difficulty: 5, source: .dictionary,
                                firstSeenAt: now,
                                nextReviewAt: now.addingTimeInterval(EngineTuning.dictionaryFirstReviewHours * 3600))
        learner.memoryStates[unitId] = state
        return state
    }
}

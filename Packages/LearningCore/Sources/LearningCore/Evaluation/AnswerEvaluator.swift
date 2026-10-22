import Foundation

/// Level-1 deterministic evaluator (docs/05-moteur-pedagogique.md, "Évaluation").
struct AnswerEvaluator: Sendable {
    let index: ContentIndex
    let classifier: WordClassifier

    init(index: ContentIndex) {
        self.index = index
        self.classifier = WordClassifier(tables: index.tables)
    }

    private var studiedLanguage: String { index.bundle.language.code }

    // MARK: Entry point

    func evaluate(_ ex: Exercise, _ submission: AnswerSubmission) -> Evaluation {
        switch ex.type {
        case .match: return evaluateMatch(ex, submission)
        case .reorder: return evaluateReorder(ex, submission)
        case .mcq, .fillBlank, .translation, .freeAnswer: return evaluateText(ex, submission)
        }
    }

    // MARK: Shared pieces

    private func isEnglish(_ ex: Exercise) -> Bool { ex.answerLanguage(studied: studiedLanguage) == "en" }

    private func acceptedTexts(_ ex: Exercise) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for a in [ex.answer] + ex.acceptedAnswers where !a.isEmpty && seen.insert(a).inserted { out.append(a) }
        if ex.type == .fillBlank, ex.prompt.contains("___") {
            for a in out { 
                let full = ex.prompt.replacingOccurrences(of: "___", with: a)
                if seen.insert(full).inserted { out.append(full) }
            }
        }
        return out
    }

    private func joinedSet(_ variants: [[String]]) -> Set<String> { Set(variants.map { $0.joined(separator: " ") }) }

    private func matchPattern(_ ex: Exercise, userVariants: [[String]], english: Bool) -> ErrorPattern? {
        guard let patterns = ex.errorPatterns, !patterns.isEmpty else { return nil }
        let userSet = joinedSet(userVariants)
        for p in patterns {
            guard let eq = p.equals else { continue }
            if !userSet.isDisjoint(with: joinedSet(TextNormalizer.canonicalVariants(eq, english: english))) { return p }
        }
        var best: (pattern: ErrorPattern, length: Int)?
        for p in patterns {
            guard let c = p.contains else { continue }
            let needles = TextNormalizer.canonicalVariants(c, english: english)
            for needle in needles where !needle.isEmpty {
                if userVariants.contains(where: { TextNormalizer.containsSequence($0, needle) }) {
                    if best == nil || needle.count > best!.length { best = (p, needle.count) }
                    break
                }
            }
        }
        return best?.pattern
    }

    // MARK: Alignment

    struct AlignOp {
        enum Kind { case same, sub, extra, missing }
        var kind: Kind
        var user: String
        var expected: String
    }

    private func isTypo(_ u: String, _ e: String) -> Bool {
        e.count >= 3 && classifier.isUnknownWord(u) && damerauLevenshtein(u, e) <= (e.count <= 5 ? 1 : 2)
    }

    private func align(_ user: [String], _ expected: [String], english: Bool, typoAllowed: Bool) -> (cost: Double, ops: [AlignOp]) {
        let n = user.count, m = expected.count
        var dp = [[Double]](repeating: [Double](repeating: 0, count: m + 1), count: n + 1)
        var back = [[UInt8]](repeating: [UInt8](repeating: 0, count: m + 1), count: n + 1)
        if n > 0 { for i in 1...n { dp[i][0] = Double(i); back[i][0] = 2 } }
        if m > 0 { for j in 1...m { dp[0][j] = Double(j); back[0][j] = 3 } }
        if n > 0 && m > 0 {
            for i in 1...n {
                for j in 1...m {
                    let u = user[i - 1], e = expected[j - 1]
                    var sub = 1.0
                    if u == e { sub = 0 }
                    else if english && classifier.variantCategory(user: u, expected: e) != nil { sub = 0.6 }
                    else if typoAllowed && isTypo(u, e) { sub = 0.5 }
                    var best = dp[i - 1][j - 1] + sub, dir: UInt8 = 1
                    if dp[i - 1][j] + 1 < best { best = dp[i - 1][j] + 1; dir = 2 }
                    if dp[i][j - 1] + 1 < best { best = dp[i][j - 1] + 1; dir = 3 }
                    dp[i][j] = best; back[i][j] = dir
                }
            }
        }
        var ops: [AlignOp] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            switch back[i][j] {
            case 1:
                let u = user[i - 1], e = expected[j - 1]
                ops.append(AlignOp(kind: u == e ? .same : .sub, user: u, expected: e)); i -= 1; j -= 1
            case 2:
                ops.append(AlignOp(kind: .extra, user: user[i - 1], expected: "")); i -= 1
            default:
                ops.append(AlignOp(kind: .missing, user: "", expected: expected[j - 1])); j -= 1
            }
        }
        return (dp[n][m], ops.reversed())
    }

    struct ErrorItem {
        var kind: AlignOp.Kind
        var category: ErrorCategory
        var clear: Bool
        var feedback: String
    }

    struct Analysis {
        var diffs: [TokenDiff] = []
        var typos: [(user: String, expected: String)] = []
        var errors: [ErrorItem] = []
        var sameCount = 0
        var expectedCount = 0
    }

    private func analyze(_ ops: [AlignOp], english: Bool, typoAllowed: Bool) -> Analysis {
        var a = Analysis()
        for op in ops {
            switch op.kind {
            case .same:
                a.diffs.append(TokenDiff(text: op.user, expected: nil, status: .same)); a.sameCount += 1; a.expectedCount += 1
            case .sub:
                a.expectedCount += 1
                if english, let cat = classifier.variantCategory(user: op.user, expected: op.expected) {
                    a.diffs.append(TokenDiff(text: op.user, expected: op.expected, status: .wrong))
                    a.errors.append(ErrorItem(kind: .sub, category: cat, clear: true,
                                              feedback: "Le mot « \(op.user) » ne convient pas ici : on attend « \(op.expected) »."))
                } else if typoAllowed && isTypo(op.user, op.expected) {
                    a.diffs.append(TokenDiff(text: op.user, expected: op.expected, status: .typo))
                    a.typos.append((op.user, op.expected))
                } else {
                    a.diffs.append(TokenDiff(text: op.user, expected: op.expected, status: .wrong))
                    let cat = english ? classifier.substitutionCategory(user: op.user, expected: op.expected) : .vocabulary
                    a.errors.append(ErrorItem(kind: .sub, category: cat, clear: false,
                                              feedback: "Le mot « \(op.user) » ne convient pas ici : on attend « \(op.expected) »."))
                }
            case .extra:
                a.diffs.append(TokenDiff(text: op.user, expected: nil, status: .extra))
                let c = english ? classifier.unpairedCategory(op.user) : (category: ErrorCategory.vocabulary, closedClass: false)
                a.errors.append(ErrorItem(kind: .extra, category: c.category, clear: false,
                                          feedback: "Le mot « \(op.user) » est en trop."))
            case .missing:
                a.expectedCount += 1
                a.diffs.append(TokenDiff(text: "", expected: op.expected, status: .missing))
                let c = english ? classifier.unpairedCategory(op.expected) : (category: ErrorCategory.vocabulary, closedClass: false)
                a.errors.append(ErrorItem(kind: .missing, category: c.category, clear: false,
                                          feedback: "Il manque « \(op.expected) »."))
            }
        }
        return a
    }

    private func typoNote(_ typos: [(user: String, expected: String)]) -> String {
        "Attention à l'orthographe : " + typos.map { "« \($0.user) » → « \($0.expected) »" }.joined(separator: " ; ") + "."
    }

    private func positionalDiff(_ user: [String], _ expected: [String]) -> [TokenDiff] {
        var diffs: [TokenDiff] = []
        for i in 0..<max(user.count, expected.count) {
            if i < user.count && i < expected.count {
                diffs.append(user[i] == expected[i] ? TokenDiff(text: user[i], expected: nil, status: .same)
                                                    : TokenDiff(text: user[i], expected: expected[i], status: .wrong))
            } else if i < user.count {
                diffs.append(TokenDiff(text: user[i], expected: nil, status: .extra))
            } else {
                diffs.append(TokenDiff(text: "", expected: expected[i], status: .missing))
            }
        }
        return diffs
    }

    private struct Maker {
        let ex: Exercise
        let raw: String
        func callAsFunction(_ r: AttemptResult, _ expected: String? = nil, _ category: ErrorCategory? = nil,
                            _ feedback: String? = nil, _ typoNote: String? = nil, _ diff: [TokenDiff] = [],
                            _ ai: Bool = false) -> Evaluation {
            Evaluation(result: r, expectedAnswer: expected ?? ex.answer, userAnswer: raw, errorCategory: category,
                       feedback: feedback, typoNote: typoNote, diff: diff, needsAIReview: ai)
        }
    }

    // MARK: Text exercises (mcq, fill_blank, translation, free_answer)

    private func evaluateText(_ ex: Exercise, _ submission: AnswerSubmission) -> Evaluation {
        let english = isEnglish(ex)
        let raw = submission.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        var isChoice = ex.type == .mcq
        if case .choice = submission { isChoice = true }
        let make = Maker(ex: ex, raw: raw)
        let userTokens = TextNormalizer.tokens(raw)
        if userTokens.isEmpty {
            return make(.incorrect, nil, nil, "Tu n'as pas encore répondu.")
        }
        guard case .matches = submission else {
            return evaluateTextTokens(ex, raw: raw, english: english, isChoice: isChoice, make: make)
        }
        return make(.incorrect, nil, nil, "Ce type de réponse ne convient pas à cet exercice.")
    }

    private func evaluateTextTokens(_ ex: Exercise, raw: String, english: Bool, isChoice: Bool,
                                    make: Maker) -> Evaluation {
        let accepted = acceptedTexts(ex)
        let userVariants = TextNormalizer.canonicalVariants(raw, english: english)
        let acceptedVariants = accepted.map { TextNormalizer.canonicalVariants($0, english: english) }
        let userSet = joinedSet(userVariants)

        // 1. exact (canonical) match
        for (i, av) in acceptedVariants.enumerated() where !userSet.isDisjoint(with: joinedSet(av)) {
            return make(.correct, i == 0 ? nil : accepted[0], nil, nil, nil, [], false)
        }

        // 2. anticipated error patterns
        let tokensForDiff = userVariants.first ?? []
        func bestAlignment(typoAllowed: Bool) -> (index: Int, ops: [AlignOp], expectedTokens: [String], userTokens: [String], cost: Double)? {
            var best: (Int, [AlignOp], [String], [String], Double)?
            var evaluations = 0
            for (ai, avs) in acceptedVariants.enumerated() {
                for av in avs.prefix(8) {
                    for uv in userVariants.prefix(8) {
                        evaluations += 1
                        if evaluations > 160 { break }
                        let r = align(uv, av, english: english, typoAllowed: typoAllowed)
                        if best == nil || r.cost < best!.4 - 1e-9 { best = (ai, r.ops, av, uv, r.cost) }
                    }
                }
            }
            return best.map { (index: $0.0, ops: $0.1, expectedTokens: $0.2, userTokens: $0.3, cost: $0.4) }
        }
        let typoAllowed = !isChoice && english

        if let pattern = matchPattern(ex, userVariants: userVariants, english: english) {
            var diff: [TokenDiff] = []
            var expected = ex.answer
            if let best = bestAlignment(typoAllowed: typoAllowed) {
                diff = analyze(best.ops, english: english, typoAllowed: typoAllowed).diffs
                expected = accepted[best.index]
            }
            return make(.incorrect, expected, pattern.category, pattern.feedback, nil, diff, false)
        }

        // Accent-only and apostrophe-only differences are accepted with a remark (typed answers only:
        // choices may differ by a single diacritic, e.g. Arabic بَ / بِ).
        let foldedUser = Set(userSet.map { TextNormalizer.foldAccents($0) })
        let accentNote = studiedLanguage == "ar" ? "Attention aux voyelles et aux signes (harakat)." : "Attention aux accents."
        for (i, av) in acceptedVariants.enumerated() where !isChoice
            && !foldedUser.isDisjoint(with: Set(joinedSet(av).map { TextNormalizer.foldAccents($0) })) {
            return make(.correctWithTypo, i == 0 ? nil : accepted[0], nil, nil, accentNote, [], false)
        }
        if english {
            let lenientSet = joinedSet(TextNormalizer.canonicalVariants(raw, english: true, lenient: true))
            for (i, av) in acceptedVariants.enumerated() where !lenientSet.isDisjoint(with: joinedSet(av)) {
                return make(.correctWithTypo, i == 0 ? nil : accepted[0], nil, nil, "Attention à l'apostrophe : « don't », « I'm »…", [], false)
            }
        }

        // 3. open free answers: requirements
        if let req = ex.requirements {
            return evaluateRequirements(ex, req: req, raw: raw, english: english, userVariants: userVariants, make: make)
        }

        guard let best = bestAlignment(typoAllowed: typoAllowed) else {
            return make(.incorrect, nil, .grammar, nil, nil, [], false)
        }
        let expectedText = accepted[best.index]

        // 4. same words, other order
        let anagram = userVariants.contains { uv in
            acceptedVariants.contains { avs in avs.contains { av in uv != av && uv.sorted() == av.sorted() } }
        }
        if anagram {
            var diff = positionalDiff(tokensForDiff, best.expectedTokens)
            for av in acceptedVariants.flatMap({ $0 }) {
                for uv in userVariants where uv != av && uv.sorted() == av.sorted() { diff = positionalDiff(uv, av); break }
            }
            return make(.incorrect, expectedText, .wordOrder, "L'ordre des mots n'est pas correct.", nil, diff, false)
        }

        // 5. word-level analysis
        let analysis = analyze(best.ops, english: english, typoAllowed: typoAllowed)
        let production = ex.type == .translation || ex.type == .freeAnswer
        if analysis.errors.isEmpty {
            if analysis.typos.count <= 2 && !analysis.typos.isEmpty {
                return make(.correctWithTypo, expectedText, nil, nil, typoNote(analysis.typos), analysis.diffs, false)
            }
            return make(.incorrect, expectedText, .spelling, "Plusieurs fautes d'orthographe : vérifie chaque mot.", nil, analysis.diffs, false)
        }
        let feedback = analysis.errors.prefix(2).map { $0.feedback }.joined(separator: " ")
        let category = analysis.errors[0].category
        let userCount = best.userTokens.count
        let onlyMissing = analysis.errors.allSatisfy { $0.kind == .missing }
        let ratio = analysis.expectedCount == 0 ? 0 : Double(analysis.sameCount + analysis.typos.count) / Double(analysis.expectedCount)
        if production && onlyMissing && ratio >= 0.6 && userCount >= 1 {
            return make(.partial, expectedText, category, feedback, analysis.typos.isEmpty ? nil : typoNote(analysis.typos), analysis.diffs, false)
        }
        if analysis.errors.allSatisfy({ $0.clear }) {
            return make(.incorrect, expectedText, category, feedback, nil, analysis.diffs, false)
        }
        if production && userCount >= 2 {
            return make(.pending, expectedText, nil, nil, nil, analysis.diffs, true)
        }
        return make(.incorrect, expectedText, category, feedback, nil, analysis.diffs, false)
    }

    // MARK: Open free answers

    private func evaluateRequirements(_ ex: Exercise, req: AnswerRequirements, raw: String, english: Bool,
                                      userVariants: [[String]],
                                      make: Maker) -> Evaluation {
        func present(_ phrase: String) -> Bool {
            let needles = TextNormalizer.canonicalVariants(phrase, english: english)
            return needles.contains { n in !n.isEmpty && userVariants.contains { TextNormalizer.containsSequence($0, n) } }
        }
        if let minWords = req.minWords, TextNormalizer.tokens(raw).count < minWords {
            return make(.incorrect, nil, .instruction, "Ta phrase doit contenir au moins \(minWords) mots.", nil, [], false)
        }
        for group in req.mustInclude ?? [] where !group.contains(where: present) {
            // A near form of a required word (e.g. "play" for "plays") is reported as a grammar error.
            let userTokens = userVariants.first ?? []
            for alt in group {
                for token in userTokens {
                    let altTokens = TextNormalizer.tokens(alt)
                    if altTokens.count == 1, english, let cat = classifier.variantCategory(user: token, expected: altTokens[0]) {
                        return make(.incorrect, nil, cat, "Le mot « \(token) » ne convient pas ici : on attend « \(altTokens[0]) ».", nil, [], false)
                    }
                }
            }
            let shown = group.prefix(5).map { "« \($0) »" }
            let feedback = group.count == 1
                ? "Ta phrase doit contenir \(shown[0])."
                : "Ta phrase doit contenir l'un de ces mots : \(shown.joined(separator: ", "))\(group.count > 5 ? "…" : "")."
            return make(.incorrect, nil, .instruction, feedback, nil, [], false)
        }
        for bad in req.mustNotInclude ?? [] where present(bad) {
            return make(.incorrect, nil, .instruction, "Évite d'utiliser « \(bad) » dans ta phrase.", nil, [], false)
        }
        return make(.pending, nil, nil, nil, nil, [], true)
    }

    // MARK: Reorder

    private func evaluateReorder(_ ex: Exercise, _ submission: AnswerSubmission) -> Evaluation {
        let english = isEnglish(ex)
        let raw = submission.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        func make(_ r: AttemptResult, expected: String? = nil, category: ErrorCategory? = nil, feedback: String? = nil,
                  diff: [TokenDiff] = []) -> Evaluation {
            Evaluation(result: r, expectedAnswer: expected ?? ex.answer, userAnswer: raw, errorCategory: category,
                       feedback: feedback, diff: diff)
        }
        if case .matches = submission { return make(.incorrect, feedback: "Ce type de réponse ne convient pas à cet exercice.") }
        let userVariants = TextNormalizer.canonicalVariants(raw, english: english)
        if userVariants.first?.isEmpty ?? true { return make(.incorrect, feedback: "Tu n'as pas encore remis les mots dans l'ordre.") }
        let accepted = acceptedTexts(ex)
        let acceptedVariants = accepted.map { TextNormalizer.canonicalVariants($0, english: english) }
        let userSet = joinedSet(userVariants)
        for (i, av) in acceptedVariants.enumerated() where !userSet.isDisjoint(with: joinedSet(av)) {
            return make(.correct, expected: i == 0 ? nil : accepted[0])
        }
        // Closest accepted order for the diff.
        var bestDiff: [TokenDiff] = []
        var bestExpected = ex.answer
        var bestScore = Int.max
        for (i, avs) in acceptedVariants.enumerated() {
            for av in avs.prefix(8) {
                for uv in userVariants.prefix(8) {
                    let diff = positionalDiff(uv, av)
                    let wrong = diff.filter { $0.status != .same }.count
                    if wrong < bestScore { bestScore = wrong; bestDiff = diff; bestExpected = accepted[i] }
                }
            }
        }
        if let pattern = matchPattern(ex, userVariants: userVariants, english: english) {
            return make(.incorrect, expected: bestExpected, category: pattern.category, feedback: pattern.feedback, diff: bestDiff)
        }
        return make(.incorrect, expected: bestExpected, category: .wordOrder,
                    feedback: "L'ordre des mots n'est pas correct.", diff: bestDiff)
    }

    // MARK: Match

    private func pairKey(_ p: MatchPair) -> String {
        TextNormalizer.canonicalForm(p.left, english: true) + "\u{1F}" + TextNormalizer.canonicalForm(p.right, english: false)
    }

    private func parsePairs(_ text: String) -> [MatchPair] {
        text.components(separatedBy: ";").compactMap { chunk in
            let parts = chunk.components(separatedBy: "=")
            guard parts.count == 2 else { return nil }
            return MatchPair(left: parts[0].trimmingCharacters(in: .whitespaces), right: parts[1].trimmingCharacters(in: .whitespaces))
        }
    }

    private func evaluateMatch(_ ex: Exercise, _ submission: AnswerSubmission) -> Evaluation {
        let expected = ex.pairs ?? parsePairs(ex.answer)
        var given: [MatchPair]
        switch submission {
        case .matches(let p): given = p
        case .text(let t), .choice(let t): given = parsePairs(t)
        case .ordering: given = []
        }
        let expectedKeys = Set(expected.map(pairKey))
        var seen = Set<String>()
        var found = 0
        var wrong: [MatchPair] = []
        for p in given {
            let key = pairKey(p)
            guard seen.insert(key).inserted else { continue }
            if expectedKeys.contains(key) { found += 1 } else { wrong.append(p) }
        }
        let total = expected.count
        let result: AttemptResult
        if found == total && wrong.isEmpty { result = .correct }
        else if total > 0 && found * 2 >= total { result = .partial }
        else { result = .incorrect }
        var feedback: String?
        if result != .correct {
            feedback = wrong.isEmpty
                ? "Il manque des associations."
                : "Associations à revoir : " + wrong.prefix(3).map { "« \($0.left) = \($0.right) »" }.joined(separator: ", ") + "."
        }
        return Evaluation(result: result, expectedAnswer: ex.answer, userAnswer: submission.displayText,
                          errorCategory: result == .correct ? nil : .vocabulary, feedback: feedback,
                          wrongPairs: wrong)
    }
}

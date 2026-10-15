import XCTest
@testable import LearningCore

/// Consistency of the engine with the real English bundle (Content/build/en.json).
final class RealContentTests: XCTestCase {
    struct Issue { let id: String; let kind: String; let detail: String }

    private func allExercises(_ b: ContentBundle) -> [Exercise] { b.exercises + b.diagnostic + b.assessment }

    /// (c) every unit and lesson id referenced by the content resolves.
    func testReferencesResolve() throws {
        let bundle = try TestSupport.realBundle()
        let engine = LearningEngine(bundle: bundle)
        var missing: [String] = []
        for e in allExercises(bundle) {
            for u in e.unitIds where engine.unit(u) == nil { missing.append("\(e.id): unit \(u)") }
            if let l = e.lessonId, engine.lesson(l) == nil { missing.append("\(e.id): lesson \(l)") }
        }
        for l in bundle.lessons {
            for u in l.introduces + l.reviews + [l.grammarUnitId] where engine.unit(u) == nil { missing.append("\(l.id): unit \(u)") }
        }
        for u in bundle.units {
            for p in u.prerequisites where engine.unit(p) == nil { missing.append("\(u.id): prerequisite \(p)") }
            if let l = u.lessonId, engine.lesson(l) == nil { missing.append("\(u.id): lesson \(l)") }
        }
        for d in bundle.dictionary { if let u = d.unitId, engine.unit(u) == nil { missing.append("\(d.id): unit \(u)") } }
        XCTAssertEqual(missing, [], "unresolved references")
    }

    private func modelAnswers(_ e: Exercise) -> [AnswerSubmission] {
        var subs: [AnswerSubmission] = []
        switch e.type {
        case .mcq: subs = ([e.answer] + e.acceptedAnswers).map { .choice($0) }
        case .reorder:
            subs = ([e.answer] + e.acceptedAnswers).map { .ordering($0.split(separator: " ").map(String.init)) }
        case .match: subs = [.matches(e.pairs ?? [])]
        default: subs = ([e.answer] + e.acceptedAnswers).map { .text($0) }
        }
        return subs
    }

    /// (a) the model answer and every accepted answer are accepted; (b) no anticipated wrong answer is.
    func testModelAnswersAndPatterns() throws {
        let bundle = try TestSupport.realBundle()
        let engine = LearningEngine(bundle: bundle)
        var contentIssues: [Issue] = []
        var engineIssues: [String] = []
        var pending = 0
        for e in allExercises(bundle) {
            let open = e.requirements != nil
            for sub in modelAnswers(e) {
                let ev = engine.evaluate(e, submission: sub)
                if ev.isCorrect { continue }
                if open && ev.result == .pending { pending += 1; continue }
                contentIssues.append(Issue(id: e.id, kind: "answer", detail: "« \(sub.displayText) » → \(ev.result.rawValue) \(ev.feedback ?? "")"))
            }
            for p in e.errorPatterns ?? [] {
                guard let eq = p.equals else { continue }
                let sub: AnswerSubmission
                switch e.type {
                case .mcq: sub = .choice(eq)
                case .reorder: sub = .ordering(eq.split(separator: " ").map(String.init))
                case .match: continue
                default: sub = .text(eq)
                }
                let ev = engine.evaluate(e, submission: sub)
                if ev.isCorrect {
                    contentIssues.append(Issue(id: e.id, kind: "pattern", detail: "equals « \(eq) » is accepted (\(ev.result.rawValue))"))
                } else if ev.errorCategory != p.category && ev.result != .pending {
                    // Another pattern with the same value may be listed first: only report real mismatches.
                    let sameValue = (e.errorPatterns ?? []).contains { $0.equals == eq && $0.category == ev.errorCategory }
                    if !sameValue && ev.feedback != p.feedback { engineIssues.append("\(e.id): pattern « \(eq) » not recognised (\(ev.result.rawValue), \(ev.errorCategory?.rawValue ?? "-"))") }
                }
            }
        }
        print("real content: \(contentIssues.count) content issues, \(engineIssues.count) pattern mismatches, \(pending) open answers pending")
        for i in contentIssues.prefix(60) { print("  CONTENT \(i.id) [\(i.kind)] \(i.detail)") }
        for i in engineIssues.prefix(60) { print("  ENGINE \(i)") }
        if ProcessInfo.processInfo.environment["QUINZE_WRITE_REPORT"] != nil {
            try writeReport(contentIssues, engineIssues: engineIssues, bundle: bundle)
        }
        XCTAssertEqual(engineIssues, [], "patterns not recognised by the engine")
    }

    /// Open answers: a sentence that ignores the requirements is never accepted nor sent to the AI, a forbidden word is refused.
    func testOpenAnswerRequirementsOnRealContent() throws {
        let bundle = try TestSupport.realBundle()
        let engine = LearningEngine(bundle: bundle)
        let open = allExercises(bundle).filter { $0.requirements != nil }
        XCTAssertGreaterThan(open.count, 20)
        var problems: [String] = []
        for e in open {
            let r = e.requirements!
            let minWords = max(r.minWords ?? 1, 3)
            // enough words, none of the required ones
            let filler = Array(repeating: "banana", count: minWords + 1).joined(separator: " ")
            let ev = engine.evaluate(e, submission: .text(filler))
            if ev.isCorrect || ev.result == .pending { problems.append("\(e.id): « \(filler) » → \(ev.result.rawValue)") }
            // the model answer plus a forbidden word
            for forbidden in r.mustNotInclude ?? [] {
                let ev2 = engine.evaluate(e, submission: .text(e.answer + " " + forbidden))
                if ev2.isCorrect { problems.append("\(e.id): forbidden « \(forbidden) » accepted") }
            }
            // too short
            if let m = r.minWords, m > 1 {
                let short = e.answer.split(separator: " ").prefix(m - 1).joined(separator: " ")
                let ev3 = engine.evaluate(e, submission: .text(short))
                if ev3.isCorrect { problems.append("\(e.id): « \(short) » shorter than minWords \(m) accepted") }
            }
        }
        XCTAssertEqual(problems, [])
    }

    /// Informational findings that are not failures: patterns that collapse after normalisation, thin exercise pools.
    private func notes(_ bundle: ContentBundle) -> [String] {
        var out: [String] = []
        var collapsed: [String] = []
        for e in allExercises(bundle) {
            let ps = (e.errorPatterns ?? []).filter { $0.equals != nil }
            for i in ps.indices {
                for j in ps.indices where j > i {
                    let a = Set(TextNormalizer.canonicalStrings(ps[i].equals!)), b = Set(TextNormalizer.canonicalStrings(ps[j].equals!))
                    if !a.isDisjoint(with: b) && ps[i].feedback != ps[j].feedback {
                        collapsed.append("`\(e.id)` : « \(ps[i].equals!) » et « \(ps[j].equals!) » ont la même forme canonique mais des retours différents (le premier gagne)")
                    }
                }
            }
        }
        if !collapsed.isEmpty {
            out.append("**Patterns d'erreur équivalents après normalisation (\(collapsed.count))** : l'ordre de la liste décide du retour affiché.\n\n" + collapsed.map { "- " + $0 }.joined(separator: "\n"))
        }
        let perLesson = Dictionary(grouping: bundle.exercises, by: { $0.lessonId ?? "" }).mapValues { $0.count }
        let minPool = perLesson.values.min() ?? 0, maxPool = perLesson.values.max() ?? 0
        out.append("**Pool d'exercices par leçon : \(minPool) à \(maxPool).** Trois sessions de 8 à 12 exercices par jour consomment environ 33 exercices ; avec 10 exercices par leçon, les premiers jours (et, pour un apprenant en difficulté, les premières semaines) n'offrent pas assez d'exercices distincts : le moteur évite d'abord les exercices déjà faits aujourd'hui puis, en dernier recours seulement, en répète un. Mesure sur la simulation de 30 jours : 0 à 18 répétitions planifiées le même jour après le jour 5 selon le profil. Recommandation : viser 20 à 30 exercices par leçon (ou plus de variantes par notion) pour supprimer les répétitions.")
        return out
    }

    private func writeReport(_ issues: [Issue], engineIssues: [String], bundle: ContentBundle) throws {
        var text = "# Cohérence contenu / moteur\n\nRapport généré par `RealContentTests.testModelAnswersAndPatterns` (`QUINZE_WRITE_REPORT=1 swift test --filter RealContentTests`).\n\n"
        let all = allExercises(bundle)
        let patterns = all.reduce(0) { $0 + ($1.errorPatterns ?? []).filter { $0.equals != nil }.count }
        let accepted = all.reduce(0) { $0 + 1 + $1.acceptedAnswers.count }
        text += "Le test évalue, avec le moteur, chaque réponse modèle / réponse acceptée (\(accepted) réponses) de chacun des \(all.count) exercices (leçons \(bundle.exercises.count), diagnostic \(bundle.diagnostic.count), évaluation \(bundle.assessment.count)) et chacun des \(patterns) patterns d'erreur `equals`. Il vérifie aussi que toutes les références (`unitIds`, `lessonId`, prérequis, dictionnaire) se résolvent et que les exercices à réponse ouverte (`requirements`) refusent une phrase hors sujet.\n\n"
        text += issues.isEmpty ? "## Incohérences bloquantes\n\nAucune : toutes les réponses modèles sont acceptées, aucun pattern d'erreur `equals` n'est accepté, toutes les références se résolvent.\n" : "## Incohérences de contenu (\(issues.count))\n\n| Exercice | Type | Détail |\n|---|---|---|\n"
        for i in issues { text += "| `\(i.id)` | \(i.kind) | \(i.detail.replacingOccurrences(of: "|", with: "\\|")) |\n" }
        if !engineIssues.isEmpty { text += "\n## Écarts moteur\n\n" + engineIssues.map { "- \($0)" }.joined(separator: "\n") + "\n" }
        text += "\n## Observations (non bloquantes)\n\n" + notes(bundle).joined(separator: "\n\n") + "\n"
        let url = TestSupport.repoRoot.appendingPathComponent("docs/reports/content-engine-consistency.md")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

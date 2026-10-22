import XCTest
@testable import LearningCore

final class EvaluatorTests: XCTestCase {
    var engine: LearningEngine!

    override func setUpWithError() throws { engine = try TestSupport.fixtureEngine() }

    private func ev(_ id: String, _ sub: AnswerSubmission) -> Evaluation {
        engine.evaluate(engine.exercise(id)!, submission: sub)
    }
    private func text(_ id: String, _ s: String) -> Evaluation { ev(id, .text(s)) }

    // MARK: Exact answers, case, punctuation, spaces, contractions

    func testCaseSpacesAndPunctuationAreIgnored() {
        XCTAssertEqual(text("en.l01.e06", "we ARE   happy").result, .correct)
        XCTAssertEqual(text("en.l01.e06", "  We are happy!  ").result, .correct)
        XCTAssertEqual(text("en.l01.e06", "We are, happy.").result, .correct)
        XCTAssertEqual(text("en.l01.e06", "We’re happy").result, .correct)   // accepted contraction, curly apostrophe
    }

    func testContractionsAreEquivalentToExpandedForms() {
        for s in ["She isn't tired.", "She is not tired", "she ISN’T tired", "She's not tired"] {
            XCTAssertEqual(text("en.l01.e05", s).result, .correct, s)
        }
        for s in ["He doesn't work", "He does not work"] { XCTAssertEqual(text("en.l02.e03", s).result, .correct, s) }
        XCTAssertEqual(text("en.l03.e10", "She did not play yesterday").result, .correct)
        XCTAssertEqual(text("en.l03.e10", "She didn't play yesterday").result, .correct)
        XCTAssertEqual(text("en.assess.03", "I'm a doctor").result, .correct)
    }

    func testFillBlankAcceptsTheBlankOrTheFullSentence() {
        XCTAssertEqual(text("en.l01.e03", "is").result, .correct)
        XCTAssertEqual(ev("en.l01.e03", .choice("is")).result, .correct)
        XCTAssertEqual(text("en.l01.e03", "She is a teacher.").result, .correct)
    }

    func testEmptyAnswerIsIncorrect() {
        let e = text("en.l01.e06", "   ")
        XCTAssertEqual(e.result, .incorrect)
        XCTAssertNotNil(e.feedback)
    }

    // MARK: Typos versus grammar errors

    func testTypoIsAcceptedWithANote() {
        let e = text("en.l03.e03", "I recieved a message")
        XCTAssertEqual(e.result, .correctWithTypo)
        XCTAssertTrue(e.isCorrect)
        XCTAssertTrue(e.typoNote?.contains("recieved") == true && e.typoNote?.contains("received") == true, e.typoNote ?? "nil")
        XCTAssertTrue(e.diff.contains { $0.status == .typo })
        XCTAssertEqual(text("en.l01.e07", "docter").result, .correctWithTypo)
    }

    func testMissingApostropheIsAccepted() {
        let e = text("en.l02.e03", "He doesnt work")
        XCTAssertEqual(e.result, .correctWithTypo)
        XCTAssertNotNil(e.typoNote)
    }

    func testGrammarErrorIsNotATypo() {
        let conj = text("en.l02.e07", "he go")
        XCTAssertEqual(conj.result, .incorrect)
        XCTAssertEqual(conj.errorCategory, .conjugation)
        XCTAssertTrue(conj.feedback?.contains("go") == true)
        let tense = text("en.l03.e02", "go")
        XCTAssertEqual(tense.result, .incorrect)
        XCTAssertEqual(tense.errorCategory, .verbTense)
        let conj2 = text("en.l02.e04", "She live in Paris")
        XCTAssertEqual(conj2.errorCategory, .conjugation)
        let was = text("en.l01.e06", "We is happy")
        XCTAssertEqual(was.errorCategory, .conjugation)
        let prep = text("en.l02.e04", "She lives at Paris")
        XCTAssertEqual(prep.result, .incorrect)
        XCTAssertEqual(prep.errorCategory, .preposition)
    }

    func testUnknownWordsAreAVocabularyIssueNotATypo() {
        let e = text("en.l01.e07", "banana")
        XCTAssertEqual(e.result, .incorrect)
        XCTAssertEqual(e.errorCategory, .vocabulary)
        // A real but different word is never a typo.
        let f = text("en.l03.e04", "We watched a flim")
        XCTAssertEqual(f.result, .correctWithTypo)
    }

    // MARK: Word order, partial, error patterns

    func testWordOrder() {
        let e = text("en.l03.e04", "We a film watched")
        XCTAssertEqual(e.result, .incorrect)
        XCTAssertEqual(e.errorCategory, .wordOrder)
        XCTAssertFalse(e.diff.isEmpty)
    }

    func testPartialWhenWordsAreMissing() {
        let e = text("en.l03.e04", "We watched a")
        XCTAssertEqual(e.result, .partial)
        XCTAssertTrue(e.feedback?.contains("film") == true || e.feedback?.contains("movie") == true)
        XCTAssertTrue(e.diff.contains { $0.status == .missing })
    }

    func testPatternFeedbackIncludingContractionPatterns() {
        // equals "she aren't tired": the answer is normalized and expanded the same way.
        let a = text("en.l01.e05", "She aren't tired")
        XCTAssertEqual(a.result, .incorrect)
        XCTAssertEqual(a.errorCategory, .conjugation)
        XCTAssertEqual(a.feedback, "Avec she, on utilise isn't, pas aren't.")
        let b = text("en.l01.e05", "She are not tired")
        XCTAssertEqual(b.feedback, "Avec she, on utilise isn't, pas aren't.")
        // equals "he doesn't works"
        XCTAssertEqual(text("en.l02.e03", "He does not works").feedback, "Après doesn't, le verbe reste à la base : work.")
        // contains "he don't" (whole word sequence) in a longer answer
        let c = text("en.l02.e03", "Oh he don't work today")
        XCTAssertEqual(c.errorCategory, .grammar)
        XCTAssertEqual(c.feedback, "Avec he, on utilise doesn't, pas don't.")
        // contains is a whole-word match: "he don'ts" is not "he don't"
        XCTAssertNotEqual(text("en.l02.e03", "he don'ts work").feedback, "Avec he, on utilise doesn't, pas don't.")
        // mcq with an equals pattern
        let d = ev("en.l02.e09", .choice("She don't like tea."))
        XCTAssertEqual(d.result, .incorrect)
        XCTAssertEqual(d.feedback, "Avec she, on dit doesn't.")
        XCTAssertEqual(ev("en.l01.e01", .choice("I is a student")).errorCategory, .conjugation)
    }

    func testChoiceNeverBenefitsFromTypoTolerance() {
        let e = ev("en.l03.e01", .choice("receved"))
        XCTAssertEqual(e.result, .incorrect)
    }

    // MARK: Reorder and match

    func testReorderAcceptsAlternativeOrders() {
        XCTAssertEqual(ev("en.l03.e05", .ordering(["We", "visited", "Paris", "yesterday"])).result, .correct)
        XCTAssertEqual(ev("en.l03.e05", .ordering(["Yesterday", "we", "visited", "Paris"])).result, .correct)
        let bad = ev("en.l03.e05", .ordering(["Paris", "visited", "We", "yesterday"]))
        XCTAssertEqual(bad.result, .incorrect)
        XCTAssertEqual(bad.errorCategory, .wordOrder)
        XCTAssertFalse(bad.diff.isEmpty)
        XCTAssertEqual(ev("en.l01.e04", .ordering(["He", "is", "a", "teacher"])).result, .correct)
    }

    func testMatch() {
        let ex = engine.exercise("en.l01.e02")!
        let right = ex.pairs!
        XCTAssertEqual(ev(ex.id, .matches(right)).result, .correct)
        XCTAssertEqual(ev(ex.id, .matches(right.reversed())).result, .correct)   // order does not matter
        // 3 of 5 right (two swapped): partial, wrong pairs reported
        var partial = right
        partial[0] = MatchPair(left: right[0].left, right: right[1].right)
        partial[1] = MatchPair(left: right[1].left, right: right[0].right)
        let p = ev(ex.id, .matches(partial))
        XCTAssertEqual(p.result, .partial)
        XCTAssertEqual(p.wrongPairs.count, 2)
        XCTAssertEqual(p.errorCategory, .vocabulary)
        // 1 of 5: incorrect
        let bad = right.enumerated().map { MatchPair(left: $0.element.left, right: right[($0.offset + 1) % 5].right) }
        let b = ev(ex.id, .matches([bad[0]] + [MatchPair(left: right[1].left, right: right[1].right)] + Array(bad[2...])))
        XCTAssertEqual(b.result, .incorrect)
        // normalization of sides
        XCTAssertEqual(ev(ex.id, .matches(right.map { MatchPair(left: $0.left.uppercased(), right: $0.right.uppercased()) })).result, .correct)
    }

    // MARK: Open free answers, French

    func testOpenFreeAnswerWaitsForTheAI() {
        let e = text("en.l01.e08", "My father is a doctor in Lyon")
        XCTAssertEqual(e.result, .pending)
        XCTAssertTrue(e.needsAIReview)
        XCTAssertFalse(e.isCorrect)
        XCTAssertEqual(text("en.l01.e08", "I am a teacher.").result, .correct)        // a listed model answer
        let missing = text("en.l01.e08", "Hello there my friend")
        XCTAssertEqual(missing.result, .incorrect)
        XCTAssertEqual(missing.errorCategory, .instruction)
        XCTAssertTrue(missing.feedback?.contains("teacher") == true)
        XCTAssertEqual(text("en.l01.e08", "I am teacher").result, .pending)
        XCTAssertEqual(text("en.l01.e08", "teacher").errorCategory, .instruction)       // minWords
        XCTAssertEqual(text("en.l03.e08", "Yesterday I went home").result, .pending)
        let forbidden = text("en.l02.e08", "He lives in Paris and he don't smoke")
        XCTAssertEqual(forbidden.result, .incorrect)
        XCTAssertTrue(forbidden.feedback?.contains("don't") == true)
        // near form of a required word: grammar feedback
        let near = text("en.l02.e08", "My brother work in Paris")
        XCTAssertEqual(near.result, .incorrect)
        XCTAssertEqual(near.errorCategory, .conjugation)
    }

    func testUnlistedTranslationIsPendingButClearGrammarErrorsAreNot() {
        let e = text("en.l03.e03", "I have got a message")
        XCTAssertEqual(e.result, .pending)
        XCTAssertTrue(e.needsAIReview)
        XCTAssertEqual(text("en.l02.e07", "he goes").result, .correct)
        XCTAssertEqual(text("en.l02.e07", "he goes").needsAIReview, false)
        XCTAssertEqual(text("en.l02.e04", "Banana").result, .incorrect)   // single word: never sent to the AI
    }

    func testFrenchAnswers() {
        XCTAssertEqual(text("en.l01.e11", "Je suis fatigué").result, .correct)
        XCTAssertEqual(text("en.l01.e11", "je suis fatiguée.").result, .correct)
        let accents = text("en.l01.e11", "Je suis fatigue")
        XCTAssertEqual(accents.result, .correctWithTypo)
        XCTAssertEqual(accents.typoNote, "Attention aux accents.")
        XCTAssertEqual(text("en.l01.e11", "Je suis très fatigué").result, .pending)
        // A tapped option is exact: accent leniency only applies to typed answers (Arabic options may differ only by harakat).
        XCTAssertEqual(ev("en.l01.e10", .choice("fatigue")).result, .incorrect)
        XCTAssertEqual(ev("en.l01.e10", .choice("heureux")).result, .incorrect)
    }

    func testExpectedAnswerAndDiff() {
        let e = text("en.l02.e07", "he go")
        XCTAssertEqual(e.expectedAnswer, "he goes")
        XCTAssertEqual(e.userAnswer, "he go")
        XCTAssertTrue(e.diff.contains { $0.status == .wrong && $0.text == "go" && $0.expected == "goes" })
    }

    func testEveryFixtureModelAnswerIsAccepted() {
        for e in engine.index.bundle.exercises + engine.index.bundle.diagnostic + engine.index.bundle.assessment {
            for sub in [TestSupport.modelSubmission(e)] {
                XCTAssertTrue(engine.evaluate(e, submission: sub).isCorrect, e.id)
            }
            for a in e.acceptedAnswers where e.type != .match && e.type != .reorder && e.type != .mcq {
                XCTAssertTrue(engine.evaluate(e, submission: .text(a)).isCorrect, "\(e.id) \(a)")
            }
        }
    }
}

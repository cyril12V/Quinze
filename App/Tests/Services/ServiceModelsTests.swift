import XCTest
import LearningCore
@testable import Quinze

/// AI wire types, content versions and small pure helpers.
final class ServiceModelsTests: XCTestCase {
    private func keys<T: Encodable>(_ value: T) throws -> Set<String> {
        let data = try JSONEncoder().encode(value)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Set(object.keys)
    }

    func testAIRequestsOnlyCarryContractFields() throws {
        XCTAssertEqual(try keys(AIExplainAnswerRequest(languageCode: "en", level: 1, exerciseId: "e", userAnswer: "a",
                                                       detail: "short", previousErrorCategories: ["grammar"])),
                       ["languageCode", "level", "exerciseId", "userAnswer", "detail", "previousErrorCategories"])
        XCTAssertEqual(try keys(AIExplainWordRequest(languageCode: "en", level: 1, word: "go", sentence: nil, detail: "short")),
                       ["languageCode", "level", "word", "detail"])
        XCTAssertEqual(try keys(AIExplainRuleRequest(languageCode: "en", level: 1, unitId: "u", detail: "detailed")),
                       ["languageCode", "level", "unitId", "detail"])
        XCTAssertEqual(try keys(AIGradeRequest(languageCode: "en", level: 2, exerciseId: "e", userAnswer: "a")),
                       ["languageCode", "level", "exerciseId", "userAnswer"])
        let followUp = AIFollowUpRequest(languageCode: "en", level: 1, exerciseId: nil, unitId: "u", word: nil, userAnswer: nil,
                                         previousExplanation: "p", history: [AIHistoryMessage(role: "user", text: "q")], question: "?")
        XCTAssertEqual(try keys(followUp), ["languageCode", "level", "unitId", "previousExplanation", "history", "question"])
    }

    func testNoPersonalFieldCanBeSentToTheAI() throws {
        let all = try keys(AIExplainAnswerRequest(languageCode: "en", level: 1, exerciseId: "e", userAnswer: "a", detail: "short", previousErrorCategories: []))
            .union(keys(AIFollowUpRequest(languageCode: "en", level: 1, exerciseId: "e", unitId: nil, word: nil, userAnswer: "a",
                                          previousExplanation: "", history: [], question: "q")))
        for forbidden in ["email", "name", "displayName", "userId", "user_id"] {
            XCTAssertFalse(all.contains(forbidden), forbidden)
        }
    }

    func testTruncationMatchesContractLimits() {
        XCTAssertEqual(String(repeating: "a", count: 400).truncated(to: 300).count, 300)
        XCTAssertEqual("court".truncated(to: 300), "court")
        XCTAssertEqual(String(repeating: "é", count: 600).truncated(to: 500).count, 500)
    }

    func testGradeVerdictMapping() throws {
        func outcome(_ verdict: String, category: String? = nil) throws -> AIGradeOutcome? {
            let json = "{\"verdict\": \"\(verdict)\", \"errorCategory\": \(category.map { "\"\($0)\"" } ?? "null"), \"explanation\": \"x\", \"correctedAnswer\": null, \"source\": \"ai\", \"remainingQuota\": 36}"
            return AIGradeOutcome(response: try JSONDecoder().decode(AIGradeResponse.self, from: Data(json.utf8)))
        }
        XCTAssertEqual(try outcome("correct")?.result, .correct)
        XCTAssertEqual(try outcome("partial", category: "conjugation")?.result, .partial)
        XCTAssertEqual(try outcome("partial", category: "conjugation")?.errorCategory, .conjugation)
        XCTAssertEqual(try outcome("incorrect", category: "verb_tense")?.errorCategory, .verbTense)
        XCTAssertNil(try outcome("uncertain"), "an uncertain verdict keeps the attempt pending")
        XCTAssertNil(try outcome("???"))
        XCTAssertNil(try outcome("correct", category: "null")?.errorCategory)
        XCTAssertEqual(try outcome("correct")?.remainingQuota, 36)
    }

    func testExplainResponseDecodesContractAndOptionalFields() throws {
        let json = #"{"text": "Après doesn't…", "examples": [{"text": "He doesn't work today.", "translation": "Il ne travaille pas aujourd'hui."}], "source": "cache", "remainingQuota": 37}"#
        let response = try JSONDecoder().decode(AIExplainResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.examples?.first?.translation, "Il ne travaille pas aujourd'hui.")
        XCTAssertEqual(response.source, "cache")
        let minimal = try JSONDecoder().decode(AIExplainResponse.self, from: Data(#"{"text": "ok"}"#.utf8))
        XCTAssertNil(minimal.remainingQuota)
    }

    func testContentVersionComparison() {
        XCTAssertTrue(ContentVersion.isNewer("1.0.1", than: "1.0.0"))
        XCTAssertTrue(ContentVersion.isNewer("1.10.0", than: "1.9.3"))
        XCTAssertTrue(ContentVersion.isNewer("2.0", than: "1.99.99"))
        XCTAssertFalse(ContentVersion.isNewer("1.0.0", than: "1.0.0"))
        XCTAssertFalse(ContentVersion.isNewer("1.0", than: "1.0.0"))
        XCTAssertFalse(ContentVersion.isNewer("0.9.9", than: "1.0.0"))
        XCTAssertTrue(ContentVersion.isNewer("1.0.0", than: nil))
    }

    func testScheduleIssueMessagesAreFrench() {
        var schedule = DailySchedule.default
        schedule.afternoon = TimeOfDay(hour: 8, minute: 0)
        let messages = schedule.validate().map(\.message)
        XCTAssertFalse(messages.isEmpty)
        XCTAssertTrue(messages.allSatisfy { !$0.isEmpty })
        XCTAssertTrue(messages.contains { $0.contains("matin") })
    }

    func testLearningStoreErrorsAreUserFacingFrench() {
        XCTAssertEqual(LearningStoreError.slotNotYetAvailable(TimeOfDay(hour: 8, minute: 5)).errorDescription,
                       "Cette leçon sera disponible à 08:05.")
        XCTAssertNotNil(LearningStoreError.contentUnavailable.errorDescription)
    }
}

import XCTest
@testable import LearningCore

final class SmokeTests: XCTestCase {
    func testTimeOfDay() {
        XCTAssertEqual(TimeOfDay(hour: 9, minute: 5).description, "09:05")
        XCTAssertEqual(DailySchedule.default.validate(), [])
    }

    /// Decodes the real English bundle built by tools/build_content.py.
    func testRealBundleDecodes() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Content/build/en.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("bundle not built") }
        let bundle = try ContentBundle.decode(from: Data(contentsOf: url))
        XCTAssertEqual(bundle.lessons.count, 60)
        XCTAssertEqual(bundle.exercises.count, 600)
        XCTAssertEqual(bundle.units.count, 346)
        XCTAssertEqual(bundle.diagnostic.count, 40)
        XCTAssertEqual(bundle.assessment.count, 40)
        XCTAssertGreaterThan(bundle.dictionary.count, 390)
    }
}

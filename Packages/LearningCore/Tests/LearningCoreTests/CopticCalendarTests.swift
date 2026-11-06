import XCTest
@testable import LearningCore

final class CopticCalendarTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    func testCopticDates() {
        // Nayrouz: 1 Tout falls on 11 September, on 12 September the year before a Gregorian leap year.
        XCTAssertEqual(CopticCalendar.copticDate(for: date(2026, 9, 11), calendar: calendar),
                       .init(year: 1743, month: 1, day: 1))
        XCTAssertEqual(CopticCalendar.copticDate(for: date(2023, 9, 12), calendar: calendar),
                       .init(year: 1740, month: 1, day: 1))
        XCTAssertEqual(CopticCalendar.copticDate(for: date(2023, 9, 11), calendar: calendar),
                       .init(year: 1739, month: 13, day: 6), "6th day of Nasie in a Coptic leap year")
        // Christmas, 29 Kiahk = 7 January.
        XCTAssertEqual(CopticCalendar.copticDate(for: date(2026, 1, 7), calendar: calendar),
                       .init(year: 1742, month: 4, day: 29))
        XCTAssertEqual(CopticCalendar.copticDate(for: date(2026, 11, 6), calendar: calendar).formatted, "27 Baba 1743")
    }

    func testEaster() {
        for (year, month, day) in [(2024, 5, 5), (2025, 4, 20), (2026, 4, 12), (2027, 5, 2)] {
            let e = CopticCalendar.easter(year: year)
            XCTAssertEqual([e.year, e.month, e.day], [year, month, day])
        }
    }

    func testAdamAndWatos() {
        XCTAssertEqual(CopticCalendar.tune(for: date(2026, 11, 8), calendar: calendar), .adam)    // Sunday
        XCTAssertEqual(CopticCalendar.tune(for: date(2026, 11, 10), calendar: calendar), .adam)   // Tuesday
        XCTAssertEqual(CopticCalendar.tune(for: date(2026, 11, 11), calendar: calendar), .watos)  // Wednesday
        XCTAssertEqual(CopticCalendar.tune(for: date(2026, 11, 14), calendar: calendar), .watos)  // Saturday
    }

    func testFasts() {
        func fast(_ y: Int, _ m: Int, _ d: Int) -> String? { CopticCalendar.fast(on: date(y, m, d), calendar: calendar) }
        XCTAssertEqual(fast(2026, 2, 2), "Jeûne de Ninive")          // Monday, 69 days before Easter
        XCTAssertEqual(fast(2026, 2, 16), "Grand Carême")            // first day of Lent
        XCTAssertEqual(fast(2026, 4, 6), "Semaine sainte")
        XCTAssertNil(fast(2026, 4, 15), "no fast in the fifty days, even on a Wednesday")
        XCTAssertEqual(fast(2026, 6, 1), "Jeûne des Apôtres")         // day after Pentecost (31 May)
        XCTAssertEqual(fast(2026, 7, 11), "Jeûne des Apôtres")        // 4 Abib
        XCTAssertEqual(fast(2026, 8, 7), "Jeûne de la Vierge")        // 1 Misra
        XCTAssertEqual(fast(2026, 11, 25), "Jeûne de la Nativité")    // 16 Hatour
        XCTAssertEqual(fast(2027, 1, 6), "Jeûne de la Nativité")      // 28 Kiahk
        XCTAssertEqual(fast(2026, 11, 11), "Jeûne du mercredi")
        XCTAssertEqual(fast(2026, 11, 13), "Jeûne du vendredi")
        XCTAssertNil(fast(2026, 11, 12), "Thursday")
        XCTAssertNil(fast(2027, 1, 19), "Theophany on a Tuesday")
        XCTAssertNil(fast(2028, 1, 7), "Nativity on a Friday: no fast")
    }
}

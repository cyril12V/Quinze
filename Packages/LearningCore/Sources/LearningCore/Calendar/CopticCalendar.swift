import Foundation

/// The Coptic calendar and the few facts of the day the « Église » space shows: the Coptic date, Adam or
/// Watos day, and the fast in progress. Pure date arithmetic (Julian day numbers), valid for 1900–2099.
public enum CopticCalendar {

    /// A date of the Coptic calendar (Anno Martyrum: year 1 began on 29 August 284, Julian).
    public struct CopticDate: Hashable, Sendable {
        public let year: Int
        /// 1…13 (13 is the small month « Nasie » of 5 or 6 days).
        public let month: Int
        public let day: Int

        public var monthName: String { CopticCalendar.monthNames[month - 1] }
        public var monthNameArabic: String { CopticCalendar.monthNamesArabic[month - 1] }

        /// « 27 Baba 1743 »
        public var formatted: String { "\(day) \(monthName) \(year)" }
    }

    /// The months as Egyptians say them, in French spelling.
    public static let monthNames = ["Tout", "Baba", "Hatour", "Kiahk", "Touba", "Amshir", "Baramhat", "Baramouda",
                                    "Bashans", "Baouna", "Abib", "Misra", "Nasie"]
    public static let monthNamesArabic = ["توت", "بابه", "هاتور", "كيهك", "طوبه", "أمشير", "برمهات", "برموده",
                                          "بشنس", "بؤونه", "أبيب", "مسرى", "النسيء"]

    /// Adam days (Sunday, Monday, Tuesday) and Watos days (Wednesday to Saturday): the tune of the psalis and
    /// theotokias of the day.
    public enum DayTune: String, Sendable {
        case adam = "Adam"
        case watos = "Watos"
    }

    // MARK: Conversion

    private static let epoch = 1_825_030   // Julian day number of 1 Tout 1 A.M.

    static func julianDay(year: Int, month: Int, day: Int) -> Int {
        // Gregorian → JDN (Fliegel & Van Flandern).
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    static func gregorian(julianDay jdn: Int) -> (year: Int, month: Int, day: Int) {
        let a = jdn + 32044
        let b = (4 * a + 3) / 146_097
        let c = a - 146_097 * b / 4
        let d = (4 * c + 3) / 1461
        let e = c - 1461 * d / 4
        let m = (5 * e + 2) / 153
        let day = e - (153 * m + 2) / 5 + 1
        let month = m + 3 - 12 * (m / 10)
        let year = 100 * b + d - 4800 + m / 10
        return (year, month, day)
    }

    static func julianDay(coptic year: Int, month: Int, day: Int) -> Int {
        epoch + 365 * (year - 1) + year / 4 + 30 * (month - 1) + (day - 1)
    }

    static func coptic(julianDay jdn: Int) -> CopticDate {
        let year = (4 * (jdn - epoch) + 1463) / 1461
        let month = (jdn - julianDay(coptic: year, month: 1, day: 1)) / 30 + 1
        let day = jdn - julianDay(coptic: year, month: month, day: 1) + 1
        return CopticDate(year: year, month: month, day: day)
    }

    private static func julianDay(of date: Date, calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return julianDay(year: c.year ?? 2000, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// Coptic date of a civil day.
    public static func copticDate(for date: Date, calendar: Calendar = .current) -> CopticDate {
        coptic(julianDay: julianDay(of: date, calendar: calendar))
    }

    /// Adam or Watos, from the day of the week.
    public static func tune(for date: Date, calendar: Calendar = .current) -> DayTune {
        let weekday = calendar.component(.weekday, from: date)   // 1 = Sunday
        return (1...3).contains(weekday) ? .adam : .watos
    }

    /// French name of the day of the week (« dimanche »).
    public static func weekdayName(for date: Date, calendar: Calendar = .current) -> String {
        let names = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
        return names[(calendar.component(.weekday, from: date) - 1) % 7]
    }

    // MARK: Easter and fasts

    /// Julian day number of the Coptic (Orthodox) Easter Sunday of a Gregorian year (Alexandrian computus).
    static func easterJulianDay(year: Int) -> Int {
        let a = year % 4, b = year % 7, c = year % 19
        let d = (19 * c + 15) % 30
        let e = (2 * a + 4 * b - d + 34) % 7
        let month = (d + e + 114) / 31
        let day = (d + e + 114) % 31 + 1
        // Julian calendar date → JDN.
        let aa = (14 - month) / 12
        let y = year + 4800 - aa
        let m = month + 12 * aa - 3
        return day + (153 * m + 2) / 5 + 365 * y + y / 4 - 32083
    }

    /// Gregorian date of the Coptic Easter Sunday.
    public static func easter(year: Int) -> (year: Int, month: Int, day: Int) {
        gregorian(julianDay: easterJulianDay(year: year))
    }

    /// The fast of a day, if any (« Grand Carême », « Jeûne du mercredi »…). Nil on the days without fasting,
    /// such as the fifty days after Easter.
    public static func fast(on date: Date, calendar: Calendar = .current) -> String? {
        let jdn = julianDay(of: date, calendar: calendar)
        let year = calendar.component(.year, from: date)
        let easter = easterJulianDay(year: year)
        let cd = coptic(julianDay: jdn)
        let weekday = calendar.component(.weekday, from: date)

        // The fifty days from Easter to Pentecost: no fasting at all.
        if jdn >= easter && jdn <= easter + 49 { return nil }
        if jdn >= easter - 7 && jdn < easter { return "Semaine sainte" }
        if jdn >= easter - 55 && jdn < easter - 7 { return "Grand Carême" }
        if jdn >= easter - 69 && jdn <= easter - 67 { return "Jeûne de Ninive" }
        // Apostles: from the day after Pentecost to 4 Abib (feast of the apostles on 5 Abib).
        let apostlesEnd = julianDay(coptic: cd.year, month: 11, day: 4)
        if jdn >= easter + 50 && jdn <= apostlesEnd { return "Jeûne des Apôtres" }
        if cd.month == 12 && cd.day <= 15 { return "Jeûne de la Vierge" }
        // The Nativity is celebrated on 7 January and the Theophany on 19 January (Gregorian): the 43 days of the
        // Nativity fast run from 25 November to 6 January.
        let c = calendar.dateComponents([.month, .day], from: date)
        let (month, day) = (c.month ?? 1, c.day ?? 1)
        if (month == 11 && day >= 25) || month == 12 || (month == 1 && day <= 6) { return "Jeûne de la Nativité" }
        // Wednesday and Friday, except when the Nativity or the Theophany falls on them.
        let isNativity = month == 1 && day == 7
        let isTheophany = month == 1 && day == 19
        if (weekday == 4 || weekday == 6) && !isNativity && !isTheophany {
            return weekday == 4 ? "Jeûne du mercredi" : "Jeûne du vendredi"
        }
        return nil
    }
}

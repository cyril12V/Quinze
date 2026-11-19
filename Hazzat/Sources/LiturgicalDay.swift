import Foundation

/// What the Church lives on a given day: the Coptic date, Adam or Watos, the period of the year and the next one.
/// Pure date arithmetic, no network.
struct LiturgicalDay {
    let date: Date
    let coptic: CopticCalendar.CopticDate
    let tune: CopticCalendar.DayTune
    /// Tune of tomorrow, when it changes (Tuesday → Watos, Saturday → Adam).
    let tomorrowTune: CopticCalendar.DayTune?
    let season: String
    /// The fast of the day, if any (« Jeûne de la Nativité »…).
    let fast: String?
    /// The next period that is not the ordinary time, and in how many days it starts.
    let next: (season: String, days: Int, start: Date)?

    static let ordinary = "Période annuelle"

    init(date: Date = .now, calendar: Calendar = .current) {
        self.date = date
        coptic = CopticCalendar.copticDate(for: date, calendar: calendar)
        tune = CopticCalendar.tune(for: date, calendar: calendar)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        let t = CopticCalendar.tune(for: tomorrow, calendar: calendar)
        tomorrowTune = t == tune ? nil : t
        let today = Self.julianDay(date, calendar)
        season = Self.season(julianDay: today)
        fast = CopticCalendar.fast(on: date, calendar: calendar)
        var found: (season: String, days: Int, start: Date)?
        for offset in 1...400 {
            let s = Self.season(julianDay: today + offset)
            if s != season && s != Self.ordinary {
                found = (s, offset, calendar.date(byAdding: .day, value: offset, to: date) ?? date)
                break
            }
        }
        next = found
    }

    private static func julianDay(_ date: Date, _ calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return CopticCalendar.julianDay(year: c.year ?? 2000, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// The period of a day, named like the periods of the list.
    static func season(julianDay jdn: Int) -> String {
        let g = CopticCalendar.gregorian(julianDay: jdn)
        let cd = CopticCalendar.coptic(julianDay: jdn)
        let e = CopticCalendar.easterJulianDay(year: g.year)
        let (m, d) = (cd.month, cd.day)

        // Fast of Jonah and the Great Lent, with Palm Sunday and the Holy Week.
        if jdn >= e - 69 && jdn <= e - 66 { return "Jonas" }
        if jdn == e - 7 { return "Rameaux" }
        if jdn >= e - 6 && jdn < e { return "Semaine sainte" }
        if jdn >= e - 55 && jdn < e - 7 { return "Grand carême" }

        // Feasts on a fixed date. The Nativity is kept on 7 January, the Theophany on 19 January.
        if m == 1 && d <= 16 { return "Nayrouz" }
        if m == 1 && d <= 19 { return "Fête de la croix" }
        if g.month == 1 && g.day >= 7 && g.day <= 18 { return "Nativité" }
        if g.month == 1 && (g.day == 19 || g.day == 20) { return "Épiphanie" }
        if g.month == 1 && g.day == 21 { return "Noces de Cana" }
        if m == 4 && d <= 28 { return "Kiahk" }
        if m == 9 && d == 24 { return "Entrée en Égypte" }

        // The fifty days, then the fast of the apostles until their feast on 5 Abib.
        if jdn >= e && jdn < e + 39 { return "Résurrection" }
        if jdn >= e + 39 && jdn < e + 49 { return "Ascension" }
        if jdn == e + 49 { return "Pentecôte" }
        let apostles = CopticCalendar.julianDay(coptic: CopticCalendar.coptic(julianDay: e).year, month: 11, day: 5)
        if jdn > e + 49 && jdn <= apostles { return "Jeûne des apôtres" }

        // Fast of the Virgin (Nahda), up to her feast on 16 Misra.
        if m == 12 && d <= 16 { return "Nahda" }
        return ordinary
    }
}

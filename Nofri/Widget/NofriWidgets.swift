import WidgetKit
import SwiftUI
import LearningCore

/// Lock-screen widgets of Nofri:
/// - « Aujourd'hui dans l'Église » : Coptic date, Adam or Watos day, fast (rectangular and inline);
/// - « À retenir » : one key fact of the lessons already validated, a new one every hour (rectangular);
/// - « Série » : days in a row, and whether today's lesson is done (circular).
@main
struct NofriWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayInChurchWidget()
        KeyFactWidget()
        StreakWidget()
    }
}

struct NofriEntry: TimelineEntry {
    let date: Date
    let data: NofriWidgetData
    /// Index of the entry in its timeline (rotates the key facts).
    let slot: Int
}

struct NofriTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NofriEntry {
        NofriEntry(date: .now, data: NofriWidgetData(facts: ["Nicée, 325 : le Fils est consubstantiel au Père."], streakDays: 3), slot: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (NofriEntry) -> Void) {
        completion(NofriEntry(date: .now, data: context.isPreview ? placeholder(in: context).data : NofriWidgetData.load(), slot: 0))
    }

    /// One entry per hour for the next day: the Coptic day changes at midnight, the evening line at 18:00.
    func getTimeline(in context: Context, completion: @escaping (Timeline<NofriEntry>) -> Void) {
        let data = NofriWidgetData.load()
        let calendar = Calendar.current
        let now = Date.now
        let startOfHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let hourOfEra = Int(startOfHour.timeIntervalSince1970 / 3600)
        var entries: [NofriEntry] = [NofriEntry(date: now, data: data, slot: hourOfEra)]
        for h in 1...24 {
            if let date = calendar.date(byAdding: .hour, value: h, to: startOfHour) {
                entries.append(NofriEntry(date: date, data: data, slot: hourOfEra + h))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Aujourd'hui dans l'Église

struct TodayInChurchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "nofri.today", provider: NofriTimelineProvider()) { entry in
            TodayInChurchWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Aujourd'hui dans l'Église")
        .description("La date copte, le jour Adam ou Watos et le jeûne du jour.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

struct TodayInChurchWidgetView: View {
    let entry: NofriEntry
    @Environment(\.widgetFamily) private var family

    private var calendar: Calendar { .current }
    private var coptic: CopticCalendar.CopticDate { CopticCalendar.copticDate(for: entry.date, calendar: calendar) }
    private var tune: String { CopticCalendar.tune(for: entry.date, calendar: calendar).rawValue }
    private var fast: String { CopticCalendar.fast(on: entry.date, calendar: calendar) ?? "Pas de jeûne" }
    private var isEvening: Bool { calendar.component(.hour, from: entry.date) >= 18 }

    /// From 18:00 the Church is already in tomorrow: the theotokia is tomorrow's.
    private var secondLine: String {
        guard isEvening, let tomorrow = calendar.date(byAdding: .day, value: 1, to: entry.date) else {
            return "Jour \(tune) · \(CopticCalendar.weekdayName(for: entry.date, calendar: calendar))"
        }
        let name = CopticCalendar.weekdayName(for: tomorrow, calendar: calendar)
        return "Ce soir : théotokie du \(name) (\(CopticCalendar.tune(for: tomorrow, calendar: calendar).rawValue))"
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("\(coptic.day) \(coptic.monthName) · \(tune)")
        default:
            VStack(alignment: .leading, spacing: 1) {
                Text(coptic.formatted)
                    .font(.headline)
                    .widgetAccentable()
                Text(secondLine)
                    .font(.caption)
                Text(fast)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - À retenir

struct KeyFactWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "nofri.fact", provider: NofriTimelineProvider()) { entry in
            KeyFactWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("À retenir")
        .description("Une chose apprise dans tes leçons, qui change toutes les heures.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct KeyFactWidgetView: View {
    let entry: NofriEntry

    private var fact: String {
        let facts = entry.data.facts
        guard !facts.isEmpty else { return "Fais ta première leçon : ce que tu apprends s'affichera ici." }
        // The most recent lessons come back more often: two hours out of three pick among the last 20 facts.
        let recent = Array(facts.suffix(20))
        let pool = entry.slot % 3 == 0 ? facts : recent
        return pool[Int(UInt(bitPattern: entry.slot &* 2_654_435_761) % UInt(pool.count))]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("À RETENIR")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .widgetAccentable()
            Text(fact)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(3)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Série

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "nofri.streak", provider: NofriTimelineProvider()) { entry in
            StreakWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Série")
        .description("Tes jours d'affilée, et si la leçon du jour est faite.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct StreakWidgetView: View {
    let entry: NofriEntry

    private var doneToday: Bool { entry.data.lastStudyDay == NofriWidgetData.isoDay(entry.date) }

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: doneToday ? "checkmark.circle.fill" : "flame")
                    .font(.system(size: 14, weight: .semibold))
                    .widgetAccentable()
                Text("\(entry.data.streakDays)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(entry.data.streakDays > 1 ? "jours" : "jour")
                    .font(.system(size: 8, weight: .medium))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Série de \(entry.data.streakDays) jours. \(doneToday ? "Leçon du jour faite." : "Leçon du jour à faire.")")
    }
}

import SwiftUI
import LearningCore

/// « Progrès » tab (« statistiques » model): learning time over the last 7 days, mini stats, category
/// progress, weak points, assessment history. Tab root: wrapped in a `NavigationStack` by `MainTabView`
/// (it creates none), hides the system bar and draws `AppHeader`. The studied-units detail is pushed.
struct ProgressDashboardView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showSettings = false
    @State private var explanationOpen = false

    init() {}

    var body: some View {
        QScreen {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                AppHeader(label: "Progrès",
                          title: env.store.languageName,
                          initials: QAvatar.initials(from: env.store.displayName),
                          avatarAction: { showSettings = true })
                if let report = env.store.progress {
                    dashboard(report)
                } else {
                    placeholder
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showSettings) {
            SettingsView()
        }
        .task { await env.store.refresh() }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScreenTitle("Tes progrès")
            ScreenSubtitle("Ce que tu as appris, et ce que tu retiens vraiment.")
        }
    }

    // MARK: Loading / empty

    @ViewBuilder private var placeholder: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.titleToContent) {
            titleBlock
            if env.store.isLoading {
                SkeletonCard(height: 260)
                SkeletonCard(height: 160)
            } else {
                EmptyStateView(icon: .chart, pastel: .yellow,
                               message: "Ta progression apparaîtra ici dès ta première leçon.")
            }
        }
    }

    // MARK: Dashboard

    @ViewBuilder private func dashboard(_ report: ProgressReport) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.titleToContent) {
            titleBlock
            weekCard
                .qAppear(0)
        }
        statsSection(report)
            .qAppear(1)
        totalsCard(report)
        categoriesSection(report)
        explanationCard
        weakPointsSection(report)
        assessmentsSection
        studiedUnitsLink(report)
            .qAppear(2)
    }

    // MARK: Week chart

    private var weekCard: some View {
        let week: ProgressWeek = ProgressWeek.make(attempts: env.store.learner.recentAttempts,
                                                   today: LocalDay(date: .now))
        return ChartCard(icon: .clock,
                         detail: "7 derniers jours",
                         value: week.totalText,
                         caption: "Temps d'apprentissage") {
            RoundedBarChart(data: week.bars, highlighted: week.todayId)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(week.summary)
        .accessibilityValue(week.detail)
    }

    // MARK: Mini stats

    private func statsSection(_ report: ProgressReport) -> some View {
        let wordsLabel: String = "Mots maîtrisés (sur \(report.wordsStudied) étudié\(report.wordsStudied > 1 ? "s" : ""))"
        let rulesLabel: String = "Règles maîtrisées (sur \(report.rulesStudied) étudiée\(report.rulesStudied > 1 ? "s" : ""))"
        let successValue: String = report.attemptCount > 0 ? FrenchLabels.percent(report.successRate) : "–"
        let streakValue: String = FrenchLabels.days(env.store.stats.streakDays)
        return VStack(spacing: 12) {
            StatGrid {
                StatMiniCard(icon: .dictionary, value: "\(report.wordsMastered)", label: wordsLabel, pastel: .pink)
                StatMiniCard(icon: .book, value: "\(report.rulesMastered)", label: rulesLabel, pastel: .blue)
            }
            StatGrid {
                StatMiniCard(icon: .target, value: successValue, label: "Taux de réussite", pastel: .green)
                StatMiniCard(icon: .flame, value: streakValue, label: "Série en cours", pastel: .yellow)
            }
        }
    }

    // MARK: All-time totals (§15.1)

    private func totalsCard(_ report: ProgressReport) -> some View {
        let stats: UsageStats = env.store.stats
        let rows: [(icon: QIcon, label: String, value: String)] = [
            (icon: .check, label: "Sessions terminées", value: "\(stats.sessionsCompleted)"),
            (icon: .clock, label: "Temps total d'apprentissage", value: FrenchLabels.duration(seconds: stats.totalLearningSeconds)),
            (icon: .refresh, label: "Révisions effectuées", value: "\(report.reviewsDone)"),
            (icon: .book, label: "Leçons faites", value: "\(report.lessonsCompleted) sur \(report.lessonsTotal)"),
            (icon: .dictionary, label: "Mots étudiés", value: "\(report.wordsStudied)"),
            (icon: .lightbulb, label: "Règles étudiées", value: "\(report.rulesStudied)"),
        ]
        return VStack(alignment: .leading, spacing: Theme.Spacing.card) {
            QSectionTitle("Depuis le début")
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 12) {
                        QIconView(icon: row.icon, size: 18)
                            .foregroundStyle(Theme.ink)
                        Text(row.label)
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.primaryText)
                        Spacer(minLength: Theme.Spacing.s)
                        Text(row.value)
                            .font(Theme.Font.body(.semibold))
                            .foregroundStyle(Theme.primaryText)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 12)
                    .accessibilityElement(children: .combine)
                    if index < rows.count - 1 {
                        Rectangle().fill(Theme.separator).frame(height: 1)
                    }
                }
            }
            .card()
        }
    }

    // MARK: Categories

    private func categoriesSection(_ report: ProgressReport) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.card) {
            QSectionTitle("Par catégorie")
            ForEach(Array(report.categories.enumerated()), id: \.offset) { index, category in
                ProgressCategoryCard(progress: category)
                    .qAppear(index + 3)
            }
        }
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                if reduceMotion {
                    explanationOpen.toggle()
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { explanationOpen.toggle() }
                }
            } label: {
                HStack(spacing: 12) {
                    QIconView(icon: .info, size: 18)
                        .foregroundStyle(Theme.ink)
                    Text("Comment c'est calculé ?")
                        .font(Theme.Font.body(.semibold))
                        .foregroundStyle(Theme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    QIconView(icon: .chevronDown, size: 14)
                        .foregroundStyle(Theme.secondaryText)
                        .rotationEffect(.degrees(explanationOpen ? 180 : 0))
                }
                .frame(minHeight: Theme.minTapSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.press)
            .accessibilityValue(explanationOpen ? "Développé" : "Réduit")
            .accessibilityHint("Affiche ou masque l'explication")
            if explanationOpen {
                Text("Pour chaque catégorie, on fait la moyenne de la maîtrise des notions que tu as déjà étudiées. Une notion est considérée comme maîtrisée quand tu la retrouves sans indice, que tu réussis encore après un certain délai, et avec des exercices variés. Les pourcentages montent donc progressivement : c'est normal.")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.secondaryText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }

    // MARK: Weak points

    @ViewBuilder private func weakPointsSection(_ report: ProgressReport) -> some View {
        if report.attemptCount > 0 {
            let stats: [ErrorCategoryStat] = Array(report.weakErrorCategories.filter { $0.errorCount > 0 }.prefix(5))
            VStack(alignment: .leading, spacing: Theme.Spacing.card) {
                QSectionTitle("Points à travailler")
                if stats.isEmpty {
                    ScreenSubtitle("Pas d'erreur fréquente repérée pour l'instant.")
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                            weakRow(stat)
                        }
                    }
                    .card()
                }
            }
        }
    }

    private func weakRow(_ stat: ErrorCategoryStat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Text(stat.category.displayName)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(stat.errorCount) erreur\(stat.errorCount > 1 ? "s" : "") · \(FrenchLabels.percent(stat.rate))")
                .font(Theme.Font.callout.monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Assessments

    private var assessmentsSection: some View {
        let records: [AssessmentRecord] = env.store.stats.assessments.sorted { $0.day > $1.day }
        return VStack(alignment: .leading, spacing: Theme.Spacing.card) {
            QSectionTitle("Tests de consolidation")
            if records.isEmpty {
                ScreenSubtitle("Aucun test passé pour l'instant.")
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(records.enumerated()), id: \.offset) { _, record in
                        HStack {
                            Text(record.day.shortDisplay)
                                .font(Theme.Font.body)
                                .foregroundStyle(Theme.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(FrenchLabels.percent(record.score))
                                .font(Theme.Font.body(.semibold).monospacedDigit())
                                .foregroundStyle(Theme.primaryText)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .card()
            }
        }
    }

    // MARK: Studied units (pushed screen)

    private func studiedUnitsLink(_ report: ProgressReport) -> some View {
        let wordsText: String = report.wordsStudied > 1 ? "\(report.wordsStudied) mots" : "\(report.wordsStudied) mot"
        let rulesText: String = report.rulesStudied > 1 ? "\(report.rulesStudied) règles" : "\(report.rulesStudied) règle"
        return NavigationLink {
            StudiedUnitsView()
        } label: {
            HStack(spacing: 14) {
                QIconView(icon: .book, size: 18)
                    .foregroundStyle(Theme.onInk)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.ink))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notions étudiées")
                        .font(Theme.Font.headline)
                        .foregroundStyle(Theme.primaryText)
                    Text("\(wordsText) · \(rulesText)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.tertiaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                QIconView(icon: .chevronRight, size: 14)
                    .foregroundStyle(Theme.secondaryText)
            }
            .card()
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.press)
        .accessibilityHint("Ouvre le détail de chaque règle et de chaque mot")
    }
}

// MARK: - Learning time over the last 7 days

/// Minutes per day from the attempts of the learner (sum of `durationSeconds` per `LocalDay`).
struct ProgressWeek {
    let bars: [BarDatum]
    /// Id of today's bar (the last one).
    let todayId: Int
    let totalSeconds: Double
    let todaySeconds: Double

    /// An idle question (app left open) must not flatten the chart: one attempt counts for 10 minutes at most.
    private static let maxAttemptSeconds: Double = 600
    private static let weekdayLabels: [String] = ["dim", "lun", "mar", "mer", "jeu", "ven", "sam"]

    var totalText: String { Self.durationText(totalSeconds) }

    /// One sentence for VoiceOver.
    var summary: String {
        "Temps d'apprentissage des 7 derniers jours : \(Self.durationText(totalSeconds)) au total, \(Self.durationText(todaySeconds)) aujourd'hui."
    }

    /// Day by day, read after the summary.
    var detail: String {
        bars.map { "\($0.label) : \($0.valueText)" }.joined(separator: ", ")
    }

    static func make(attempts: [AttemptRecord], today: LocalDay, calendar: Calendar = .current) -> ProgressWeek {
        var secondsByDay: [LocalDay: Double] = [:]
        for attempt in attempts {
            let day: LocalDay = LocalDay(date: attempt.answeredAt, calendar: calendar)
            let seconds: Double = min(max(attempt.durationSeconds, 0), maxAttemptSeconds)
            secondsByDay[day, default: 0] += seconds
        }
        var bars: [BarDatum] = []
        var total: Double = 0
        var todaySeconds: Double = 0
        for offset in 0..<7 {
            let day: LocalDay = today.adding(days: offset - 6, calendar: calendar)
            let seconds: Double = secondsByDay[day] ?? 0
            total += seconds
            if offset == 6 { todaySeconds = seconds }
            let weekday: Int = calendar.component(.weekday, from: day.startDate(calendar: calendar))
            let label: String = weekdayLabels[((weekday - 1) % 7 + 7) % 7]
            bars.append(BarDatum(id: offset, label: label, value: seconds / 60, valueText: minutesText(seconds)))
        }
        return ProgressWeek(bars: bars, todayId: 6, totalSeconds: total, todaySeconds: todaySeconds)
    }

    /// "12 min", "< 1 min", "0 min"
    private static func minutesText(_ seconds: Double) -> String {
        let minutes: Int = Int((seconds / 60).rounded())
        if minutes == 0 { return seconds > 0 ? "< 1 min" : "0 min" }
        return "\(minutes) min"
    }

    /// "42 min", "1 h 05", "0 min"
    private static func durationText(_ seconds: Double) -> String {
        if seconds < 60 { return seconds > 0 ? "< 1 min" : "0 min" }
        return FrenchLabels.duration(seconds: Int(seconds.rounded()))
    }
}

// MARK: - Category card

private struct ProgressCategoryCard: View {
    let progress: CategoryProgress

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s + 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(progress.category.displayName)
                    .font(Theme.Font.body(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Spacer(minLength: Theme.Spacing.s)
                Text(progress.unitsStudied > 0 ? FrenchLabels.percent(progress.averageMastery) : "–")
                    .font(Theme.Font.body.monospacedDigit())
                    .foregroundStyle(Theme.primaryText)
            }
            QProgressBar(value: progress.unitsStudied > 0 ? progress.averageMastery : 0)
            Text("\(progress.unitsStudied) étudiées sur \(progress.unitsTotal) · \(progress.unitsMastered) maîtrisées")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.category.displayName)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if progress.unitsStudied > 0 {
            parts.append("maîtrise moyenne \(FrenchLabels.percent(progress.averageMastery))")
        } else {
            parts.append("pas encore commencé")
        }
        parts.append("\(progress.unitsStudied) notions étudiées sur \(progress.unitsTotal)")
        parts.append("\(progress.unitsMastered) maîtrisées")
        return parts.joined(separator: ", ")
    }
}

// MARK: - Studied units (pushed)

private struct StudiedUnitRow: Identifiable {
    let unit: LearningUnit
    let mastery: MasteryReport
    var id: String { unit.id }
}

/// Every studied rule / word with its mastery level; a row opens the rule explanation or the word sheet.
private struct StudiedUnitsView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var studied: [StudiedUnitRow] = []
    @State private var unitFilter: UnitKind = .grammar
    @State private var sheet: WordLookupSheet? = nil

    init() {}

    private var filteredUnits: [StudiedUnitRow] {
        studied
            .filter { $0.unit.kind == unitFilter }
            .sorted { $0.mastery.score < $1.mastery.score }
    }

    var body: some View {
        QScreen {
            VStack(alignment: .leading, spacing: Theme.Spacing.titleToContent) {
                filters
                unitsList
            }
        }
        .navigationTitle("Notions étudiées")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadStudiedUnits() }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .word(let item):
                WordSheet(item: item)
            case .tutor(let request):
                TutorSheet(subject: request.subject)
            }
        }
    }

    private var filters: some View {
        QFlowLayout() {
            FilterChip(title: "Règles", icon: .book, iconFill: Theme.blue, isSelected: unitFilter == .grammar) {
                unitFilter = .grammar
            }
            FilterChip(title: "Mots", icon: .dictionary, iconFill: Theme.pink, isSelected: unitFilter == .vocabulary) {
                unitFilter = .vocabulary
            }
        }
    }

    @ViewBuilder private var unitsList: some View {
        let rows: [StudiedUnitRow] = filteredUnits
        if rows.isEmpty {
            EmptyStateView(icon: unitFilter == .grammar ? .book : .dictionary,
                           pastel: unitFilter == .grammar ? .blue : .pink,
                           message: unitFilter == .grammar ? "Aucune règle étudiée pour l'instant." : "Aucun mot étudié pour l'instant.")
        } else {
            LazyVStack(spacing: 10) {
                ForEach(rows) { row in
                    Button { open(row) } label: { StudiedUnitRowView(row: row) }
                        .buttonStyle(.press)
                }
            }
        }
    }

    private func loadStudiedUnits() {
        studied = env.store.studiedUnits().map { StudiedUnitRow(unit: $0.unit, mastery: $0.mastery) }
    }

    private func open(_ row: StudiedUnitRow) {
        switch row.unit.kind {
        case .grammar:
            sheet = .tutor(TutorRequest(subject: .rule(unitId: row.unit.id)))
        case .vocabulary:
            if let item = env.store.dictionaryEntry(for: row.unit.title) {
                sheet = .word(item)
            } else {
                sheet = .tutor(TutorRequest(subject: .word(row.unit.title, sentence: nil)))
            }
        }
    }
}

private struct StudiedUnitRowView: View {
    let row: StudiedUnitRow

    private var levelIcon: QIcon {
        switch row.mastery.level {
        case .notStarted: return .hourglass
        case .learning: return .book
        case .fragile: return .warning
        case .mastered: return .check
        }
    }

    private var levelFill: Color {
        switch row.mastery.level {
        case .notStarted: return Theme.background
        case .learning: return Pastel.blue.soft
        case .fragile: return Pastel.yellow.soft
        case .mastered: return Pastel.green.soft
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(row.unit.title)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.primaryText)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            QPill(text: row.mastery.level.displayName, icon: levelIcon, fill: levelFill, foreground: Theme.ink)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: Theme.minTapSize, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.surface)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(row.unit.kind == .grammar ? "Ouvre l'explication de la règle" : "Ouvre la fiche du mot")
    }
}

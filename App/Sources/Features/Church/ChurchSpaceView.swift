import SwiftUI
import LearningCore

/// The « Église » space: an app inside Quinze, with its own home, path, words and progress. Outside the daily
/// slots and the blocking; one session a day at the learner's pace.
struct ChurchSpaceView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var tab: ChurchTab = .home

    enum ChurchTab: String, CaseIterable, Identifiable {
        case home, path, words, progress
        var id: String { rawValue }

        var title: String {
            switch self {
            case .home: return "Accueil"
            case .path: return "Parcours"
            case .words: return "Lexique"
            case .progress: return "Progrès"
            }
        }

        var icon: QIcon {
            switch self {
            case .home: return .home
            case .path: return .path
            case .words: return .dictionary
            case .progress: return .chart
            }
        }
    }

    var body: some View {
        ZStack {
            switch tab {
            case .home: NavigationStack { ChurchHomeView() }
            case .path: NavigationStack { PathView() }.id(ChurchTab.path)
            case .words: NavigationStack { DictionaryView() }.id(ChurchTab.words)
            case .progress: NavigationStack { ProgressDashboardView() }.id(ChurchTab.progress)
            }
        }
        .environment(\.subjectLocked, true)
        .studySubject(.church)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChurchBottomNav(selection: $tab)
        }
        .onAppear {
            if env.study.focusSubject != .church {
                env.study.focusSubject = .church
                Task { await env.store.refresh() }
            }
        }
    }
}

struct ChurchBottomNav: View {
    @Binding var selection: ChurchSpaceView.ChurchTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ChurchSpaceView.ChurchTab.allCases) { tab in
                item(tab)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, Theme.Spacing.s)
        .frame(maxWidth: Theme.maxContentWidth)
        .frame(maxWidth: .infinity)
        .background {
            Rectangle()
                .fill(Theme.background.opacity(0.96))
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func item(_ tab: ChurchSpaceView.ChurchTab) -> some View {
        let isActive = tab == selection
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 4) {
                QIconView(icon: tab.icon, size: 22, filled: isActive)
                Text(tab.title)
                    .font(Theme.Font.jakarta(10, isActive ? .semibold : .medium, relativeTo: .caption2))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isActive ? Theme.ink : Theme.inactive)
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }
}

/// Home of the « Église » space: today in the Church, the session of the day, the progression.
struct ChurchHomeView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var activeRun: StudyRun?
    @State private var isStarting = false
    @State private var showSettings = false
    @State private var now = Date.now
    @State private var errorMessage: String?

    private var store: LearningStore { env.study.store(.church) }

    var body: some View {
        QScreen {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                AppHeader(label: "Église copte",
                          title: headerName,
                          initials: QAvatar.initials(from: env.store.displayName),
                          avatarAction: { showSettings = true },
                          trailingIcon: .home,
                          trailingLabel: "Revenir à Quinze",
                          trailingAction: { env.openSpace(.quinze) })
                if env.restrictions.isRestrictionActive {
                    restrictionBanner
                }
                if let errorMessage {
                    HomeErrorBanner(message: errorMessage) { self.errorMessage = nil }
                }
                TodayInChurchCard(date: now)
                    .qAppear(0)
                if store.engine == nil {
                    EmptyStateView(icon: .book, pastel: .yellow, message: "Les premières leçons de l'Église arrivent bientôt.")
                } else {
                    sessionCard
                        .qAppear(1)
                    statsBlock
                        .qAppear(2)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await reload() }
        .navigationDestination(isPresented: $showSettings) { SettingsView() }
        .fullScreenCover(item: $activeRun) { run in
            StudyRunView(run: run, onClose: { activeRun = nil; Task { await reload() } })
        }
        .task { await reload() }
    }

    private var headerName: String {
        let name: String = env.store.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Bienvenue" : name
    }

    private func reload() async {
        now = .now
        await store.refresh()
    }

    // MARK: Session of the day

    private var sessionCard: some View {
        let resumable = store.resumableSession()
        let next = store.upNextTitle
        return PastelCard(.yellow, padding: 20) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.s) {
                    QPill(text: "Séance du jour", icon: .book)
                    Spacer(minLength: 0)
                }
                CardTitle(next.map { "Prochaine leçon : \($0)" } ?? "Révisions du jour")
                Text("Le cours d'abord, puis les questions. Une leçon est validée à 80 % ; chaque module se termine par un contrôle.")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.onPastelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(resumable == nil ? "Commencer" : "Reprendre") {
                    start(resume: resumable)
                }
                .buttonStyle(.primary)
                .disabled(isStarting)
                Button("Réviser encore") { startPractice() }
                    .buttonStyle(.secondary)
                    .disabled(isStarting)
            }
        }
    }

    private var statsBlock: some View {
        let progress = store.progress
        let done = progress?.lessonsCompleted ?? 0
        let total = progress?.lessonsTotal ?? 0
        return StatGrid {
            StatMiniCard(icon: .path, value: "\(done)/\(total)", label: "Leçons validées", pastel: .blue)
            StatMiniCard(icon: .refresh, value: "\(store.today.dueReviewCount)", label: "Révisions à faire", pastel: .pink)
        }
    }

    private var restrictionBanner: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            QIconView(icon: .lock, size: 18)
                .foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 6) {
                Text("Tes apps sont bloquées : ta leçon Quinze t'attend.")
                    .font(Theme.Font.callout(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Button("Aller à Quinze") { env.openSpace(.quinze) }
                    .font(Theme.Font.callout(.semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.m)
        .card()
    }

    private func start(resume: LessonController?) {
        guard !isStarting else { return }
        isStarting = true
        errorMessage = nil
        Task { @MainActor in
            defer { isStarting = false }
            do {
                let controller: LessonController
                if let resume {
                    controller = resume
                } else {
                    controller = try await store.startDailySession()
                }
                activeRun = env.study.single(controller)
            } catch {
                errorMessage = store.errorMessage ?? "Impossible de lancer la séance pour le moment."
            }
        }
    }

    private func startPractice() {
        guard !isStarting else { return }
        isStarting = true
        errorMessage = nil
        Task { @MainActor in
            defer { isStarting = false }
            do {
                activeRun = env.study.single(try await store.startExtraSession())
            } catch {
                errorMessage = store.errorMessage ?? "Impossible de lancer la séance pour le moment."
            }
        }
    }
}

/// « Aujourd'hui dans l'Église » : Coptic date, Adam or Watos day, fast. In the evening the Church already enters
/// the next day: its theotokia is the one of tomorrow.
struct TodayInChurchCard: View {
    let date: Date

    private var calendar: Calendar { .current }
    private var coptic: CopticCalendar.CopticDate { CopticCalendar.copticDate(for: date, calendar: calendar) }
    private var isEvening: Bool { calendar.component(.hour, from: date) >= 18 }
    private var tomorrow: Date { calendar.date(byAdding: .day, value: 1, to: date) ?? date }
    private var tomorrowName: String { CopticCalendar.weekdayName(for: tomorrow, calendar: calendar) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            QSectionTitle("Aujourd'hui dans l'Église")
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Text(coptic.formatted)
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.primaryText)
                Text(coptic.monthNameArabic)
                    .font(.system(.callout))
                    .foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 0)
            }
            line(icon: "music.note",
                 text: "Jour \(CopticCalendar.tune(for: date, calendar: calendar).rawValue) (\(CopticCalendar.weekdayName(for: date, calendar: calendar)))")
            if isEvening {
                line(icon: "moon.stars",
                     text: "Ce soir, l'Église entre déjà dans le \(tomorrowName) : on prie la théotokie du \(tomorrowName) (jour \(CopticCalendar.tune(for: tomorrow, calendar: calendar).rawValue)).")
            }
            if let fast = CopticCalendar.fast(on: date, calendar: calendar) {
                line(icon: "leaf", text: fast)
            } else {
                line(icon: "leaf", text: "Pas de jeûne aujourd'hui")
            }
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }

    private func line(icon: String, text: String) -> some View {
        Label {
            Text(text)
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(Theme.ink)
        }
    }
}

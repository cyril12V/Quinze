import SwiftUI
import LearningCore

/// Home tab (« dashboard » model): greeting header, dynamic title, today's slots as chips and as a
/// carousel of big pastel cards, then streak / reviews, assessment and restriction cards.
/// Wrapped in a `NavigationStack` by `MainTabView`: it hides the system bar and draws `AppHeader`.
struct HomeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var activeRun: StudyRun? = nil
    @State private var resumable: StudyRun? = nil
    @State private var isStarting = false
    @State private var showUnlockDialog = false
    @State private var showDaySheet = false
    @State private var showSettings = false
    @State private var focusedCard: HomeCardID? = nil

    init() {}

    private enum StartAction {
        case slot(SessionSlot)
        case extra
        case assessment
        case resume(StudyRun)
    }

    /// Width taken off each card so that the next one peeks out of the carousel.
    private static let carouselPeek: CGFloat = 22

    var body: some View {
        QScreen {
            content
        }
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await reload() }
        .navigationDestination(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showDaySheet) {
            HomeDaySheet(day: env.study.today.day,
                         slots: env.study.today.slots,
                         schedule: env.settings.schedule,
                         blocking: env.restrictions.isEnabled && env.restrictions.hasSelection
                             && env.restrictions.authorization == .approved,
                         minutes: Dictionary(uniqueKeysWithValues: Subject.allCases.map { ($0, env.settings.study.minutes(for: $0)) }))
        }
        .fullScreenCover(item: $activeRun) { run in
            StudyRunView(run: run, onClose: closeLesson)
        }
        .confirmationDialog(
            "Débloquer tes apps maintenant ?",
            isPresented: $showUnlockDialog,
            titleVisibility: .visible
        ) {
            Button("Débloquer mes apps", role: .destructive, action: emergencyUnlock)
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Tes apps seront accessibles tout de suite. Ta leçon reste disponible quand tu voudras la faire.")
        }
        .task { await reload() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { @MainActor in await reload() }
            }
        }
    }

    // MARK: Content

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.section) {
            header

            if let message = env.study.errorMessage {
                HomeErrorBanner(message: message) { env.study.errorMessage = nil }
                    .qAppear(0)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.titleToContent) {
                titleBlock
                lessonsBlock
            }

            if let resumable {
                HomeResumeCard(sessionName: "\(resumable.controller.subject.displayName) · \(resumable.controller.type.displayName)",
                               isStarting: isStarting) {
                    start(.resume(resumable))
                }
                .qAppear(3)
            }

            statsBlock
                .qAppear(4)

            if env.study.today.assessmentDue {
                HomeAssessmentCard(isStarting: isStarting) { start(.assessment) }
                    .qAppear(5)
            }

            if env.restrictions.isRestrictionActive {
                HomeRestrictionCard(activeSlots: env.restrictions.activeSlots) {
                    showUnlockDialog = true
                }
                .qAppear(6)
            }
        }
    }

    private var header: some View {
        AppHeader(label: "Bonjour",
                  title: headerName,
                  initials: QAvatar.initials(from: env.store.displayName),
                  avatarAction: { showSettings = true },
                  trailingIcon: .calendar,
                  trailingLabel: "Ma journée : horaires et blocages",
                  trailingAction: { showDaySheet = true })
    }

    private var headerName: String {
        let name: String = env.store.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Bienvenue" : name
    }

    // MARK: Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScreenTitle(screenTitle)
            ScreenSubtitle(screenSubtitle)
        }
    }

    private var screenTitle: String {
        switch featuredState {
        case .loading:
            return "Ta journée"
        case .resume(let slot):
            return "Reprends ta leçon \(FrenchLabels.slotPhrase(slot.slot))"
        case .start(let slot):
            return "Ta leçon \(FrenchLabels.slotPhrase(slot.slot)) est prête"
        case .catchUp(let slot):
            return "Rattrape ta leçon \(FrenchLabels.slotPhrase(slot.slot))"
        case .waiting(let slot):
            return "Ta prochaine leçon est à \(slot.scheduledTime)"
        case .extra(let allDone):
            return allDone ? "Bravo, ta journée est terminée" : "Prêt à réviser ?"
        }
    }

    private var screenSubtitle: String {
        let today: TodayState = env.study.today
        if today.slots.isEmpty {
            return env.study.isLoading ? "Je prépare ta journée…" : "Une courte série d'exercices, à ton rythme."
        }
        let done: Int = today.completedCount
        let total: Int = today.slots.count
        if done > 1 {
            return "\(done) leçons sur \(total) terminées aujourd'hui."
        }
        return "\(done) leçon sur \(total) terminée aujourd'hui."
    }

    // MARK: Lessons (chips + carousel)

    @ViewBuilder private var lessonsBlock: some View {
        if case .loading = featuredState {
            SkeletonCard(height: 300)
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.card) {
                if !env.study.today.slots.isEmpty {
                    slotChips
                }
                carousel
            }
        }
    }

    private var selectedCard: HomeCardID? {
        focusedCard ?? carouselItems.first?.id
    }

    private var slotChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(env.study.today.slots) { slot in
                    slotChip(slot)
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, Theme.Spacing.page, for: .scrollContent)
        .padding(.horizontal, -Theme.Spacing.page)
    }

    private func slotChip(_ slot: SlotState) -> some View {
        FilterChip(title: "\(slot.slot.displayName) · \(slot.scheduledTime)",
                   icon: slot.status.homeIcon,
                   iconFill: slot.status.homeIconFill,
                   isSelected: selectedCard == HomeCardID.slot(slot.slot)) {
            select(.slot(slot.slot))
        }
        .accessibilityLabel("\(slot.slot.displayName), \(slot.scheduledTime), \(slot.status.homeLabel.lowercased())")
        .accessibilityHint("Affiche la carte de cette leçon")
    }

    private func select(_ id: HomeCardID) {
        if reduceMotion {
            focusedCard = id
        } else {
            withAnimation(.easeOut(duration: 0.25)) { focusedCard = id }
        }
    }

    private var carousel: some View {
        let items: [HomeCarouselItem] = carouselItems
        return ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Theme.Spacing.card) {
                ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                    carouselCard(item, index: offset)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $focusedCard)
        .contentMargins(.horizontal, Theme.Spacing.page, for: .scrollContent)
        .padding(.horizontal, -Theme.Spacing.page)
    }

    @ViewBuilder private func carouselCard(_ item: HomeCarouselItem, index: Int) -> some View {
        switch item.kind {
        case .slot(let slot):
            HomeSlotCard(slot: slot, minutes: sittingMinutes, isStarting: isStarting) { start(.slot(slot.slot)) }
                .containerRelativeFrame(.horizontal) { length, _ in max(length - Self.carouselPeek, 240) }
                .qAppear(index + 1)
        case .extra(let allDone):
            HomeExtraCard(allDone: allDone, minutes: sittingMinutes, isStarting: isStarting) { start(.extra) }
                .containerRelativeFrame(.horizontal) { length, _ in max(length - Self.carouselPeek, 240) }
                .qAppear(index + 1)
        }
    }

    /// Length of a sitting: every enabled subject one after the other.
    private var sittingMinutes: Int {
        env.study.enabledSubjects.reduce(0) { $0 + env.settings.study.minutes(for: $1) }
    }

    // MARK: Stats

    private var statsBlock: some View {
        let today: TodayState = env.study.today
        let reviewsLabel: String = today.dueReviewCount > 1 ? "Révisions à faire" : "Révision à faire"
        return StatGrid {
            StatMiniCard(icon: .flame, value: FrenchLabels.days(today.streakDays), label: "Série en cours", pastel: .pink)
            StatMiniCard(icon: .refresh, value: "\(today.dueReviewCount)", label: reviewsLabel, pastel: .blue)
        }
    }

    // MARK: Featured slot

    private var featuredState: HomeFeaturedState {
        let today: TodayState = env.study.today
        if today.slots.isEmpty {
            return env.study.isLoading ? .loading : .extra(allDone: false)
        }
        if let slot = today.slots.first(where: { $0.status == .inProgress }) { return .resume(slot) }
        if let slot = today.slots.first(where: { $0.status == .available }) { return .start(slot) }
        if let slot = today.slots.first(where: { $0.status == .missed }) { return .catchUp(slot) }
        if let slot = today.slots.first(where: { $0.status == .upcoming }) { return .waiting(slot) }
        return .extra(allDone: true)
    }

    private var featuredSlot: SlotState? {
        switch featuredState {
        case .resume(let slot), .start(let slot), .catchUp(let slot), .waiting(let slot):
            return slot
        case .loading, .extra:
            return nil
        }
    }

    /// Featured slot first, then the other slots still to do, then the finished ones.
    /// With the 3 lessons done (or no slot at all) the « leçon supplémentaire » card leads.
    private var carouselItems: [HomeCarouselItem] {
        let slots: [SlotState] = env.study.today.slots
        if slots.isEmpty {
            return [HomeCarouselItem(kind: .extra(allDone: false))]
        }
        let lead: SlotState? = featuredSlot
        var items: [HomeCarouselItem] = []
        if let lead {
            items.append(HomeCarouselItem(kind: .slot(lead)))
        } else {
            items.append(HomeCarouselItem(kind: .extra(allDone: true)))
        }
        for slot in slots where slot.status != .completed && slot.slot != lead?.slot {
            items.append(HomeCarouselItem(kind: .slot(slot)))
        }
        for slot in slots where slot.status == .completed {
            items.append(HomeCarouselItem(kind: .slot(slot)))
        }
        return items
    }

    // MARK: Actions

    private func start(_ action: StartAction) {
        guard !isStarting else { return }
        isStarting = true
        env.study.errorMessage = nil
        Task { @MainActor in
            defer { isStarting = false }
            do {
                let run: StudyRun
                switch action {
                case .slot(let slot):
                    run = try await env.study.startSlot(slot)
                case .extra:
                    run = try await env.study.startExtra()
                case .assessment:
                    run = try await env.study.startAssessment()
                case .resume(let resumed):
                    run = resumed
                }
                env.study.focusSubject = run.controller.subject
                activeRun = run
            } catch {
                if env.study.errorMessage == nil {
                    env.study.errorMessage = "Impossible de lancer la leçon pour le moment. Réessaie dans un instant."
                }
            }
        }
    }

    private func closeLesson() {
        activeRun = nil
        Task { @MainActor in
            await reload()
            focusedCard = carouselItems.first?.id
        }
    }

    private func emergencyUnlock() {
        env.restrictions.emergencyUnlock(reason: "home_emergency_unlock")
        Task { @MainActor in await reload() }
    }

    private func reload() async {
        await env.study.refresh()
        guard activeRun == nil else { return }
        let candidate: StudyRun? = env.study.resumableRun()
        if let candidate, candidate.controller.slot == nil, !candidate.controller.isFinished {
            resumable = candidate
        } else {
            resumable = nil
        }
    }
}

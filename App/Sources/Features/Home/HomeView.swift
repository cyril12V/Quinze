import SwiftUI
import LearningCore

/// Home tab: greeting header, dynamic title, today's slots as chips and, for the slot shown, one block per
/// subject (anglais, arabe, culture G) started separately; then free practice, streak / reviews, assessment
/// and restriction cards.
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
    @State private var selectedSlot: SessionSlot? = nil
    @State private var infoMessage: String? = nil

    init() {}

    private enum StartAction {
        case subject(Subject, SessionSlot)
        case extra(Subject)
        case assessment
        case resume(StudyRun)
    }

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
            if let infoMessage {
                HomeInfoBanner(message: infoMessage) { self.infoMessage = nil }
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

    // MARK: Lessons (slot chips + one block per subject)

    @ViewBuilder private var lessonsBlock: some View {
        if case .loading = featuredState {
            SkeletonCard(height: 300)
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.card) {
                if let slot = shownSlot {
                    slotChips
                    ForEach(Array(slot.parts.enumerated()), id: \.element.id) { offset, part in
                        HomeSubjectBlock(subject: part.subject, status: part.status, scheduledTime: slot.scheduledTime,
                                         minutes: env.settings.study.minutes(for: part.subject),
                                         upNext: env.study.store(part.subject).upNextTitle,
                                         isStarting: isStarting,
                                         onStart: { start(.subject(part.subject, slot.slot)) },
                                         onPractice: { start(.extra(part.subject)) })
                            .qAppear(offset + 1)
                    }
                }
                freePractice
            }
        }
    }

    /// The slot whose subject blocks are shown: the one chosen with the chips, else the featured one.
    private var shownSlot: SlotState? {
        let slots: [SlotState] = env.study.today.slots
        if let selectedSlot, let slot = slots.first(where: { $0.slot == selectedSlot }) { return slot }
        return featuredSlot ?? slots.last
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
                   isSelected: shownSlot?.slot == slot.slot) {
            if reduceMotion { selectedSlot = slot.slot } else { withAnimation(.easeOut(duration: 0.2)) { selectedSlot = slot.slot } }
        }
        .accessibilityLabel("\(slot.slot.displayName), \(slot.scheduledTime), \(slot.status.homeLabel.lowercased())")
        .accessibilityHint("Affiche les matières de cette leçon")
    }

    /// « Entraînement libre » : one more session in the subject of your choice, whenever you want.
    private var freePractice: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            QSectionTitle("Entraînement libre")
            Text("Une séance en plus, quand tu veux : révisions, et la leçon suivante s'il n'y a rien à revoir.")
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Spacing.s) {
                ForEach(env.study.enabledSubjects) { subject in
                    Button { start(.extra(subject)) } label: {
                        Text("\(subject.emoji) \(subject.shortName)")
                            .font(Theme.Font.callout(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.secondary)
                    .disabled(isStarting)
                    .accessibilityLabel("Entraînement libre, \(subject.displayName)")
                }
            }
        }
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

    // MARK: Actions

    private func start(_ action: StartAction) {
        guard !isStarting else { return }
        isStarting = true
        env.study.errorMessage = nil
        infoMessage = nil
        Task { @MainActor in
            defer { isStarting = false }
            do {
                let run: StudyRun
                switch action {
                case .subject(let subject, let slot):
                    guard let started = try await env.study.startSubject(subject, slot: slot) else {
                        infoMessage = "Rien de nouveau en \(subject.shortName.lowercased()) pour cette leçon : c'est validé."
                        return
                    }
                    run = started
                case .extra(let subject):
                    run = try await env.study.startExtra(subject)
                case .assessment:
                    run = try await env.study.startAssessment()
                case .resume(let resumed):
                    run = resumed
                }
                env.study.focusSubject = run.controller.subject
                activeRun = run
            } catch {
                if env.study.errorMessage == nil {
                    env.study.errorMessage = "Impossible de lancer la séance pour le moment. Réessaie dans un instant."
                }
            }
        }
    }

    private func closeLesson() {
        activeRun = nil
        Task { @MainActor in await reload() }
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

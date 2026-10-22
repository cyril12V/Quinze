import SwiftUI
import LearningCore

// « Parcours » tab: the modules of the course as big pastel cards, each opening a read-only list of its
// lessons. The engine always picks the lesson to do: nothing here starts a specific lesson.

// MARK: - Model

enum PathModuleStatus: Sendable {
    case upcoming, current, done

    var label: String {
        switch self {
        case .upcoming: return "À venir"
        case .current: return "En cours"
        case .done: return "Terminé"
        }
    }

    var icon: QIcon {
        switch self {
        case .upcoming: return .clock
        case .current: return .play
        case .done: return .check
        }
    }
}

enum PathFilter: CaseIterable, Identifiable, Sendable {
    case all, current, done

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return "Tous"
        case .current: return "En cours"
        case .done: return "Terminés"
        }
    }

    func includes(_ status: PathModuleStatus) -> Bool {
        switch self {
        case .all: return true
        case .current: return status == .current
        case .done: return status == .done
        }
    }
}

struct PathModuleSummary: Identifiable, Sendable {
    let info: ModuleInfo
    /// Position in the course (drives the alternating pastel).
    let position: Int
    let lessons: [Lesson]
    let doneCount: Int
    let status: PathModuleStatus

    var id: Int { info.id }
    var total: Int { lessons.count }
    var progress: Double { total == 0 ? 0 : Double(doneCount) / Double(total) }
    var pastel: Pastel { Pastel.cycle(position) }

    /// "9 leçons · 4 faites"
    var countText: String {
        let lessonsText: String = total > 1 ? "\(total) leçons" : "\(total) leçon"
        let doneText: String = doneCount > 1 ? "\(doneCount) faites" : "\(doneCount) faite"
        return "\(lessonsText) · \(doneText)"
    }

    /// Sentence read by VoiceOver for the whole card.
    var spokenSummary: String {
        "Module \(id), \(info.title). \(countText). \(status.label)."
    }
}

struct PathSnapshot: Sendable {
    let modules: [PathModuleSummary]
    /// Lesson the engine would teach next.
    let currentLessonId: String?

    var lessonsTotal: Int { modules.reduce(0) { $0 + $1.total } }
    var lessonsDone: Int { modules.reduce(0) { $0 + $1.doneCount } }

    static func make(engine: LearningEngine, learner: LearnerSnapshot, now: Date) -> PathSnapshot {
        let lessons: [Lesson] = engine.index.lessonsInOrder
        let completed: Set<String> = learner.completedLessonIds
        let placed: Set<String> = learner.placedLessonIds
        let current: Lesson? = engine.nextLesson(for: learner, now: now)
            ?? lessons.first { !completed.contains($0.id) && !placed.contains($0.id) }

        var byModule: [Int: [Lesson]] = [:]
        for lesson in lessons {
            byModule[lesson.module, default: []].append(lesson)
        }

        let infos: [ModuleInfo] = engine.index.bundle.modules.sorted { $0.id < $1.id }
        var summaries: [PathModuleSummary] = []
        for (position, info) in infos.enumerated() {
            let moduleLessons: [Lesson] = byModule[info.id] ?? []
            let done: Int = moduleLessons.filter { completed.contains($0.id) || placed.contains($0.id) }.count
            let containsCurrent: Bool = current?.module == info.id
            let status: PathModuleStatus
            if !moduleLessons.isEmpty && done == moduleLessons.count {
                status = .done
            } else if containsCurrent || done > 0 {
                status = .current
            } else {
                status = .upcoming
            }
            summaries.append(PathModuleSummary(info: info, position: position, lessons: moduleLessons,
                                               doneCount: done, status: status))
        }
        return PathSnapshot(modules: summaries, currentLessonId: current?.id)
    }
}

// MARK: - Path tab

struct PathView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var filter: PathFilter = .all
    @State private var showSettings = false

    init() {}

    var body: some View {
        let snapshot: PathSnapshot? = makeSnapshot()
        QScreen {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                AppHeader(label: "Apprentissage",
                          title: env.store.languageName,
                          initials: QAvatar.initials(from: env.store.displayName),
                          avatarAction: { showSettings = true })
                SubjectPicker()
                VStack(alignment: .leading, spacing: Theme.Spacing.titleToContent) {
                    titleBlock(snapshot)
                    filterRow
                }
                modulesSection(snapshot)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private func makeSnapshot() -> PathSnapshot? {
        guard let engine = env.store.engine else { return nil }
        return PathSnapshot.make(engine: engine, learner: env.store.learner, now: .now)
    }

    // MARK: Title and filters

    private func titleBlock(_ snapshot: PathSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScreenTitle("Ton parcours")
            ScreenSubtitle(subtitle(snapshot))
        }
    }

    private func subtitle(_ snapshot: PathSnapshot?) -> String {
        guard let snapshot, snapshot.lessonsTotal > 0 else {
            return "On choisit pour toi la leçon qu'il te faut."
        }
        let done: Int = snapshot.lessonsDone
        let doneText: String = done > 1 ? "\(done) leçons faites" : "\(done) leçon faite"
        return "\(doneText) sur \(snapshot.lessonsTotal). On choisit la prochaine pour toi."
    }

    private var filterRow: some View {
        QFlowLayout() {
            ForEach(PathFilter.allCases) { item in
                FilterChip(title: item.title, isSelected: filter == item) {
                    filter = item
                }
            }
        }
    }

    // MARK: Modules

    @ViewBuilder private func modulesSection(_ snapshot: PathSnapshot?) -> some View {
        if let snapshot {
            let visible: [PathModuleSummary] = snapshot.modules.filter { filter.includes($0.status) }
            if snapshot.modules.isEmpty {
                EmptyStateView(icon: .path, pastel: .blue,
                               message: "Ton parcours apparaîtra ici dès que les leçons seront prêtes.")
            } else if visible.isEmpty {
                EmptyStateView(icon: .path, pastel: .pink, message: emptyFilterMessage)
            } else {
                moduleList(visible, currentLessonId: snapshot.currentLessonId)
            }
        } else {
            VStack(spacing: Theme.Spacing.card) {
                SkeletonCard(height: 220)
                SkeletonCard(height: 220)
            }
        }
    }

    private var emptyFilterMessage: String {
        switch filter {
        case .current: return "Aucun module en cours pour l'instant."
        case .done: return "Aucun module terminé pour l'instant. Ça viendra vite !"
        case .all: return "Aucun module à afficher."
        }
    }

    private func moduleList(_ modules: [PathModuleSummary], currentLessonId: String?) -> some View {
        VStack(spacing: Theme.Spacing.card) {
            ForEach(Array(modules.enumerated()), id: \.element.id) { offset, module in
                NavigationLink {
                    ModuleDetailView(module: module, currentLessonId: currentLessonId)
                } label: {
                    PathModuleCard(module: module)
                }
                .buttonStyle(.press)
                .accessibilityHint("Ouvre la liste des leçons du module")
                .qAppear(offset)
            }
        }
    }
}

// MARK: - Module card

struct PathModuleCard: View {
    let module: PathModuleSummary

    var body: some View {
        PastelCard(module.pastel) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                QFlowLayout() {
                    QPill(text: "Module \(module.id)")
                    QPill(text: module.status.label, icon: module.status.icon)
                }
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        CardTitle(module.info.title)
                        Text(module.countText)
                            .font(Theme.Font.callout)
                            .foregroundStyle(Theme.onPastelSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    PortraitSlot(imageName: "module-\(module.id)", width: 110, height: 130)
                }
                QProgressBar(value: module.progress, track: Theme.surface.opacity(0.5), fill: Theme.ink)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(module.spokenSummary)
    }
}

// MARK: - Module detail (read-only)

enum PathLessonState: Sendable {
    case done, placed, current, upcoming

    var label: String {
        switch self {
        case .done: return "Terminée"
        case .placed: return "Déjà acquise"
        case .current: return "Prochaine leçon"
        case .upcoming: return "À venir"
        }
    }

    var icon: QIcon {
        switch self {
        case .done, .placed: return .check
        case .current: return .play
        case .upcoming: return .clock
        }
    }
}

struct ModuleDetailView: View {
    let module: PathModuleSummary
    let currentLessonId: String?

    @Environment(AppEnvironment.self) private var env

    init(module: PathModuleSummary, currentLessonId: String?) {
        self.module = module
        self.currentLessonId = currentLessonId
    }

    var body: some View {
        QScreen {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                VStack(alignment: .leading, spacing: Theme.Spacing.titleToContent) {
                    VStack(alignment: .leading, spacing: 10) {
                        ScreenTitle(module.info.title)
                        ScreenSubtitle(module.info.description)
                    }
                    summaryCard
                        .qAppear(0)
                }
                lessonsList
                QCallout(systemImage: "lightbulb", tint: Theme.ink, fill: Pastel.yellow.soft) {
                    Text("Pas besoin de choisir : à chaque créneau, on te propose automatiquement la leçon qu'il te faut.")
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .qAppear(module.lessons.count + 1)
            }
        }
        .navigationTitle("Module \(module.id)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryCard: some View {
        PastelCard(module.pastel) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                QFlowLayout() {
                    QPill(text: "Module \(module.id)")
                    QPill(text: module.status.label, icon: module.status.icon)
                }
                Text(module.countText)
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.ink)
                QProgressBar(value: module.progress, track: Theme.surface.opacity(0.5), fill: Theme.ink)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(module.spokenSummary)
    }

    @ViewBuilder private var lessonsList: some View {
        if module.lessons.isEmpty {
            EmptyStateView(icon: .book, pastel: .blue, message: "Les leçons de ce module arrivent bientôt.")
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.card) {
                QSectionTitle("Les leçons")
                ForEach(Array(module.lessons.enumerated()), id: \.element.id) { offset, lesson in
                    PathLessonRow(lesson: lesson, state: state(of: lesson), pastel: module.pastel)
                        .qAppear(offset + 1)
                }
            }
        }
    }

    private func state(of lesson: Lesson) -> PathLessonState {
        let learner: LearnerSnapshot = env.store.learner
        if learner.completedLessonIds.contains(lesson.id) { return .done }
        if learner.placedLessonIds.contains(lesson.id) { return .placed }
        if lesson.id == currentLessonId { return .current }
        return .upcoming
    }
}

struct PathLessonRow: View {
    let lesson: Lesson
    let state: PathLessonState
    let pastel: Pastel

    var body: some View {
        Group {
            if state == .current {
                PastelCard(pastel) { rowContent }
            } else {
                rowContent.card()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var markerFill: Color {
        switch state {
        case .done, .placed: return Theme.green
        case .current: return Theme.ink
        case .upcoming: return Theme.background
        }
    }

    private var markerTint: Color {
        switch state {
        case .done, .placed: return Theme.ink
        case .current: return Theme.onInk
        case .upcoming: return Theme.tertiaryText
        }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 14) {
            QIconView(icon: state.icon, size: 18)
                .foregroundStyle(markerTint)
                .frame(width: 38, height: 38)
                .background(Circle().fill(markerFill))
            VStack(alignment: .leading, spacing: 4) {
                Text(lesson.title)
                    .font(Theme.Font.headline)
                    .foregroundStyle(state == .current ? Theme.ink : Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(lesson.description)
                    .font(Theme.Font.caption)
                    .foregroundStyle(state == .current ? Theme.onPastelSecondary : Theme.tertiaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(state.label)
                    .font(Theme.Font.caption(.semibold))
                    .foregroundStyle(state == .current ? Theme.ink : Theme.secondaryText)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

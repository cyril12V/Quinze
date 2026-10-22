import SwiftUI
import LearningCore

/// The three modes of the dictionary tab.
enum DictionaryMode: String, CaseIterable, Identifiable, Sendable {
    /// Search and the words added to the reviews.
    case words
    /// One series of words per lesson, to learn very quickly.
    case series
    /// Games with lots of words.
    case games

    var id: String { rawValue }

    var title: String {
        switch self {
        case .words: return "Mots"
        case .series: return "Séries"
        case .games: return "Jeux"
        }
    }

    var icon: QIcon {
        switch self {
        case .words: return .search
        case .series: return .book
        case .games: return .sparkle
        }
    }

    var hint: String {
        switch self {
        case .words: return "Cherche un mot et retrouve tes mots à réviser."
        case .series: return "Une série de mots par leçon de ton parcours."
        case .games: return "Des jeux rapides pour retenir plein de mots."
        }
    }
}

/// « Dictionnaire » tab root: subject switcher, then three modes: search (« Mots »), word series
/// (« Séries ») and games (« Jeux »). Lives inside the `NavigationStack` that `MainTabView` creates for the
/// tab: it hides the system navigation bar and draws its own `AppHeader`.
struct DictionaryView: View {
    @Environment(AppEnvironment.self) private var env
    @SceneStorage("quinze.dictionary.mode") private var mode: DictionaryMode = .words
    @State private var query: String = ""
    @State private var results: [DictionaryItem] = []
    @State private var trackedItems: [DictionaryItem] = []
    @State private var selected: DictionaryItem?
    @State private var tutorRequest: TutorRequest?
    @State private var showSettings = false
    @FocusState private var searchFocused: Bool

    init() {}

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var firstName: String {
        env.store.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var body: some View {
        QScreen {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                AppHeader(
                    label: firstName.isEmpty ? "Apprentissage" : "Bonjour",
                    title: firstName.isEmpty ? env.store.languageName : firstName,
                    initials: QAvatar.initials(from: env.store.displayName),
                    avatarAction: { showSettings = true }
                )
                SubjectPicker()
            }
            ScreenTitle("Dictionnaire")
                .padding(.top, Theme.Spacing.section)
            DictionaryModePicker(selection: $mode)
                .padding(.top, Theme.Spacing.m)
            modeContent
                .padding(.top, Theme.Spacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showSettings) {
            SettingsView()
        }
        .onChange(of: query) { _, _ in runSearch() }
        .onChange(of: selected?.id) { _, newValue in
            if newValue == nil { loadTracked() }
        }
        .onChange(of: env.study.focusSubject) { _, _ in
            subjectDidChange()
        }
        .onChange(of: mode) { _, newMode in
            searchFocused = false
            if newMode == .words { loadTracked() }
        }
        .task { loadTracked() }
        .sheet(item: $selected) { item in
            WordSheet(item: item)
        }
        .sheet(item: $tutorRequest) { request in
            TutorSheet(subject: request.subject)
        }
    }

    @ViewBuilder private var modeContent: some View {
        switch mode {
        case .words:
            wordsContent
        case .series:
            WordSeriesListView()
        case .games:
            WordGamesView()
        }
    }

    private var wordsContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.section) {
            searchField
            content
        }
    }

    // MARK: Subject-dependent texts

    private var searchPlaceholder: String {
        switch env.store.subject {
        case .english: return "Chercher un mot"
        case .arabic: return "Chercher un mot arabe ou français"
        case .culture: return "Chercher une notion, un nom, une date"
        }
    }

    private var idleMessage: String {
        switch env.store.subject {
        case .english:
            return "Cherche un mot anglais ou français pour voir sa fiche. Les mots que tu choisis d'apprendre apparaîtront ici."
        case .arabic:
            return "Cherche un mot arabe ou sa traduction pour voir sa fiche. Les mots que tu choisis d'apprendre apparaîtront ici."
        case .culture:
            return "Cherche une notion, un personnage, un lieu ou une date pour voir sa fiche. Ce que tu choisis d'apprendre apparaîtra ici."
        }
    }

    // MARK: Search field

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.s + 2) {
            QIconView(icon: .search, size: 20)
                .foregroundStyle(Theme.tertiaryText)
            TextField(searchPlaceholder, text: $query)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    QIconView(icon: .close, size: 16)
                        .foregroundStyle(Theme.tertiaryText)
                        .frame(minWidth: Theme.minTapSize, minHeight: Theme.minTapSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.press)
                .accessibilityLabel("Effacer la recherche")
            }
        }
        .qField(isFocused: searchFocused)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if trimmedQuery.isEmpty {
            idleContent
        } else {
            searchContent
        }
    }

    /// Nothing typed: the tracked words as pastel chips, or an illustrated empty state.
    @ViewBuilder private var idleContent: some View {
        if trackedItems.isEmpty {
            EmptyStateView(
                icon: .dictionary,
                pastel: .blue,
                message: idleMessage
            )
            .qAppear(0)
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                QSectionTitle("Tes mots à réviser")
                QFlowLayout() {
                    ForEach(trackedItems) { item in
                        TrackedWordChip(item: item) {
                            selected = item
                        }
                    }
                }
            }
            .qAppear(0)
        }
    }

    @ViewBuilder private var searchContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.card) {
            if results.isEmpty {
                EmptyStateView(
                    icon: .search,
                    pastel: .yellow,
                    message: "Aucun mot trouvé pour « \(trimmedQuery) »."
                )
            } else {
                QSectionTitle("Résultats")
                VStack(spacing: Theme.Spacing.s) {
                    ForEach(results) { item in
                        DictionaryRow(item: item, isTracked: env.store.isWordTracked(item.id)) {
                            selected = item
                        }
                    }
                }
            }
            Button("Demander l'explication de « \(trimmedQuery) »") {
                tutorRequest = TutorRequest(subject: .word(trimmedQuery, sentence: nil))
            }
            .buttonStyle(.secondary)
        }
    }

    // MARK: Data

    private func runSearch() {
        let text: String = trimmedQuery
        if text.isEmpty {
            results = []
        } else {
            results = env.store.searchDictionary(text)
        }
    }

    /// Another subject was picked: its search starts empty and its own tracked words are shown.
    private func subjectDidChange() {
        query = ""
        results = []
        searchFocused = false
        loadTracked()
    }

    /// The store has no list of tracked words: they are the units added from the dictionary.
    private func loadTracked() {
        let store: LearningStore = env.store
        let states: [MemoryState] = store.learner.memoryStates.values
            .filter { $0.source == .dictionary }
            .sorted { $0.firstSeenAt > $1.firstSeenAt }
        var items: [DictionaryItem] = []
        for state in states {
            guard let unit = store.unit(state.unitId), unit.kind == .vocabulary else { continue }
            if let itemId = unit.dictionaryItemId, let item = store.engine?.index.dictionaryById[itemId] {
                items.append(item)
            } else if let item = store.dictionaryEntry(for: unit.title) {
                items.append(item)
            }
        }
        trackedItems = items
    }
}

// MARK: - Mode picker

/// « Mots · Séries · Jeux »: a white capsule, the selected mode in ink.
private struct DictionaryModePicker: View {
    @Binding var selection: DictionaryMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DictionaryMode.allCases) { mode in
                segment(mode)
            }
        }
        .padding(4)
        .background(Capsule().fill(Theme.surface))
    }

    private func segment(_ mode: DictionaryMode) -> some View {
        let isSelected: Bool = selection == mode
        return Button {
            selection = mode
        } label: {
            HStack(spacing: 6) {
                QIconView(icon: mode.icon, size: 14)
                Text(mode.title)
                    .font(Theme.Font.caption(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? Theme.onInk : Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(Capsule().fill(isSelected ? Theme.ink : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.press)
        .accessibilityLabel(mode.title)
        .accessibilityHint(mode.hint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Rows & chips

/// Tracked word: white capsule with a green check, Arabic in a larger font.
private struct TrackedWordChip: View {
    let item: DictionaryItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                QIconView(icon: .check, size: 14)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Pastel.green.color))
                StudiedText(text: item.word, size: .chip)
                    .lineLimit(1)
            }
            .padding(.leading, 5)
            .padding(.trailing, 14)
            .frame(minHeight: 38)
            .foregroundStyle(Theme.ink)
            .background(Capsule().fill(Theme.surface))
            .frame(minHeight: Theme.minTapSize)
            .contentShape(Capsule())
        }
        .buttonStyle(.press)
        .accessibilityLabel(item.word)
        .accessibilityHint("Ouvre la fiche du mot")
    }
}

/// White row (radius 16): word (with its reading for Arabic), part of speech, translation; a pastel pill
/// when the word is tracked.
private struct DictionaryRow: View {
    let item: DictionaryItem
    let isTracked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s + 2) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                        StudiedText(text: item.word, size: .row)
                            .foregroundStyle(Theme.primaryText)
                        Text(item.partOfSpeechLabel)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    if let reading = item.reading {
                        Text(reading)
                            .font(Theme.Font.caption(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Text(item.translation)
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isTracked {
                    QPill(text: "Suivi", icon: .check, fill: Pastel.green.color, foreground: Theme.ink)
                }
                QIconView(icon: .chevronRight, size: 14)
                    .foregroundStyle(Theme.inactive)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s + 4)
            .frame(minHeight: Theme.minTapSize)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.surface)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        }
        .buttonStyle(.press)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvre la fiche du mot")
    }
}

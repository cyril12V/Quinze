import SwiftUI
import LearningCore

/// « Dictionnaire » tab root: search in the dictionary and the words the learner added to his reviews.
/// Lives inside the `NavigationStack` that `MainTabView` creates for the tab: it hides the system
/// navigation bar and draws its own `AppHeader`.
struct DictionaryView: View {
    @Environment(AppEnvironment.self) private var env
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
            AppHeader(
                label: firstName.isEmpty ? "Apprentissage" : "Bonjour",
                title: firstName.isEmpty ? env.store.languageName : firstName,
                initials: QAvatar.initials(from: env.store.displayName),
                avatarAction: { showSettings = true }
            )
            ScreenTitle("Dictionnaire")
                .padding(.top, Theme.Spacing.section)
            searchField
                .padding(.top, Theme.Spacing.titleToContent)
            content
                .padding(.top, Theme.Spacing.section)
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
        .task { loadTracked() }
        .sheet(item: $selected) { item in
            WordSheet(item: item)
        }
        .sheet(item: $tutorRequest) { request in
            TutorSheet(subject: request.subject)
        }
    }

    // MARK: Search field

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.s + 2) {
            QIconView(icon: .search, size: 20)
                .foregroundStyle(Theme.tertiaryText)
            TextField("Chercher un mot", text: $query)
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
                message: "Cherche un mot anglais ou français pour voir sa fiche. Les mots que tu choisis d'apprendre apparaîtront ici."
            )
            .qAppear(0)
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                QSectionTitle("Tes mots à réviser")
                QFlowLayout() {
                    ForEach(trackedItems) { item in
                        FilterChip(title: item.word, icon: .check, iconFill: Pastel.green.color) {
                            selected = item
                        }
                        .accessibilityHint("Ouvre la fiche du mot")
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

    /// The store has no list of tracked words: they are the units added from the dictionary.
    private func loadTracked() {
        let states: [MemoryState] = env.store.learner.memoryStates.values
            .filter { $0.source == .dictionary }
            .sorted { $0.firstSeenAt > $1.firstSeenAt }
        var items: [DictionaryItem] = []
        for state in states {
            guard let unit = env.store.unit(state.unitId), unit.kind == .vocabulary else { continue }
            if let item = env.store.dictionaryEntry(for: unit.title) {
                items.append(item)
            }
        }
        trackedItems = items
    }
}

/// White row (radius 16): word, part of speech, translation; a pastel pill when the word is tracked.
private struct DictionaryRow: View {
    let item: DictionaryItem
    let isTracked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s + 2) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                        Text(item.word)
                            .font(Theme.Font.headline)
                            .foregroundStyle(Theme.primaryText)
                        Text(FrenchLabels.partOfSpeech(item.partOfSpeech))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    Text(item.translation)
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.secondaryText)
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

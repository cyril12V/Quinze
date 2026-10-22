import SwiftUI

/// One subject's own space (tab « Anglais », « Arabe », « Culture G »): its path, its words and games, its
/// progress. Nothing of the other subjects shows here.
struct SubjectSpaceView: View {
    let subject: Subject

    @Environment(AppEnvironment.self) private var env
    @State private var section: Section = .path

    enum Section: String, CaseIterable, Identifiable {
        case path = "Parcours"
        case words = "Mots & jeux"
        case progress = "Progrès"
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if env.stores[subject]?.engine == nil {
                QScreen {
                    EmptyStateView(icon: .book, pastel: .blue, message: "Le contenu de \(subject.displayName.lowercased()) arrive bientôt.")
                }
            } else {
                switch section {
                case .path: PathView()
                case .words: DictionaryView()
                case .progress: ProgressDashboardView()
                }
            }
        }
        .environment(\.subjectLocked, true)
        .studySubject(subject)
        .safeAreaInset(edge: .top, spacing: 0) { bar }
        .onAppear {
            if env.study.focusSubject != subject {
                env.study.focusSubject = subject
                Task { await env.store.refresh() }
            }
        }
    }

    private var bar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("\(subject.emoji) \(subject.displayName)")
                .font(Theme.Font.headline)
                .foregroundStyle(Theme.primaryText)
                .accessibilityAddTraits(.isHeader)
            Picker("Rubrique", selection: $section) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.s)
        .qContentWidth()
        .background(Theme.background)
    }
}

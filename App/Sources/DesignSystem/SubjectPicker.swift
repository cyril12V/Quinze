import SwiftUI

/// Chips « 🇬🇧 Anglais · 🇪🇬 Arabe · 🌍 Culture » that switch the subject shown by a single-subject screen
/// (parcours, progrès). Only subjects whose content is installed are listed.
struct SubjectPicker: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let subjects = Subject.studyOrder.filter { env.stores[$0]?.engine != nil }
        if subjects.count > 1 {
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(subjects) { subject in
                        FilterChip(title: "\(subject.emoji) \(subject.shortName)",
                                   isSelected: env.study.focusSubject == subject) {
                            select(subject)
                        }
                        .accessibilityLabel(subject.displayName)
                        .accessibilityAddTraits(env.study.focusSubject == subject ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, Theme.Spacing.page, for: .scrollContent)
            .padding(.horizontal, -Theme.Spacing.page)
        }
    }

    private func select(_ subject: Subject) {
        guard env.study.focusSubject != subject else { return }
        env.study.focusSubject = subject
        Task { await env.store.refresh() }
    }
}

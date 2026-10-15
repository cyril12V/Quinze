import SwiftUI
import LearningCore

// MARK: - Shared types

/// Wraps a tutor subject so it can drive `.sheet(item:)`.
struct TutorRequest: Identifiable, Equatable {
    let id = UUID()
    let subject: TutorSubject
}

private struct TutorAllowsPracticeKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    /// False inside a lesson: the focused practice would start a second session on top of the current one.
    var tutorAllowsPractice: Bool {
        get { self[TutorAllowsPracticeKey.self] }
        set { self[TutorAllowsPracticeKey.self] = newValue }
    }
}

private struct TutorEntry: Identifiable, Equatable {
    let id = UUID()
    let role: TutorMessage.Role
    let text: String
    var examples: [Example] = []
    var source: TutorReplySource? = nil
}

// MARK: - Sheet

/// « Explique-moi » : short explanation first, then details and follow-up questions.
struct TutorSheet: View {
    let subject: TutorSubject

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tutorAllowsPractice) private var allowsPractice
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var entries: [TutorEntry] = []
    @State private var isLoading = false
    @State private var detailsRequested = false
    @State private var draft: String = ""
    @State private var remainingQuota: Int?
    @State private var practice: LessonController?
    @State private var isStartingPractice = false
    @State private var practiceFailed = false
    @FocusState private var composerFocused: Bool

    private let bottomAnchor = "tutor-bottom"

    init(subject: TutorSubject) {
        self.subject = subject
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.card) {
                        ForEach(entries) { entry in
                            TutorEntryView(entry: entry, languageCode: env.store.learningLanguageCode)
                                .id(entry.id)
                                .qAppear()
                        }
                        if isLoading { loadingRow }
                        if !entries.isEmpty && !isLoading { followUpBlock }
                        Color.clear.frame(height: 1).id(bottomAnchor)
                    }
                    .padding(.horizontal, Theme.Spacing.page)
                    .padding(.top, Theme.Spacing.s)
                    .padding(.bottom, Theme.Spacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: entries.count) { _, _ in scrollToBottom(proxy) }
                .onChange(of: isLoading) { _, _ in scrollToBottom(proxy) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .background(Theme.background.ignoresSafeArea())
        .qSheet()
        .presentationDetents([.medium, .large])
        .fullScreenCover(item: $practice) { controller in
            LessonFlowView(controller: controller, onClose: { practice = nil })
        }
        .task { await loadInitialExplanation() }
    }

    // MARK: Header

    private var subjectTitle: String {
        switch subject {
        case .answer: return "À propos de ta réponse"
        case .rule(let unitId): return env.store.unit(unitId)?.title ?? "Une règle"
        case .word(let word, _): return word
        case .example(let text, _): return text
        }
    }

    /// Tutor icon in a black round, « Ton professeur » and the subject, close button on the right.
    private var sheetHeader: some View {
        HStack(spacing: Theme.Spacing.s + 4) {
            HStack(spacing: Theme.Spacing.s + 4) {
                QIconView(icon: .tutor, size: 20)
                    .foregroundStyle(Theme.onInk)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Theme.ink))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ton professeur")
                        .font(Theme.Font.headline)
                        .foregroundStyle(Theme.primaryText)
                    Text(subjectTitle)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(2)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Spacing.s)
            RoundIconButton(icon: .close, label: "Fermer") { dismiss() }
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.vertical, Theme.Spacing.s)
    }

    /// Soft skeleton lines in a white block while the reply is being prepared.
    private var loadingRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s + 2) {
            Text("Je prépare ma réponse…")
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.secondaryText)
            SkeletonBlock(height: 12, width: 220, radius: Theme.Radius.small)
            SkeletonBlock(height: 12, width: 160, radius: Theme.Radius.small)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    // MARK: Follow-up actions

    private var followUpBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if let quota = remainingQuota, quota <= 3 {
                Text(quota == 0 ? "Tu as utilisé toutes tes explications pour l'instant." : "Explications restantes : \(quota)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.tertiaryText)
            }
            if !detailsRequested {
                Button("Plus de détails", action: requestDetails)
                    .buttonStyle(.secondary)
            }
            QFlowLayout() {
                FilterChip(title: "Explique-moi plus simplement") { ask("Explique-moi plus simplement") }
                FilterChip(title: "Donne-moi un autre exemple") { ask("Donne-moi un autre exemple") }
                FilterChip(title: "Quelle est la différence avec… ?") {
                    draft = "Quelle est la différence avec "
                    composerFocused = true
                }
            }
            practiceBlock
        }
    }

    @ViewBuilder private var practiceBlock: some View {
        if case .rule(let unitId) = subject, allowsPractice {
            Button("Fais-moi réviser cette règle") { startPractice(unitId: unitId) }
                .buttonStyle(.primary)
                .disabled(isStartingPractice)
            if practiceFailed {
                Text("Impossible de lancer l'exercice pour le moment. Réessaie dans un instant.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.error)
            }
        }
    }

    // MARK: Composer

    private var composer: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
            TextField("Pose ta question", text: $draft)
                .focused($composerFocused)
                .submitLabel(.send)
                .onSubmit { ask(draft) }
                .qField(isFocused: composerFocused)
            RoundIconButton(icon: .send, label: "Envoyer", size: 46, fill: Theme.ink, tint: Theme.onInk) {
                ask(draft)
            }
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.35)
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.vertical, Theme.Spacing.s)
        .background(Theme.background)
    }

    private var canSend: Bool {
        !isLoading && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Logic

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        }
    }

    private func append(_ reply: TutorReply) {
        entries.append(TutorEntry(role: .tutor, text: reply.text, examples: reply.examples, source: reply.source))
        remainingQuota = reply.remainingQuota
    }

    private func loadInitialExplanation() async {
        guard entries.isEmpty, !isLoading else { return }
        isLoading = true
        let reply: TutorReply = await env.tutor.explain(subject, detail: .short)
        guard !Task.isCancelled else {
            isLoading = false
            return
        }
        append(reply)
        isLoading = false
    }

    private func requestDetails() {
        guard !isLoading else { return }
        detailsRequested = true
        isLoading = true
        entries.append(TutorEntry(role: .user, text: "Plus de détails"))
        Task { @MainActor in
            let reply: TutorReply = await env.tutor.explain(subject, detail: .detailed)
            append(reply)
            isLoading = false
        }
    }

    private func ask(_ question: String) {
        let trimmed: String = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isLoading else { return }
        let history: [TutorMessage] = entries.map { TutorMessage(role: $0.role, text: $0.text) }
        entries.append(TutorEntry(role: .user, text: trimmed))
        draft = ""
        composerFocused = false
        isLoading = true
        Task { @MainActor in
            let reply: TutorReply = await env.tutor.followUp(about: subject, history: history, question: trimmed)
            append(reply)
            isLoading = false
        }
    }

    private func startPractice(unitId: String) {
        guard !isStartingPractice else { return }
        isStartingPractice = true
        practiceFailed = false
        Task { @MainActor in
            defer { isStartingPractice = false }
            do {
                practice = try await env.store.startFocusedPractice(unitId: unitId)
            } catch {
                practiceFailed = true
            }
        }
    }
}

// MARK: - Conversation entries

private struct TutorEntryView: View {
    let entry: TutorEntry
    let languageCode: String

    var body: some View {
        switch entry.role {
        case .user:
            userBubble
        case .tutor:
            tutorReply
        }
    }

    private var userBubble: some View {
        HStack(spacing: 0) {
            Spacer(minLength: Theme.Spacing.xl)
            Text(entry.text)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s + 4)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                        .fill(Theme.pink)
                )
                .accessibilityLabel("Toi : \(entry.text)")
        }
    }

    private var tutorReply: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s + 2) {
            if entry.source == .fallback || entry.source == .offline {
                QPill(text: "Réponse hors ligne", icon: .info, fill: Theme.warningSoft, foreground: Theme.ink)
            }
            Text(QMarkdown.attributed(entry.text))
                .font(Theme.Font.body)
                .foregroundStyle(Theme.primaryText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .card()
            ForEach(Array(entry.examples.enumerated()), id: \.offset) { _, example in
                PastelCard(.blue, radius: Theme.Radius.medium, padding: Theme.Spacing.m) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        TappableSentenceView(text: example.text, languageCode: languageCode)
                            .font(Theme.Font.body(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text(example.translation)
                            .font(Theme.Font.callout)
                            .foregroundStyle(Theme.onPastelSecondary)
                    }
                }
            }
        }
    }
}

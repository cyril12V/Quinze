import SwiftUI

/// « Professeur IA » : the learner pastes his own Anthropic API key (kept in the Keychain), so the tutor
/// and the grading of free answers work straight from the iPhone, without any backend.
struct AISettingsSection: View {
    @Environment(AppEnvironment.self) private var env

    @State private var draft = ""
    /// Last 4 characters of the saved key, nil when there is none.
    @State private var savedSuffix: String?
    @State private var isReplacing = false
    @State private var isTesting = false
    @State private var message: String?
    @State private var messageKind: FlowMessage.Kind = .info
    @State private var showDeleteConfirm = false

    private static let footer = "Ta clé reste dans le trousseau de cet iPhone : elle ne quitte le téléphone que pour aller chez Anthropic, avec les questions au professeur et les réponses à corriger. Crée-la sur console.anthropic.com > API Keys (il faut un peu de crédit sur le compte). Coût : quelques centimes par jour pour une personne."

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.card) {
            SettingsSection("Professeur IA", footer: Self.footer) {
                if let savedSuffix, !isReplacing {
                    savedKeyRows(suffix: savedSuffix)
                } else {
                    keyEntryRows
                }
            }
            if let message { FlowMessage(text: message, kind: messageKind) }
        }
        .onAppear(perform: refreshStatus)
        .confirmationDialog("Supprimer ta clé Claude ?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Supprimer la clé", role: .destructive, action: deleteKey)
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Le professeur répondra de nouveau avec les explications intégrées à l'app, et tu corrigeras toi-même les réponses libres.")
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func savedKeyRows(suffix: String) -> some View {
        HStack(spacing: Theme.Spacing.s + 2) {
            QIconView(icon: .lock, size: 18)
                .foregroundStyle(Theme.ink)
            Text("Clé enregistrée ✓ (sk-ant-…\(suffix))")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 0)
        }
        .frame(minHeight: Theme.minTapSize + 8)
        .accessibilityElement(children: .combine)
        FlowDivider()
        Button(action: test) {
            HStack(spacing: Theme.Spacing.s) {
                actionLabel(isTesting ? "Test en cours…" : "Tester", icon: .sparkle)
                if isTesting { ProgressView().tint(Theme.ink) }
            }
        }
        .buttonStyle(.press)
        .disabled(isTesting)
        FlowDivider()
        Button {
            isReplacing = true
            draft = ""
            message = nil
        } label: {
            actionLabel("Remplacer la clé", icon: .edit)
        }
        .buttonStyle(.press)
        FlowDivider()
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            actionLabel("Supprimer la clé", icon: .trash, tint: Theme.error)
        }
        .buttonStyle(.press)
    }

    @ViewBuilder
    private var keyEntryRows: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            QFieldLabel("Ta clé API Claude (Anthropic)")
            SecureField("sk-ant-…", text: $draft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(save)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.primaryText)
                .padding(.horizontal, Theme.Spacing.m)
                .frame(minHeight: 48)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.background))
        }
        .padding(.vertical, Theme.Spacing.m)
        FlowDivider()
        Button(action: save) {
            actionLabel("Enregistrer", icon: .check)
        }
        .buttonStyle(.press)
        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if isReplacing {
            FlowDivider()
            Button {
                isReplacing = false
                draft = ""
                message = nil
            } label: {
                actionLabel("Annuler", tint: Theme.secondaryText)
            }
            .buttonStyle(.press)
        }
    }

    /// Text button of a white block, with an optional thin leading icon (same look as SettingsView).
    private func actionLabel(_ title: String, icon: QIcon? = nil, tint: Color = Theme.ink) -> some View {
        HStack(spacing: Theme.Spacing.s + 2) {
            if let icon { QIconView(icon: icon, size: 18) }
            Text(title)
            Spacer(minLength: 0)
        }
        .font(Theme.Font.body(.semibold))
        .foregroundStyle(tint)
        .frame(minHeight: Theme.minTapSize + 8)
        .contentShape(Rectangle())
    }

    // MARK: Actions

    private func refreshStatus() {
        savedSuffix = KeychainStore.apiKey().map { String($0.suffix(4)) }
    }

    private func save() {
        // A pasted key may carry spaces or line breaks: a real key never contains any.
        let key = draft.components(separatedBy: .whitespacesAndNewlines).joined()
        guard !key.isEmpty else { return }
        guard key.hasPrefix("sk-"), key.count >= 20 else {
            show("Ce n'est pas une clé API Anthropic : elle commence par « sk-ant- ». Copie-la depuis console.anthropic.com > API Keys.", .error)
            return
        }
        guard KeychainStore.setAPIKey(key) else {
            show("La clé n'a pas pu être enregistrée dans le trousseau. Réessaie.", .error)
            return
        }
        draft = ""
        isReplacing = false
        refreshStatus()
        show("Clé enregistrée. Touche « Tester » pour vérifier qu'elle fonctionne.", .success)
    }

    private func deleteKey() {
        KeychainStore.deleteAPIKey()
        draft = ""
        isReplacing = false
        refreshStatus()
        show("Clé supprimée de cet iPhone.", .info)
    }

    private func test() {
        guard let key = KeychainStore.apiKey() else {
            refreshStatus()
            return
        }
        guard env.network.isOnline else {
            show(Self.text(of: .offline), .error)
            return
        }
        isTesting = true
        message = nil
        Task {
            defer { isTesting = false }
            do {
                try await ClaudeDirectClient(apiKey: key).ping()
                show("Ça marche : le professeur IA répond avec ta clé.", .success)
            } catch let failure as AIClient.Failure {
                show(Self.text(of: failure), .error)
            } catch {
                show(Self.text(of: .server), .error)
            }
        }
    }

    private func show(_ text: String, _ kind: FlowMessage.Kind) {
        message = text
        messageKind = kind
    }

    private static func text(of failure: AIClient.Failure) -> String {
        switch failure {
        case .unauthorized:
            return "Clé refusée par Anthropic : vérifie qu'elle est complète et toujours active (console.anthropic.com > API Keys)."
        case .rateLimited:
            return "Anthropic est surchargé ou ta limite de requêtes est atteinte. Réessaie dans une minute."
        case .badRequest:
            return "Anthropic a refusé la requête : vérifie qu'il reste du crédit sur ton compte (console.anthropic.com > Billing)."
        case .offline:
            return "Pas de connexion Internet. Vérifie ton réseau et réessaie."
        case .notConfigured:
            return "Aucune clé enregistrée."
        case .unavailable, .server:
            return "Anthropic ne répond pas pour le moment. Réessaie un peu plus tard."
        }
    }
}

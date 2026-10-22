import SwiftUI
import UserNotifications
import LearningCore

/// Settings: subjects, lesson times, reminders, app restrictions, appearance, voices, AI, profile, about.
/// Meant to be pushed inside the navigation stack of the home screen (it does not create its own).
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL

    @State private var draft = DailySchedule.default
    @State private var scheduleIssues: [DailySchedule.Issue] = []
    @State private var nameDraft = ""
    @State private var showPicker = false
    @State private var showEmergencyConfirm = false
    @State private var restrictionMessage: String?
    @State private var showLogoutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var accountMessage: String?
    @State private var accountError: String?

    private var preferences: NotificationPreferences { env.settings.notificationPreferences }
    private var restrictions: RestrictionManager { env.restrictions }

    var body: some View {
        QScreen {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                SubjectsSettingsSection()
                scheduleSection
                reminderSection
                restrictionSection
                AppearanceSettingsSection()
                VoiceSettingsSection()
                if env.auth.isLocalMode { localAccountSection } else { accountSection }
                aboutSection
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .tint(Theme.ink)
        .navigationTitle("Réglages")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            draft = env.settings.schedule
            nameDraft = env.settings.profile.displayName ?? ""
            await env.notifications.refreshAuthorizationStatus()
            env.restrictions.refreshAuthorization()
        }
        .onDisappear(perform: saveName)
        .sheet(isPresented: $showPicker) {
            AppSelectionView(onDone: pickerDone)
        }
    }

    // MARK: Row building blocks

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tint(Theme.ink)
        .frame(minHeight: Theme.minTapSize + 8)
    }

    private func stepperRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int) -> some View {
        Stepper(value: value, in: range, step: step) {
            Text(title)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: Theme.minTapSize + 8)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        LabeledContent {
            Text(value)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.trailing)
        } label: {
            Text(title)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.primaryText)
        }
        .frame(minHeight: Theme.minTapSize + 8)
    }

    /// Text button of a white block, with an optional thin leading icon.
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

    private func linkLabel(_ title: String, icon: QIcon) -> some View {
        HStack(spacing: Theme.Spacing.s + 2) {
            QIconView(icon: icon, size: 18)
                .foregroundStyle(Theme.ink)
            Text(title)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 0)
            QIconView(icon: .chevronRight, size: 14)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(minHeight: Theme.minTapSize + 8)
        .contentShape(Rectangle())
    }

    // MARK: Schedule

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.card) {
            SettingsSection("Tes leçons du jour",
                            footer: "Trois leçons de cinq minutes. Chaque leçon peut être faite jusqu'à \(draft.earlyStartMinutes) minutes avant l'heure prévue.") {
                ForEach(SessionSlot.allCases) { slot in
                    DatePicker(slot.displayName, selection: scheduleBinding(slot), displayedComponents: .hourAndMinute)
                        .font(Theme.Font.body)
                        .tint(Theme.ink)
                        .frame(minHeight: Theme.minTapSize + 8)
                    if slot != .evening { FlowDivider() }
                }
            }
            ForEach(Array(scheduleIssues.enumerated()), id: \.offset) { _, issue in
                FlowMessage(text: issue.message, kind: .error)
            }
        }
    }

    private func scheduleBinding(_ slot: SessionSlot) -> Binding<Date> {
        Binding(get: { draft.time(for: slot).asDate },
                set: { newValue in
                    draft.setTime(TimeOfDay(date: newValue), for: slot)
                    commitDraft()
                })
    }

    /// Saves the schedule when it is valid (restrictions, reminders and sync follow); otherwise shows why not.
    private func commitDraft() {
        scheduleIssues = draft.validate()
        guard scheduleIssues.isEmpty else { return }
        let value = draft
        Task { _ = await env.saveSchedule(value) }
    }

    // MARK: Reminders

    private var reminderSection: some View {
        SettingsSection("Rappels",
                        footer: "Les notifications sont de simples rappels : le blocage des apps n'en dépend pas.") {
            Group {
                toggleRow("Rappel à l'heure de chaque leçon", isOn: preference(\.lessonReminders))
                FlowDivider()
                toggleRow("Relance si la leçon n'est pas faite", isOn: preference(\.unfinishedReminder))
            }
            if preferences.unfinishedReminder {
                FlowDivider()
                stepperRow("Relance après \(preferences.unfinishedReminderDelayMinutes) min",
                           value: delayBinding, range: 10...120, step: 5)
            }
            Group {
                FlowDivider()
                toggleRow("Confirmation quand la leçon est terminée", isOn: preference(\.completionConfirmation))
                FlowDivider()
                toggleRow("Mentionner les révisions dans le rappel du soir", isOn: preference(\.reviewAvailable))
                FlowDivider()
                toggleRow("Alerte si Temps d'écran est désactivé", isOn: preference(\.authorizationProblems))
            }
            if env.notifications.authorizationStatus == .denied {
                FlowDivider()
                notificationsDeniedNotice
            }
        }
    }

    private var notificationsDeniedNotice: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Les notifications sont désactivées pour Quinze dans les Réglages de l'iPhone.")
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: openSystemSettings) {
                HStack(spacing: Theme.Spacing.xs + 2) {
                    Text("Ouvrir les Réglages")
                    QIconView(icon: .arrowRight, size: 14)
                }
                .font(Theme.Font.callout(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(minHeight: Theme.minTapSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.press)
        }
        .padding(.vertical, Theme.Spacing.s)
    }

    private func preference(_ keyPath: WritableKeyPath<NotificationPreferences, Bool>) -> Binding<Bool> {
        Binding(get: { env.settings.notificationPreferences[keyPath: keyPath] },
                set: { newValue in
                    var updated = env.settings.notificationPreferences
                    updated[keyPath: keyPath] = newValue
                    Task { await env.updateNotificationPreferences(updated) }
                })
    }

    private var delayBinding: Binding<Int> {
        Binding(get: { env.settings.notificationPreferences.unfinishedReminderDelayMinutes },
                set: { newValue in
                    var updated = env.settings.notificationPreferences
                    updated.unfinishedReminderDelayMinutes = newValue
                    Task { await env.updateNotificationPreferences(updated) }
                })
    }

    // MARK: Restrictions

    private var restrictionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.card) {
            SettingsSection("Restrictions d'apps",
                            footer: "Les apps choisies sont bloquées à l'heure de chaque leçon et se débloquent quand la leçon est terminée, ou à la fin de l'échéance de sécurité. Le choix reste sur cet iPhone.") {
                toggleRow("Restreindre les apps pendant les leçons",
                          isOn: Binding(get: { restrictions.isEnabled }, set: { setRestrictions($0) }))
                if restrictions.isEnabled || restrictions.authorization == .approved {
                    FlowDivider()
                    modePicker
                    FlowDivider()
                    chooseAppsRow
                    FlowDivider()
                    safetyWindowRow
                    FlowDivider()
                    earlyStartRow
                }
                FlowDivider()
                infoRow("Temps d'écran", authorizationText)
                FlowDivider()
                infoRow("Restrictions actives", activeText)
            }
            if let message = restrictionMessage ?? env.restrictionError {
                FlowMessage(text: message, kind: .error)
            }
            emergencyButton
        }
    }

    private var modePicker: some View {
        Picker(selection: modeBinding) {
            ForEach(RestrictionMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        } label: {
            Text("Mode")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.primaryText)
        }
        .pickerStyle(.menu)
        .tint(Theme.ink)
        .frame(minHeight: Theme.minTapSize + 8)
    }

    private var chooseAppsRow: some View {
        Button {
            showPicker = true
        } label: {
            linkLabel(restrictions.hasSelection ? "Modifier les apps" : "Choisir les apps", icon: .lock)
        }
        .buttonStyle(.press)
    }

    private var safetyWindowRow: some View {
        let value = Binding(get: { draft.safetyWindowMinutes },
                            set: { (newValue: Int) in
                                draft.safetyWindowMinutes = newValue
                                commitDraft()
                            })
        return stepperRow("Échéance de sécurité : \(draft.safetyWindowMinutes) min", value: value,
                          range: DailySchedule.minimumSafetyWindowMinutes...DailySchedule.maximumSafetyWindowMinutes,
                          step: 15)
    }

    private var earlyStartRow: some View {
        let value = Binding(get: { draft.earlyStartMinutes },
                            set: { (newValue: Int) in
                                draft.earlyStartMinutes = newValue
                                commitDraft()
                            })
        return stepperRow("Leçon possible \(draft.earlyStartMinutes) min à l'avance", value: value,
                          range: 0...120, step: 15)
    }

    /// Secondary (white pill) button on the page background, with its confirmation.
    private var emergencyButton: some View {
        Button {
            showEmergencyConfirm = true
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                QIconView(icon: .unlock, size: 18)
                Text("Déblocage d'urgence")
            }
        }
        .buttonStyle(.secondary)
        .confirmationDialog("Débloquer toutes les apps maintenant ?", isPresented: $showEmergencyConfirm,
                            titleVisibility: .visible) {
            Button("Débloquer maintenant", role: .destructive, action: emergencyUnlock)
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("À utiliser en cas de vrai besoin. Les restrictions sont levées et ce déblocage est enregistré.")
        }
    }

    private var modeBinding: Binding<RestrictionMode> {
        Binding(get: { restrictions.mode },
                set: { restrictions.updateSelection(restrictions.selection, mode: $0) })
    }

    private var authorizationText: String {
        switch restrictions.authorization {
        case .approved: return "Autorisé"
        case .denied: return "Refusé"
        case .notDetermined: return "Pas encore demandé"
        case .unavailable: return "Indisponible"
        }
    }

    private var activeText: String {
        let slots = restrictions.activeSlots
        return slots.isEmpty ? "Aucune" : slots.map(\.displayName).joined(separator: ", ")
    }

    private func setRestrictions(_ enabled: Bool) {
        restrictionMessage = nil
        guard enabled else {
            restrictions.setEnabled(false, schedule: env.settings.schedule)
            return
        }
        Task {
            var authorization = restrictions.authorization
            if authorization != .approved { authorization = await restrictions.requestAuthorization() }
            guard authorization == .approved else {
                restrictionMessage = authorization == .unavailable
                    ? "Temps d'écran n'est pas disponible sur cet appareil."
                    : "L'autorisation Temps d'écran est nécessaire. Tu peux la donner dans les Réglages de l'iPhone."
                return
            }
            if restrictions.hasSelection {
                restrictions.setEnabled(true, schedule: env.settings.schedule)
            } else {
                showPicker = true
            }
        }
    }

    private func pickerDone() {
        showPicker = false
        if restrictions.hasSelection, !restrictions.isEnabled, restrictions.authorization == .approved {
            restrictions.setEnabled(true, schedule: env.settings.schedule)
        }
    }

    private func emergencyUnlock() {
        restrictions.emergencyUnlock(reason: "user_settings")
        Task { await env.study.refresh() }
    }

    // MARK: Account

    /// Local mode (no backend configured): only the first name; progress stays on this iPhone.
    private var localAccountSection: some View {
        SettingsSection("Profil",
                        footer: "Mode local : tes progrès sont enregistrés uniquement sur cet iPhone, sans compte ni synchronisation. Le professeur répond à partir des explications intégrées à l'app.") {
            nameRow
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.card) {
            SettingsSection("Compte",
                            footer: "Ton prénom sert uniquement à t'accueillir dans l'application. Il n'est jamais envoyé au professeur IA.") {
                Group {
                    nameRow
                    FlowDivider()
                    infoRow("E-mail", env.auth.email ?? "Non renseigné")
                    FlowDivider()
                    Button(action: exportData) {
                        actionLabel("Exporter mes données")
                    }
                    .buttonStyle(.press)
                    .disabled(isExporting)
                }
                if isExporting {
                    ProgressView()
                        .tint(Theme.ink)
                        .accessibilityLabel("Export en cours")
                        .padding(.bottom, Theme.Spacing.m)
                }
                if let exportURL {
                    FlowDivider()
                    ShareLink(item: exportURL) {
                        actionLabel("Partager le fichier d'export", icon: .share)
                    }
                }
                Group {
                    FlowDivider()
                    logoutButton
                    FlowDivider()
                    deleteButton
                }
                if isDeleting {
                    ProgressView()
                        .tint(Theme.ink)
                        .accessibilityLabel("Suppression en cours")
                        .padding(.bottom, Theme.Spacing.m)
                }
            }
            if let accountMessage { FlowMessage(text: accountMessage, kind: .success) }
            if let accountError { FlowMessage(text: accountError, kind: .error) }
        }
    }

    private var nameRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            QFieldLabel("Prénom")
            TextField("Prénom", text: $nameDraft)
                .textContentType(.givenName)
                .submitLabel(.done)
                .onSubmit(saveName)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.primaryText)
                .padding(.horizontal, Theme.Spacing.m)
                .frame(minHeight: 48)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.background))
        }
        .padding(.vertical, Theme.Spacing.m)
    }

    private var logoutButton: some View {
        Button {
            showLogoutConfirm = true
        } label: {
            actionLabel("Se déconnecter", icon: .logout)
        }
        .buttonStyle(.press)
        .confirmationDialog("Te déconnecter ?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("Se déconnecter", role: .destructive, action: logout)
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les restrictions d'apps seront désactivées sur cet iPhone. Ta progression reste sur ton compte.")
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            actionLabel("Supprimer mon compte", icon: .trash, tint: Theme.error)
        }
        .buttonStyle(.press)
        .disabled(isDeleting)
        .confirmationDialog("Supprimer ton compte ?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Supprimer définitivement", role: .destructive, action: deleteAccount)
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Toutes tes données seront supprimées, sur nos serveurs et sur cet iPhone. Cette action est irréversible. Les restrictions d'apps seront désactivées.")
        }
    }

    private func saveName() {
        let current = env.settings.profile.displayName ?? ""
        guard nameDraft.trimmingCharacters(in: .whitespacesAndNewlines) != current else { return }
        env.settings.setDisplayName(nameDraft)
        env.sync.requestSync(.settings)
        Task { await env.study.refresh() }
    }

    private func exportData() {
        isExporting = true
        accountError = nil
        accountMessage = nil
        exportURL = nil
        Task {
            defer { isExporting = false }
            do {
                exportURL = try await env.auth.exportData()
                accountMessage = "Ton export est prêt."
            } catch let failure as AuthFailure {
                accountError = Self.text(of: failure)
            } catch {
                accountError = "L'export a échoué. Vérifie ta connexion et réessaie."
            }
        }
    }

    private func logout() {
        accountError = nil
        Task {
            let succeeded = await env.logout()
            if !succeeded {
                accountError = env.auth.errorMessage ?? "La déconnexion a échoué. Vérifie ta connexion et réessaie."
            }
        }
    }

    private func deleteAccount() {
        isDeleting = true
        accountError = nil
        Task {
            defer { isDeleting = false }
            do {
                try await env.deleteAccount()
            } catch let failure as AuthFailure {
                accountError = Self.text(of: failure)
            } catch {
                accountError = "La suppression a échoué. Vérifie ta connexion et réessaie."
            }
        }
    }

    private static func text(of failure: AuthFailure) -> String {
        switch failure {
        case .message(let text): return text
        case .offline: return "Pas de connexion Internet. Vérifie ton réseau et réessaie."
        case .notConfigured: return "L'application n'est pas configurée correctement."
        }
    }

    // MARK: About

    private var aboutSection: some View {
        SettingsSection("À propos") {
            NavigationLink {
                PrivacyPolicyView()
            } label: {
                linkLabel("Politique de confidentialité", icon: .shield)
            }
            .buttonStyle(.press)
            FlowDivider()
            NavigationLink {
                KnownLimitsView()
            } label: {
                linkLabel("Limites connues", icon: .info)
            }
            .buttonStyle(.press)
            FlowDivider()
            infoRow("Version", versionText)
        }
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        let content = env.content.activeVersion.map { " · contenu \($0)" } ?? ""
        return "\(version) (\(build))\(content)"
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

// MARK: - Section container

/// Section label (caption, semibold) above a white card (radius 22), optional footnote under it.
struct SettingsSection<Content: View>: View {
    let title: String
    let footer: String?
    let content: Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title)
                .font(Theme.Font.caption(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, Theme.Spacing.xs)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, Theme.Spacing.page)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                        .fill(Theme.surface)
                )
            if let footer {
                Text(footer)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
        }
    }
}

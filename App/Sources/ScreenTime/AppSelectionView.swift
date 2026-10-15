import SwiftUI
import FamilyControls
import UIKit

/// Explanation + Screen Time authorization + mode choice + `FamilyActivityPicker` + save.
/// Used by the onboarding (step 7) and by the settings, always inside a sheet.
///
/// Public contract (frozen): `AppSelectionView(onDone:)`.
struct AppSelectionView: View {
    let onDone: () -> Void

    @State private var draft = FamilyActivitySelection()
    @State private var draftMode: RestrictionMode = .selectedApps
    @State private var showPicker = false
    @State private var isSaving = false
    @State private var didLoad = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    init(onDone: @escaping () -> Void) {
        self.onDone = onDone
    }

    private var manager: RestrictionManager { RestrictionManager.shared }

    private var canSave: Bool {
        switch draftMode {
        case .selectedApps:
            return !draft.applicationTokens.isEmpty || !draft.categoryTokens.isEmpty || !draft.webDomainTokens.isEmpty
        case .allExceptAllowed:
            return !draft.applicationTokens.isEmpty
        }
    }

    var body: some View {
        FlowScreen {
            header
            explanation
            authorizationSection
            modeSection
            selectionSection
        } footer: {
            Button {
                Task { await save() }
            } label: {
                FlowButtonLabel(title: "Enregistrer", isWorking: isSaving)
            }
            .buttonStyle(.primary)
            .disabled(!canSave || isSaving)

            FlowLinkButton(title: "Pas maintenant") { onDone() }
        }
        .familyActivityPicker(isPresented: $showPicker, selection: $draft)
        .task {
            guard !didLoad else { return }
            didLoad = true
            manager.refreshAuthorization()
            draft = manager.selection
            draftMode = manager.mode
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { manager.refreshAuthorization() }
        }
        .tint(Theme.ink)
        // Sheet chrome: the content is made of white cards, so the sheet itself stays on the page background.
        .safeAreaInset(edge: .top, spacing: 0) {
            SheetHandle().frame(maxWidth: .infinity)
        }
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(Theme.Radius.large)
        .presentationBackground(Theme.background)
    }

    // MARK: Sections

    private var header: some View {
        FlowHeader(title: "Apps à mettre en pause",
                   subtitle: "À l'heure de chaque leçon, Quinze peut mettre en pause les apps qui te distraient, le temps de ta leçon de 5 minutes.",
                   display: false)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            infoRow(.lock,
                    "Les apps choisies sont restreintes jusqu'à ce que tu aies terminé la leçon du moment.")
            infoRow(.shield,
                    "Le téléphone, les appels d'urgence et les Réglages restent toujours disponibles, ainsi que Quinze.")
            infoRow(.unlock,
                    "Tu gardes la main : tu peux retirer l'autorisation à tout moment dans Réglages > Temps d'écran, et un déblocage d'urgence reste possible depuis l'écran de restriction.")
            infoRow(.eyeSlash,
                    "Ta sélection reste sur cet iPhone. Apple ne nous transmet jamais le nom de tes apps.")
        }
        .card()
    }

    /// Thin icon in a soft pastel circle + one sentence.
    private func infoRow(_ icon: QIcon, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            QIconView(icon: icon, size: 18)
                .foregroundStyle(Theme.ink)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Pastel.blue.soft))
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.Font.callout(.regular))
                .foregroundStyle(Theme.primaryText)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var authorizationSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.card) {
            switch manager.authorization {
            case .approved:
                QCallout(systemImage: "checkmark.circle", tint: Theme.ink, fill: Theme.greenSoft) {
                    Text("Temps d'écran est autorisé.")
                        .font(Theme.Font.callout(.semibold))
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .notDetermined:
                QCallout(systemImage: "lock", tint: Theme.ink, fill: Pastel.yellow.soft) {
                    calloutText("Pour restreindre des apps, iOS te demande une autorisation Temps d'écran.")
                }
                Button {
                    Task { _ = await manager.requestAuthorization() }
                } label: {
                    Text("Autoriser Temps d'écran")
                }
                .buttonStyle(.secondary)
            case .denied:
                QCallout(systemImage: "lock", tint: Theme.ink, fill: Pastel.yellow.soft) {
                    calloutText("L'autorisation a été refusée ou retirée. Tu peux la rétablir dans Réglages > Temps d'écran.")
                }
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text("Ouvrir les Réglages")
                }
                .buttonStyle(.secondary)
            case .unavailable:
                QCallout(systemImage: "info.circle", tint: Theme.ink, fill: Pastel.blue.soft) {
                    calloutText("Temps d'écran n'est pas disponible ici (simulateur, ou autorisation Apple pas encore accordée). Tu peux continuer : les leçons fonctionnent sans restriction.")
                }
            }
            if let message = manager.lastErrorMessage {
                FlowMessage(text: message, kind: .error)
            }
        }
    }

    private func calloutText(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.callout)
            .foregroundStyle(Theme.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Two big white rows, ink once selected (checkmark too).
    private var modeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.card) {
            QSectionTitle("Que faut-il restreindre ?")
            ForEach(RestrictionMode.allCases, id: \.self) { mode in
                FlowChoiceRow(title: mode.displayName, detail: detail(for: mode), isSelected: draftMode == mode) {
                    draftMode = mode
                }
            }
        }
    }

    private func detail(for mode: RestrictionMode) -> String {
        switch mode {
        case .selectedApps:
            return "Seules les apps, catégories et sites que tu choisis sont restreints. Le reste du téléphone reste libre."
        case .allExceptAllowed:
            return "Tout est restreint sauf les apps que tu autorises. Quinze doit en faire partie, sinon tu ne pourrais pas faire ta leçon. Apple ne permet pas d'autoriser une catégorie entière : choisis des apps."
        }
    }

    private var selectionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.card) {
            Button {
                showPicker = true
            } label: {
                Text(draftMode == .selectedApps ? "Choisir les apps à restreindre" : "Choisir les apps autorisées")
            }
            .buttonStyle(.secondary)

            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text(summary)
                    .font(Theme.Font.body(.semibold))
                    .foregroundStyle(canSave ? Theme.primaryText : Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(draft.applicationTokens.prefix(5)), id: \.self) { token in
                    Label(token)
                        .labelStyle(.titleAndIcon)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.primaryText)
                }
            }
            .card()

            if draftMode == .allExceptAllowed {
                QCallout(systemImage: "exclamationmark.circle", tint: Theme.ink, fill: Pastel.yellow.soft) {
                    Text("N'oublie pas d'autoriser Quinze dans la liste.")
                        .font(Theme.Font.callout(.semibold))
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var summary: String {
        let apps = draft.applicationTokens.count
        let categories = draft.categoryTokens.count
        let sites = draft.webDomainTokens.count
        if apps + categories + sites == 0 {
            return draftMode == .selectedApps ? "Aucune app choisie pour l'instant." : "Aucune app autorisée pour l'instant."
        }
        var parts: [String] = []
        if apps > 0 { parts.append(apps == 1 ? "1 app" : "\(apps) apps") }
        if categories > 0 && draftMode == .selectedApps { parts.append(categories == 1 ? "1 catégorie" : "\(categories) catégories") }
        if sites > 0 { parts.append(sites == 1 ? "1 site" : "\(sites) sites") }
        let list = parts.joined(separator: ", ")
        return draftMode == .selectedApps ? "Restreint : \(list)." : "Autorisées : \(list)."
    }

    // MARK: Actions

    private func save() async {
        isSaving = true
        if manager.authorization == .notDetermined {
            _ = await manager.requestAuthorization()
        }
        manager.updateSelection(draft, mode: draftMode)
        isSaving = false
        onDone()
    }
}

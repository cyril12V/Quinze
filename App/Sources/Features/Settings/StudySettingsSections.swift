import SwiftUI
import AVFoundation

// Settings added with the three subjects: which subjects, how long each, appearance, voices.

/// « Mes matières » : on/off and minutes per subject, in study order.
struct SubjectsSettingsSection: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        SettingsSection("Mes matières",
                        footer: "À chaque leçon, tu fais les matières l'une après l'autre. Le créneau est terminé, et tes apps débloquées, quand toutes sont faites. Si tu vas vite, la session continue avec des révisions jusqu'au temps choisi.") {
            ForEach(Array(env.settings.study.subjects.enumerated()), id: \.element.subject) { offset, preference in
                if offset > 0 { divider }
                subjectRow(preference)
            }
            divider
            totalRow
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.separator).frame(height: 1)
    }

    private func subjectRow(_ preference: SubjectPreference) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: enabledBinding(preference.subject)) {
                HStack(spacing: Theme.Spacing.s) {
                    Text(preference.subject.emoji)
                    Text(preference.subject.displayName)
                        .font(Theme.Font.body(.semibold))
                        .foregroundStyle(Theme.primaryText)
                }
            }
            .tint(Theme.ink)
            .disabled(!isAvailable(preference.subject))
            if preference.enabled {
                Stepper(value: minutesBinding(preference.subject), in: SubjectPreference.minuteRange) {
                    Text("\(preference.minutes) min par leçon")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            if !isAvailable(preference.subject) {
                Text("Contenu bientôt disponible.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(.vertical, Theme.Spacing.s)
    }

    private var totalRow: some View {
        let total = env.study.enabledSubjects.reduce(0) { $0 + env.settings.study.minutes(for: $1) }
        return LabeledContent {
            Text("\(total) min")
                .font(Theme.Font.body(.semibold))
                .foregroundStyle(Theme.primaryText)
        } label: {
            Text("Durée d'une leçon")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.primaryText)
        }
        .frame(minHeight: Theme.minTapSize + 8)
    }

    private func isAvailable(_ subject: Subject) -> Bool {
        env.stores[subject]?.engine != nil
    }

    private func enabledBinding(_ subject: Subject) -> Binding<Bool> {
        Binding(get: { env.settings.study.subjects.first { $0.subject == subject }?.enabled ?? false },
                set: { newValue in
                    env.settings.updateStudy { study in
                        guard let i = study.subjects.firstIndex(where: { $0.subject == subject }) else { return }
                        study.subjects[i].enabled = newValue
                        // Keep at least one subject.
                        if !study.subjects.contains(where: \.enabled) { study.subjects[i].enabled = true }
                    }
                    Task { await env.studyPreferencesDidChange() }
                })
    }

    private func minutesBinding(_ subject: Subject) -> Binding<Int> {
        Binding(get: { env.settings.study.minutes(for: subject) },
                set: { newValue in
                    env.settings.updateStudy { study in
                        guard let i = study.subjects.firstIndex(where: { $0.subject == subject }) else { return }
                        study.subjects[i].minutes = newValue
                    }
                    Task { await env.studyPreferencesDidChange() }
                })
    }
}

/// « Apparence » : clair (par défaut), sombre ou automatique.
struct AppearanceSettingsSection: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        SettingsSection("Apparence") {
            Picker("Thème", selection: appearanceBinding) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.vertical, Theme.Spacing.m)
        }
    }

    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(get: { env.settings.study.appearance },
                set: { newValue in env.settings.updateStudy { $0.appearance = newValue } })
    }
}

/// « Voix » : the voice used per language, the speech rate, and how to download nicer voices.
struct VoiceSettingsSection: View {
    @Environment(AppEnvironment.self) private var env

    private struct LanguageVoices: Identifiable {
        let id: String
        let title: String
        let sample: String
        let locale: String
    }

    private let languages: [LanguageVoices] = [
        LanguageVoices(id: "en", title: "Anglais", sample: "Hello! Let's learn some English today.", locale: "en-GB"),
        LanguageVoices(id: "ar", title: "Arabe", sample: "مَرْحَبًا، كَيْفَ حَالُكَ؟", locale: "ar-SA"),
        LanguageVoices(id: "fr", title: "Français (culture G)", sample: "Bonjour ! On révise un peu de culture générale ?", locale: "fr-FR"),
    ]

    var body: some View {
        SettingsSection("Voix",
                        footer: "Pour une voix bien plus naturelle, télécharge une voix « Premium » ou « Améliorée » dans Réglages > Accessibilité > Contenu énoncé > Voix (anglais, arabe, français), puis choisis-la ici. Sans choix, Quinze prend la meilleure voix installée.") {
            ForEach(Array(languages.enumerated()), id: \.element.id) { offset, language in
                if offset > 0 { Rectangle().fill(Theme.separator).frame(height: 1) }
                voiceRow(language)
            }
            Rectangle().fill(Theme.separator).frame(height: 1)
            rateRow
        }
    }

    private func voiceRow(_ language: LanguageVoices) -> some View {
        let voices = SpeechService.voices(language: language.id)
        return HStack(spacing: Theme.Spacing.s) {
            Picker(selection: voiceBinding(language.id)) {
                Text("Automatique").tag("")
                ForEach(voices, id: \.identifier) { voice in
                    Text("\(voice.name) · \(SpeechService.qualityLabel(voice))").tag(voice.identifier)
                }
            } label: {
                Text(language.title)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.primaryText)
            }
            .pickerStyle(.menu)
            Button {
                env.speech.speak(language.sample, locale: language.locale)
            } label: {
                QIconView(icon: .speaker, size: 18)
                    .foregroundStyle(Theme.ink)
                    .frame(width: Theme.minTapSize, height: Theme.minTapSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Écouter la voix \(language.title.lowercased())")
        }
        .frame(minHeight: Theme.minTapSize + 8)
    }

    private var rateRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Vitesse de lecture")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.primaryText)
            Slider(value: rateBinding, in: 0.3...0.6) {
                Text("Vitesse de lecture")
            } minimumValueLabel: {
                Text("Lent").font(Theme.Font.caption).foregroundStyle(Theme.secondaryText)
            } maximumValueLabel: {
                Text("Rapide").font(Theme.Font.caption).foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.vertical, Theme.Spacing.s)
    }

    private func voiceBinding(_ language: String) -> Binding<String> {
        Binding(get: { env.settings.study.voiceIdentifiers[language] ?? "" },
                set: { newValue in
                    env.settings.updateStudy { $0.voiceIdentifiers[language] = newValue.isEmpty ? nil : newValue }
                    env.applySpeechPreferences()
                })
    }

    private var rateBinding: Binding<Double> {
        Binding(get: { env.settings.study.speechRate },
                set: { newValue in
                    env.settings.updateStudy { $0.speechRate = newValue }
                    env.applySpeechPreferences()
                })
    }
}

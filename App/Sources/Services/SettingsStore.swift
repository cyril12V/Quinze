import Foundation
import Observation
import LearningCore

/// Daily schedule + notification preferences, with the dirty flags used by the sync.
struct SettingsRecord: Codable, Equatable, Sendable {
    var schedule: DailySchedule
    var notifications: NotificationPreferences
    var scheduleUpdatedAt: Date
    var notificationsUpdatedAt: Date
    var scheduleDirty: Bool
    var notificationsDirty: Bool

    static func makeDefault(now: Date = .now) -> SettingsRecord {
        SettingsRecord(schedule: .default, notifications: .default, scheduleUpdatedAt: now,
                       notificationsUpdatedAt: now, scheduleDirty: false, notificationsDirty: false)
    }
}

/// Light / dark appearance chosen in the settings.
enum AppearanceMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case light, dark, system

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .light: return "Clair"
        case .dark: return "Sombre"
        case .system: return "Automatique"
        }
    }
}

/// One subject in the daily sessions.
struct SubjectPreference: Codable, Equatable, Sendable, Identifiable {
    var subject: Subject
    var enabled: Bool
    /// Target length of the subject's part of a session.
    var minutes: Int

    var id: Subject { subject }
    static let minuteRange = 2...20
}

/// What the learner studies and how the app looks and sounds (local only, not synced).
struct StudyPreferences: Codable, Equatable, Sendable {
    var subjects: [SubjectPreference]
    var appearance: AppearanceMode
    /// AVSpeechSynthesisVoice identifier chosen per language ("en", "ar", "fr").
    var voiceIdentifiers: [String: String]
    /// AVSpeechUtterance rate (0...1, 0.5 = normal).
    var speechRate: Double

    static let `default` = StudyPreferences(
        subjects: Subject.studyOrder.map { SubjectPreference(subject: $0, enabled: true, minutes: 5) },
        appearance: .light, voiceIdentifiers: [:], speechRate: 0.46)

    /// Subjects of a session, in study order (English is always kept as a fallback).
    var enabledSubjects: [Subject] {
        let list = subjects.filter(\.enabled).map(\.subject)
        return list.isEmpty ? [.english] : list
    }

    func minutes(for subject: Subject) -> Int {
        subjects.first { $0.subject == subject }?.minutes ?? 5
    }

    init(subjects: [SubjectPreference], appearance: AppearanceMode, voiceIdentifiers: [String: String], speechRate: Double) {
        self.subjects = subjects
        self.appearance = appearance
        self.voiceIdentifiers = voiceIdentifiers
        self.speechRate = speechRate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StudyPreferences.default
        var subjects = (try? c.decodeIfPresent([SubjectPreference].self, forKey: .subjects)) ?? d.subjects
        // A subject added in a later version appears enabled, at the end.
        for missing in Subject.studyOrder where !subjects.contains(where: { $0.subject == missing }) {
            subjects.append(SubjectPreference(subject: missing, enabled: true, minutes: 5))
        }
        self.subjects = subjects
        appearance = (try? c.decodeIfPresent(AppearanceMode.self, forKey: .appearance)) ?? d.appearance
        voiceIdentifiers = (try? c.decodeIfPresent([String: String].self, forKey: .voiceIdentifiers)) ?? d.voiceIdentifiers
        speechRate = (try? c.decodeIfPresent(Double.self, forKey: .speechRate)) ?? d.speechRate
    }
}

/// Profile (placement, onboarding progress, name) and settings, persisted locally and synced.
@MainActor
@Observable
final class SettingsStore {
    private(set) var schedule: DailySchedule
    private(set) var notificationPreferences: NotificationPreferences
    private(set) var profile: UserProfileRecord
    private(set) var record: SettingsRecord
    private(set) var study: StudyPreferences

    private let local: LocalStore
    private static let profileKey = "profile"
    private static let settingsKey = "settings"
    private static let studyKey = "study"

    init(local: LocalStore) {
        self.local = local
        let rec = local.value(SettingsRecord.self, for: Self.settingsKey) ?? SettingsRecord.makeDefault()
        let prof = local.value(UserProfileRecord.self, for: Self.profileKey) ?? UserProfileRecord.empty
        record = rec
        schedule = rec.schedule
        notificationPreferences = rec.notifications
        profile = prof
        study = local.value(StudyPreferences.self, for: Self.studyKey) ?? .default
    }

    func updateStudy(_ change: (inout StudyPreferences) -> Void) {
        var s = study
        change(&s)
        for i in s.subjects.indices {
            s.subjects[i].minutes = min(max(s.subjects[i].minutes, SubjectPreference.minuteRange.lowerBound),
                                        SubjectPreference.minuteRange.upperBound)
        }
        guard s != study else { return }
        study = s
        local.setValue(s, for: Self.studyKey)
    }

    /// Re-reads storage (after a wipe or a server restore).
    func reload() {
        let rec = local.value(SettingsRecord.self, for: Self.settingsKey) ?? SettingsRecord.makeDefault()
        record = rec
        schedule = rec.schedule
        notificationPreferences = rec.notifications
        profile = local.value(UserProfileRecord.self, for: Self.profileKey) ?? UserProfileRecord.empty
        study = local.value(StudyPreferences.self, for: Self.studyKey) ?? .default
    }

    // MARK: Profile

    func updateProfile(_ change: (inout UserProfileRecord) -> Void) {
        var p = profile
        change(&p)
        guard p != profile else { return }
        profile = p
        local.setValue(p, for: Self.profileKey)
    }

    func setDisplayName(_ name: String?, now: Date = .now) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (trimmed?.isEmpty ?? true) ? nil : trimmed
        updateProfile {
            $0.displayName = value
            $0.profileDirty = true
        }
    }

    /// Stores the diagnostic outcome (or the self-assessment when the test is skipped).
    func recordPlacement(_ result: DiagnosticResult?, selfAssessed: SelfAssessedLevel, startLessonSequence: Int?,
                         languageId: String, now: Date = .now) {
        updateProfile {
            $0.languageId = languageId
            $0.selfAssessedLevel = selfAssessed.rawValue
            $0.placement = result
            $0.estimatedLevel = result?.estimatedLevel ?? selfAssessed.rawValue
            $0.startLessonSequence = startLessonSequence
            $0.startedAt = $0.startedAt ?? now
            $0.userLanguageUpdatedAt = now
            $0.userLanguageDirty = true
        }
    }

    // MARK: Schedule & notifications

    /// Validates and saves. Returns the validation issues (nothing is saved when there are some).
    @discardableResult
    func updateSchedule(_ new: DailySchedule, now: Date = .now) -> [DailySchedule.Issue] {
        let issues = new.validate()
        guard issues.isEmpty else { return issues }
        guard new != schedule else { return [] }
        var rec = record
        rec.schedule = new
        rec.scheduleUpdatedAt = now
        rec.scheduleDirty = true
        persist(rec)
        return []
    }

    /// Marks the current schedule as to be pushed even if unchanged (first save at the end of the onboarding).
    func markScheduleForSync(now: Date = .now) {
        var rec = record
        rec.scheduleUpdatedAt = now
        rec.scheduleDirty = true
        persist(rec)
        updateProfile { $0.profileDirty = true }
    }

    func updateNotificationPreferences(_ new: NotificationPreferences, now: Date = .now) {
        guard new != notificationPreferences else { return }
        var rec = record
        rec.notifications = new
        rec.notificationsUpdatedAt = now
        rec.notificationsDirty = true
        persist(rec)
        updateProfile { $0.profileDirty = true }
    }

    /// Server values win only when strictly newer than the local ones.
    @discardableResult
    func applyRemoteSchedule(_ remote: DailySchedule, updatedAt: Date) -> Bool {
        guard updatedAt > record.scheduleUpdatedAt || isPristine else { return false }
        var rec = record
        rec.schedule = remote
        rec.scheduleUpdatedAt = updatedAt
        rec.scheduleDirty = false
        persist(rec)
        return true
    }

    func applyRemoteNotificationPreferences(_ remote: NotificationPreferences) {
        guard !record.notificationsDirty, remote != notificationPreferences else { return }
        var rec = record
        rec.notifications = remote
        rec.notificationsDirty = false
        persist(rec)
    }

    func markScheduleClean(updatedAt: Date) {
        guard record.scheduleDirty, record.scheduleUpdatedAt == updatedAt else { return }
        var rec = record
        rec.scheduleDirty = false
        persist(rec)
    }

    func markNotificationsAndProfileClean(notificationsUpdatedAt: Date) {
        var rec = record
        if rec.notificationsDirty, rec.notificationsUpdatedAt == notificationsUpdatedAt {
            rec.notificationsDirty = false
            persist(rec)
        }
        updateProfile { $0.profileDirty = false }
    }

    /// True while the schedule was never edited (still the factory default).
    private var isPristine: Bool { !record.scheduleDirty && record.schedule == .default }

    private func persist(_ rec: SettingsRecord) {
        record = rec
        schedule = rec.schedule
        notificationPreferences = rec.notifications
        local.setValue(rec, for: Self.settingsKey)
    }
}

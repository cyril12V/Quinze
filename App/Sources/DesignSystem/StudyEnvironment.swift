import SwiftUI

// Environment values set by a subject's screens (lesson, dictionary) for the components inside them.

private struct SpeechEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

private struct StudySubjectCodeKey: EnvironmentKey {
    static let defaultValue = "en"
}

extension EnvironmentValues {
    /// False in Culture G: there is nothing to listen to, the speaker buttons disappear.
    var speechEnabled: Bool {
        get { self[SpeechEnabledKey.self] }
        set { self[SpeechEnabledKey.self] = newValue }
    }

    /// Code of the subject being studied on screen ("en", "ar", "cg").
    var studySubjectCode: String {
        get { self[StudySubjectCodeKey.self] }
        set { self[StudySubjectCodeKey.self] = newValue }
    }
}

extension View {
    /// Environment of a subject's screens: its code, and no audio for Culture G.
    func studySubject(_ subject: Subject) -> some View {
        environment(\.studySubjectCode, subject.rawValue)
            .environment(\.speechEnabled, subject != .culture)
    }
}

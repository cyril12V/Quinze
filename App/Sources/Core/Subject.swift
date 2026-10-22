import Foundation
import LearningCore

/// The three things Quinze teaches. Each subject has its own content bundle (`Content/<code>.json`),
/// its own engine and its own learner state; every identifier of its content starts with `<code>.`.
enum Subject: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case english = "en"
    case arabic = "ar"
    case culture = "cg"

    var id: String { rawValue }
    var code: String { rawValue }

    /// "Anglais"
    var displayName: String {
        switch self {
        case .english: return "Anglais"
        case .arabic: return "Arabe"
        case .culture: return "Culture G"
        }
    }

    /// Short label for chips and tabs.
    var shortName: String {
        switch self {
        case .english: return "Anglais"
        case .arabic: return "Arabe"
        case .culture: return "Culture"
        }
    }

    var emoji: String {
        switch self {
        case .english: return "🇬🇧"
        case .arabic: return "🇪🇬"
        case .culture: return "🌍"
        }
    }

    /// SF Symbol shown next to the subject.
    var symbol: String {
        switch self {
        case .english: return "textformat.abc"
        case .arabic: return "character.book.closed"
        case .culture: return "globe.europe.africa"
        }
    }

    /// Text of the studied subject is written right to left.
    var isRightToLeft: Bool { self == .arabic }

    /// The subject owns an identifier of its content (unit, lesson, exercise, dictionary item).
    func owns(_ identifier: String) -> Bool { identifier.hasPrefix(rawValue + ".") }

    /// Subject of a content identifier ("ar.l03.e05" → .arabic). Unprefixed ids are English (v1 data).
    static func of(_ identifier: String) -> Subject {
        allCases.first { $0.owns(identifier) } ?? .english
    }

    /// Order in which a slot session goes through the subjects.
    static let studyOrder: [Subject] = [.english, .arabic, .culture]
}

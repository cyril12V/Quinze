import Foundation
import LearningCore

/// The things the apps teach. Each subject has its own content bundle (`Content/<code>.json`), its own engine and
/// its own learner state; every identifier of its content starts with `<code>.`. Quinze studies the first three
/// in its daily slots; `.church` is the single subject of the separate Nofri app (built with the NOFRI condition).
enum Subject: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case english = "en"
    case arabic = "ar"
    case culture = "cg"
    case church = "eg"

    var id: String { rawValue }
    var code: String { rawValue }

    /// "Anglais"
    var displayName: String {
        switch self {
        case .english: return "Anglais"
        case .arabic: return "Arabe"
        case .culture: return "Culture G"
        case .church: return "Église copte"
        }
    }

    /// Short label for chips and tabs.
    var shortName: String {
        switch self {
        case .english: return "Anglais"
        case .arabic: return "Arabe"
        case .culture: return "Culture"
        case .church: return "Église"
        }
    }

    var emoji: String {
        switch self {
        case .english: return "🇬🇧"
        case .arabic: return "🇪🇬"
        case .culture: return "🌍"
        case .church: return "⛪"
        }
    }

    /// SF Symbol shown next to the subject.
    var symbol: String {
        switch self {
        case .english: return "textformat.abc"
        case .arabic: return "character.book.closed"
        case .culture: return "globe.europe.africa"
        case .church: return "building.columns"
        }
    }

    /// Text of the studied subject is written right to left.
    var isRightToLeft: Bool { self == .arabic }

    /// Taught in French: a word's meaning is a definition, not a translation.
    var isTaughtInFrench: Bool { self == .culture || self == .church }

    /// The subject owns an identifier of its content (unit, lesson, exercise, dictionary item).
    func owns(_ identifier: String) -> Bool { identifier.hasPrefix(rawValue + ".") }

    /// Subject of a content identifier ("ar.l03.e05" → .arabic). Unprefixed ids are English (v1 data).
    static func of(_ identifier: String) -> Subject {
        allCases.first { $0.owns(identifier) } ?? .primary
    }

    #if NOFRI
    /// Nofri teaches one thing: the Church.
    static let studyOrder: [Subject] = [.church]
    static let primary: Subject = .church
    #else
    /// Order in which a slot session goes through the subjects.
    static let studyOrder: [Subject] = [.english, .arabic, .culture]
    /// The subject every install has (fallback of the per-subject lookups).
    static let primary: Subject = .english
    #endif
}

import Foundation
import LearningCore

/// Points and titles of Nofri. Everything is computed from the sessions already saved: nothing to keep in sync.
struct NofriRank: Equatable, Sendable {
    let title: String
    let emoji: String
    let minPoints: Int
}

enum NofriGame {
    /// The ladder: a lesson is worth about 200 points, an exam 200 more.
    static let ranks: [NofriRank] = [
        NofriRank(title: "Catéchumène", emoji: "🌱", minPoints: 0),
        NofriRank(title: "Fidèle", emoji: "🕯️", minPoints: 400),
        NofriRank(title: "Psalte", emoji: "🎶", minPoints: 1_200),
        NofriRank(title: "Lecteur", emoji: "📖", minPoints: 2_500),
        NofriRank(title: "Sous-diacre", emoji: "🚪", minPoints: 5_000),
        NofriRank(title: "Diacre", emoji: "🔔", minPoints: 9_000),
        NofriRank(title: "Archidiacre", emoji: "⭐", minPoints: 15_000),
        NofriRank(title: "Catéchiste", emoji: "🧭", minPoints: 24_000),
        NofriRank(title: "Théologien", emoji: "🦅", minPoints: 36_000),
        NofriRank(title: "Colonne de la foi", emoji: "🏛️", minPoints: 50_000)
    ]

    static let pointsPerCorrectAnswer = 10
    static let lessonBonus = 40
    static let flawlessBonus = 30
    static let examBonus = 200
    static let challengeBonus = 50

    /// Points of one session.
    static func points(correct: Int, total: Int, lessonPassed: Bool?, examPassed: Bool?) -> Int {
        var p = correct * pointsPerCorrectAnswer
        if lessonPassed == true { p += lessonBonus }
        if examPassed == true { p += examBonus }
        if total >= 5 && correct == total { p += flawlessBonus }
        return p
    }

    static func points(sessions: [SessionRecord], challengeDays: Int) -> Int {
        let fromSessions = sessions.filter { $0.status == .completed && $0.subjectCode == Subject.church.code }
            .reduce(0) { $0 + points(correct: $1.correctCount, total: $1.itemCount, lessonPassed: $1.lessonPassed, examPassed: $1.examPassed) }
        return fromSessions + challengeDays * challengeBonus
    }

    static func rank(points: Int) -> NofriRank {
        ranks.last { points >= $0.minPoints } ?? ranks[0]
    }

    static func nextRank(points: Int) -> NofriRank? {
        ranks.first { points < $0.minPoints }
    }

    /// 0...1 towards the next title.
    static func progress(points: Int) -> Double {
        let current = rank(points: points)
        guard let next = nextRank(points: points) else { return 1 }
        let span = Double(next.minPoints - current.minPoints)
        return span > 0 ? min(1, max(0, Double(points - current.minPoints) / span)) : 1
    }
}

/// Families of the collection, in display order.
enum NofriCollection: String, CaseIterable, Identifiable, Sendable {
    case saint, pere, pape, concile, heresie, lieu, eglise, notion, priere, objet, livre, date, copte

    var id: String { rawValue }

    var title: String {
        switch self {
        case .saint: return "Saints et martyrs"
        case .pere: return "Pères de l'Église"
        case .pape: return "Papes et patriarches"
        case .concile: return "Conciles"
        case .heresie: return "Hérésies"
        case .lieu: return "Lieux"
        case .eglise: return "Églises"
        case .notion: return "Notions"
        case .priere: return "Prière et louange"
        case .objet: return "Objets et bâtiment"
        case .livre: return "Livres"
        case .date: return "Événements"
        case .copte: return "Mots coptes"
        }
    }

    var emoji: String {
        switch self {
        case .saint: return "🕊️"
        case .pere: return "✍️"
        case .pape: return "🗝️"
        case .concile: return "🏛️"
        case .heresie: return "⚡"
        case .lieu: return "📍"
        case .eglise: return "⛪"
        case .notion: return "💡"
        case .priere: return "🙏"
        case .objet: return "🏺"
        case .livre: return "📜"
        case .date: return "🗓️"
        case .copte: return "ⲁ"
        }
    }

    var pastel: Pastel {
        switch self {
        case .saint, .priere, .livre: return .yellow
        case .pere, .notion, .date: return .blue
        case .pape, .heresie, .copte: return .pink
        case .concile, .lieu, .eglise, .objet: return .green
        }
    }
}

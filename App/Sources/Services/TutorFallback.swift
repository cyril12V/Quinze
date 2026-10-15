import Foundation
import LearningCore

/// Offline / unavailable / quota-exhausted answers, built only from the validated local content:
/// exercise explanation, tip and extra example, grammar rule, dictionary entry.
enum TutorFallback {
    enum Cause: Equatable, Sendable {
        case offline
        case unavailable
        case quotaReached
    }

    static func reply(for subject: TutorSubject, detail: TutorDetail, engine: LearningEngine?, cause: Cause,
                      question: String? = nil, history: [TutorMessage] = []) -> TutorReply {
        let source: TutorReplySource = cause == .offline ? .offline : .fallback
        var body = content(for: subject, detail: detail, engine: engine)

        if let question, wantsAnotherExample(question) {
            let seen = history.filter { $0.role == .tutor }.map(\.text).joined(separator: " ")
            if let fresh = body.examples.first(where: { !seen.contains($0.text) }) {
                return TutorReply(text: preface(for: cause, isFollowUp: true) + "Voici un exemple de plus :",
                                  examples: [fresh], source: source, remainingQuota: cause == .quotaReached ? 0 : nil)
            }
        }
        if question != nil, cause != .quotaReached {
            body.text = "Je ne peux pas répondre à une nouvelle question pour le moment. Voici ce que j'ai sous la main :\n\n" + body.text
        } else {
            body.text = preface(for: cause, isFollowUp: question != nil) + body.text
        }
        return TutorReply(text: body.text, examples: body.examples, source: source,
                          remainingQuota: cause == .quotaReached ? 0 : nil)
    }

    private static func preface(for cause: Cause, isFollowUp: Bool) -> String {
        switch cause {
        case .quotaReached:
            return "Tu as atteint ton quota d'explications par l'IA pour aujourd'hui (quota atteint). Il se renouvelle dans la journée. En attendant, voici l'essentiel :\n\n"
        case .offline:
            return "Tu es hors connexion : voici l'explication enregistrée dans l'application.\n\n"
        case .unavailable:
            return "Le professeur IA n'est pas disponible pour l'instant. Voici l'explication enregistrée dans l'application.\n\n"
        }
    }

    private static func wantsAnotherExample(_ question: String) -> Bool {
        question.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "fr_FR")).contains("exemple")
    }

    private static func content(for subject: TutorSubject, detail: TutorDetail, engine: LearningEngine?) -> (text: String, examples: [Example]) {
        let detailed = detail == .detailed
        guard let engine else {
            return ("Le contenu de la leçon n'est pas encore chargé. Réessaie dans un instant.", [])
        }
        switch subject {
        case .answer(let exerciseId, _):
            guard let exercise = engine.exercise(exerciseId) else { return generic() }
            var parts = ["Réponse attendue : \(exercise.answer)", exercise.explanation]
            var examples: [Example] = []
            if let tip = exercise.tip { parts.append("Astuce : \(tip)") }
            if let extra = exercise.extraExample { examples.append(extra) }
            if detailed, let unit = engine.unit(exercise.primaryUnitId), let rule = unit.rule {
                parts.append("La règle : \(rule.summary)\n\(rule.explanation)")
                if let pattern = rule.pattern { parts.append("Structure : \(pattern)") }
                examples.append(contentsOf: rule.examples.prefix(3))
            }
            return (parts.joined(separator: "\n\n"), dedupe(examples))

        case .rule(let unitId):
            return ruleContent(unitId: unitId, engine: engine, detailed: detailed)

        case .word(let word, _):
            guard let item = engine.lookup(word) else {
                return ("Je n'ai pas « \(word) » dans le dictionnaire de l'application. Réessaie avec une connexion pour une explication détaillée.", [])
            }
            var parts = ["« \(item.word) » (\(item.partOfSpeech)) : \(item.translation)", item.explanation]
            if detailed {
                if let others = item.otherTranslations, !others.isEmpty {
                    parts.append("Autres sens : \(others.joined(separator: ", ")).")
                }
                if let confusions = item.confusions, !confusions.isEmpty {
                    parts.append("À ne pas confondre : " + confusions.map { "\($0.word) (\($0.note))" }.joined(separator: " ; "))
                }
            }
            return (parts.joined(separator: "\n\n"), Array(item.examples.prefix(detailed ? 4 : 2)))

        case .example(_, let unitId):
            if let unitId {
                var result = ruleContent(unitId: unitId, engine: engine, detailed: detailed)
                result.text = "Cette phrase illustre la notion suivante.\n\n" + result.text
                return result
            }
            return generic()
        }
    }

    private static func ruleContent(unitId: String, engine: LearningEngine, detailed: Bool) -> (text: String, examples: [Example]) {
        guard let unit = engine.unit(unitId) else { return generic() }
        guard let rule = unit.rule else {
            var text = "« \(unit.title) »"
            if let translation = unit.translation { text += " signifie « \(translation) »" }
            return (text + ".", [])
        }
        var parts = [rule.summary, rule.explanation]
        if let pattern = rule.pattern { parts.append("Structure : \(pattern)") }
        if let tip = rule.tip { parts.append("Astuce : \(tip)") }
        if detailed {
            for error in rule.commonErrors.prefix(3) {
                parts.append("Erreur fréquente : « \(error.wrong) » → « \(error.right) ». \(error.why)")
            }
        }
        return (parts.joined(separator: "\n\n"), Array(rule.examples.prefix(detailed ? 4 : 2)))
    }

    private static func generic() -> (text: String, examples: [Example]) {
        ("Je n'ai pas d'explication enregistrée pour cet élément. Réessaie avec une connexion pour interroger le professeur IA.", [])
    }

    private static func dedupe(_ examples: [Example]) -> [Example] {
        var seen = Set<String>()
        return examples.filter { seen.insert($0.text).inserted }
    }
}

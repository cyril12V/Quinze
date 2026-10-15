import Foundation

/// FSRS-4.5 formulas (docs/05-moteur-pedagogique.md, "Répétition espacée").
struct FSRS: Sendable {
    static let decay = -0.5
    static let factor = 19.0 / 81.0

    let w: [Double]
    let desiredRetention: Double
    let maximumIntervalDays: Double

    init(configuration: EngineConfiguration) {
        w = configuration.fsrsWeights.count >= 17 ? configuration.fsrsWeights : EngineConfiguration.default.fsrsWeights
        desiredRetention = min(max(configuration.desiredRetention, 0.5), 0.99)
        maximumIntervalDays = configuration.maximumIntervalDays
    }

    /// Probability of recall after `elapsedDays` for a memory of stability `stability`.
    func retrievability(elapsedDays: Double, stability: Double) -> Double {
        let t = max(elapsedDays, 0)
        let s = max(stability, 0.01)
        return pow(1 + Self.factor * t / s, Self.decay)
    }

    /// Interval (days) after which the retrievability falls to `desiredRetention`, capped to the maximum.
    func interval(stability: Double) -> Double {
        let i = stability / Self.factor * (pow(desiredRetention, 1 / Self.decay) - 1)
        return min(max(i, 0), maximumIntervalDays)
    }

    func initialStability(_ g: ReviewGrade) -> Double { max(w[g.rawValue - 1], 0.1) }

    func initialDifficulty(_ g: ReviewGrade) -> Double {
        clampDifficulty(w[4] - Double(g.rawValue - 3) * w[5])
    }

    func nextDifficulty(_ d: Double, _ g: ReviewGrade) -> Double {
        let d0 = initialDifficulty(.good)
        return clampDifficulty(w[7] * d0 + (1 - w[7]) * (d - w[6] * Double(g.rawValue - 3)))
    }

    func successStability(d: Double, s: Double, r: Double, grade: ReviewGrade) -> Double {
        let hard = grade == .hard ? w[15] : 1
        let easy = grade == .easy ? w[16] : 1
        let growth = exp(w[8]) * (11 - d) * pow(s, -w[9]) * (exp(w[10] * (1 - r)) - 1) * hard * easy
        return s * (growth + 1)
    }

    func failureStability(d: Double, s: Double, r: Double) -> Double {
        let sf = w[11] * pow(d, -w[12]) * (pow(s + 1, w[13]) - 1) * exp(w[14] * (1 - r))
        return max(0.1, min(s, sf))
    }

    private func clampDifficulty(_ d: Double) -> Double { min(max(d, 1), 10) }
}

import Foundation

/// Seeded, platform-independent pseudo random generator (SplitMix64). Every random choice of the
/// engine goes through it so that plans are reproducible for a given seed.
struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func nextDouble() -> Double {
        Double(next() >> 11) / 9_007_199_254_740_992.0
    }

    /// Uniform in 0..<upper (0 when upper <= 1).
    mutating func nextInt(_ upper: Int) -> Int {
        upper <= 1 ? 0 : Int(next() % UInt64(upper))
    }

    /// Deterministic UUID (so that two plans built from the same seed are strictly equal).
    mutating func nextUUID() -> UUID {
        let a = next(), b = next()
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8(truncatingIfNeeded: a >> (UInt64(i) * 8))
            bytes[8 + i] = UInt8(truncatingIfNeeded: b >> (UInt64(i) * 8))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

/// FNV-1a 64 bits. `String.hashValue` is randomized per process, so it must never be used for seeding.
func stableHash(_ string: String) -> UInt64 {
    var h: UInt64 = 0xCBF2_9CE4_8422_2325
    for byte in string.utf8 {
        h ^= UInt64(byte)
        h = h &* 0x0000_0100_0000_01B3
    }
    return h
}

/// Constants shared by the planner, the updater and the simulation. They are documented in
/// docs/05-moteur-pedagogique.md ("Paramètres de réglage").
enum EngineTuning {
    /// Window used for the recent success rate (adaptation §13.1).
    static let performanceWindow = 30
    static let performanceMinimumAttempts = 8
    static let highPerformance = 0.85
    static let lowPerformance = 0.60
    /// Window used for the error categories (gap analysis §13.2).
    static let errorWindow = 100
    static let weakCategoryRate = 0.10
    static let weakCategoryMinimumErrors = 3
    /// Skill weights of the stability increase.
    static let recognitionWeight = 0.5
    static let recallWeight = 0.8
    static let productionWeight = 1.0
    /// Two reviews closer than this do not increase stability.
    static let rapidRepetitionMinutes = 10.0
    static let minIntervalAfterFailureHours = 4.0
    static let minIntervalAfterSuccessHours = 12.0
    /// A review is "late" (counts for the new-material pause) when it has been due for longer than this.
    static let overdueGraceHours = 12.0
    static let recentDays = 3
    static let retrievabilityForMastered = 0.8
    /// Diagnostic placement: stability / difficulty of presumed-known units, maximum checks per day.
    static let placementStability = 2.0
    static let placementDifficulty = 5.0
    static let placementChecksPerDay = 15
    /// Dictionary words.
    static let dictionaryStability = 0.5
    static let dictionaryFirstReviewHours = 4.0
}

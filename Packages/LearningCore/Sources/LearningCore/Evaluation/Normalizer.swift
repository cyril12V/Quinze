import Foundation

/// Text normalization and canonicalization (docs/05-moteur-pedagogique.md, "Normalisation").
///
/// `normalize` implements steps 1-3 (NFC, lowercase, apostrophes, quotes, punctuation, spaces).
/// `canonicalVariants` adds, for English, the contraction expansion (as a set of variants), digits 0-20
/// to words, British/American spelling and hyphen variants. Everything is locale independent.
public enum TextNormalizer {
    // MARK: Steps 1-3

    /// Normalized tokens (lowercase, no punctuation).
    public static func tokens(_ text: String) -> [String] {
        let s = text.precomposedStringWithCanonicalMapping.lowercased()
        var buffer = String()
        buffer.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "\u{2019}", "\u{2018}", "\u{201B}", "\u{00B4}", "`", "\u{02BC}":
                buffer.append("'")
            case "\u{201C}", "\u{201D}", "\u{201E}", "\u{00AB}", "\u{00BB}", "\"":
                buffer.append(" ")
            case ",", ";", ":", "(", ")", "[", "]", "{", "}", "\u{2013}", "\u{2014}", "\u{2015}":
                buffer.append(" ")
            default:
                buffer.append(ch)
            }
        }
        var out: [String] = []
        for piece in buffer.split(whereSeparator: { $0.isWhitespace }) {
            let t = trimEdges(String(piece))
            if !t.isEmpty && t != "-" { out.append(t) }
        }
        return out
    }

    public static func normalize(_ text: String) -> String {
        tokens(text).joined(separator: " ")
    }

    private static let edgePunctuation: Set<Character> = [".", "!", "?", "\u{2026}", "\u{00BF}", "\u{00A1}"]

    private static func trimEdges(_ token: String) -> String {
        var chars = Array(token)
        var changed = true
        while changed && !chars.isEmpty {
            changed = false
            if let f = chars.first, edgePunctuation.contains(f) || f == "'" { chars.removeFirst(); changed = true; continue }
            if let l = chars.last, edgePunctuation.contains(l) { chars.removeLast(); changed = true; continue }
            if let l = chars.last, l == "'", chars.count >= 2, chars[chars.count - 2] != "s" { chars.removeLast(); changed = true }
        }
        return String(chars)
    }

    /// Diacritic-insensitive form ("été" -> "ete").
    public static func foldAccents(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: nil)
    }

    // MARK: Canonical variants

    private static let variantCap = 32

    /// All canonical forms of a text, each one a token array. The first variant is the "primary" one.
    /// - english: apply the English rules (contractions, digits, spelling). French answers only get steps 1-3
    ///   plus hyphen variants.
    /// - lenient: also accept apostrophe-less contractions ("dont", "im"). Used as a second, "typo" level.
    public static func canonicalVariants(_ text: String, english: Bool = true, lenient: Bool = false) -> [[String]] {
        var variants: [[String]] = [[]]
        for tok in tokens(text) {
            let alts = tokenAlternatives(tok, english: english, lenient: lenient)
            var next: [[String]] = []
            var seen = Set<String>()
            outer: for v in variants {
                for a in alts {
                    let combined = v + a
                    if seen.insert(combined.joined(separator: " ")).inserted {
                        next.append(combined)
                        if next.count >= variantCap { break outer }
                    }
                }
            }
            variants = next
        }
        return variants
    }

    /// Primary canonical form as a string.
    public static func canonicalForm(_ text: String, english: Bool = true) -> String {
        (canonicalVariants(text, english: english).first ?? []).joined(separator: " ")
    }

    /// Canonical forms as strings (deduplicated, primary first).
    public static func canonicalStrings(_ text: String, english: Bool = true, lenient: Bool = false) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for v in canonicalVariants(text, english: english, lenient: lenient) {
            let s = v.joined(separator: " ")
            if seen.insert(s).inserted { out.append(s) }
        }
        return out
    }

    /// True when `needle` appears as a contiguous whole-word sequence in `haystack`.
    static func containsSequence(_ haystack: [String], _ needle: [String]) -> Bool {
        if needle.isEmpty { return true }
        if needle.count > haystack.count { return false }
        for start in 0...(haystack.count - needle.count) where Array(haystack[start..<(start + needle.count)]) == needle {
            return true
        }
        return false
    }

    // MARK: Token level

    private static func tokenAlternatives(_ tok: String, english: Bool, lenient: Bool) -> [[String]] {
        let base: [[String]] = english ? contractionExpansions(tok, lenient: lenient) : [[tok]]
        var result: [[String]] = []
        var seen = Set<String>()
        for arr in base {
            var partial: [[String]] = [[]]
            for w in arr {
                let alts = wordAlternatives(w, english: english)
                var next: [[String]] = []
                for p in partial { for a in alts { next.append(p + a) } }
                partial = Array(next.prefix(variantCap))
            }
            for p in partial where seen.insert(p.joined(separator: " ")).inserted { result.append(p) }
        }
        return result.isEmpty ? [[tok]] : result
    }

    private static func wordAlternatives(_ w: String, english: Bool) -> [[String]] {
        func canon(_ x: String) -> String { english ? (numberWords[x] ?? americanize(x)) : x }
        guard w.count > 1, w.contains("-") else { return [[canon(w)]] }
        let parts = w.split(separator: "-").map { String($0) }.filter { !$0.isEmpty }
        if parts.count < 2 { return [[canon(parts.joined())]] }
        return [[canon(w)], [canon(parts.joined())], parts.map { canon($0) }]
    }

    // MARK: English contractions

    private static let numberWords: [String: String] = {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                     "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen",
                     "nineteen", "twenty"]
        var d: [String: String] = [:]
        for (i, w) in words.enumerated() { d[String(i)] = w }
        return d
    }()

    private static let specialContractions: [String: [[String]]] = [
        "can't": [["can", "not"]], "cannot": [["can", "not"]], "won't": [["will", "not"]],
        "shan't": [["shall", "not"]], "let's": [["let", "us"]], "i'm": [["i", "am"]],
    ]

    private static let isHasStems: Set<String> = [
        "he", "she", "it", "that", "what", "there", "here", "who", "where", "how", "when", "why",
        "everyone", "everybody", "someone", "somebody", "nobody", "nothing", "something", "everything",
    ]

    /// Apostrophe-less spellings accepted at the lenient (typo) level.
    private static let lenientContractions: [String: [[String]]] = {
        var d: [String: [[String]]] = [
            "im": [["i", "am"]], "ive": [["i", "have"]], "youre": [["you", "are"]], "theyre": [["they", "are"]],
            "thats": [["that", "is"], ["that", "has"]], "whats": [["what", "is"], ["what", "has"]],
            "theres": [["there", "is"], ["there", "has"]], "wont": [["will", "not"]], "cant": [["can", "not"]],
        ]
        for aux in ["is", "are", "was", "were", "do", "does", "did", "have", "has", "had", "would", "could", "should", "must", "need"] {
            d[aux + "nt"] = [[aux, "not"]]
        }
        return d
    }()

    private static func contractionExpansions(_ tok: String, lenient: Bool) -> [[String]] {
        if let special = specialContractions[tok] { return special }
        if lenient, let l = lenientContractions[tok] { return [[tok]] + l }
        guard tok.contains("'") else { return [[tok]] }
        if tok.hasSuffix("n't"), tok.count > 3 {
            let stem = String(tok.dropLast(3))
            return [[stem, "not"]]
        }
        func split(_ suffix: String) -> String? {
            tok.hasSuffix(suffix) && tok.count > suffix.count ? String(tok.dropLast(suffix.count)) : nil
        }
        if let stem = split("'re") { return [[stem, "are"]] }
        if let stem = split("'ve") { return [[stem, "have"]] }
        if let stem = split("'ll") { return [[stem, "will"]] }
        if let stem = split("'m") { return [[stem, "am"]] }
        if let stem = split("'d") { return [[stem, "would"], [stem, "had"]] }
        if let stem = split("'s") {
            if isHasStems.contains(stem) { return [[stem, "is"], [stem, "has"]] }
            // Possessive 's of a noun stays as is; "Tom's a teacher" is also read as "Tom is a teacher".
            return [[tok], [stem, "is"]]
        }
        return [[tok]]
    }

    // MARK: British / American spelling

    private static let americanSpelling: [String: String] = [
        "colour": "color", "favourite": "favorite", "centre": "center", "theatre": "theater",
        "travelled": "traveled", "travelling": "traveling", "traveller": "traveler", "organise": "organize",
        "organised": "organized", "organising": "organizing", "realise": "realize", "realised": "realized",
        "recognise": "recognize", "apologise": "apologize", "grey": "gray", "mum": "mom", "cancelled": "canceled",
        "neighbour": "neighbor", "neighbourhood": "neighborhood", "behaviour": "behavior", "honour": "honor",
        "humour": "humor", "flavour": "flavor", "labour": "labor", "metre": "meter", "litre": "liter",
        "kilometre": "kilometer", "defence": "defense", "licence": "license", "programme": "program",
        "catalogue": "catalog", "dialogue": "dialog", "analyse": "analyze", "jewellery": "jewelry",
        "tyre": "tire", "pyjamas": "pajamas", "aluminium": "aluminum", "cosy": "cozy", "mould": "mold",
        "plough": "plow", "sceptical": "skeptical", "colourful": "colorful", "armour": "armor",
    ]

    private static func americanize(_ w: String) -> String {
        if let a = americanSpelling[w] { return a }
        if w.hasSuffix("s"), let a = americanSpelling[String(w.dropLast())] { return a + "s" }
        return w
    }
}

// MARK: - String distance

/// Optimal string alignment distance (Damerau-Levenshtein with adjacent transpositions).
func damerauLevenshtein(_ a: [Character], _ b: [Character]) -> Int {
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }
    var d = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
    for i in 0...a.count { d[i][0] = i }
    for j in 0...b.count { d[0][j] = j }
    for i in 1...a.count {
        for j in 1...b.count {
            let cost = a[i - 1] == b[j - 1] ? 0 : 1
            d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
            if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
            }
        }
    }
    return d[a.count][b.count]
}

func damerauLevenshtein(_ a: String, _ b: String) -> Int {
    damerauLevenshtein(Array(a), Array(b))
}

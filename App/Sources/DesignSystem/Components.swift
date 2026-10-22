import SwiftUI
import LearningCore

// Shared building blocks of the learning UI. Everything here relies on `Theme` tokens only.

// MARK: - Flow layout (wrapping chips, tokens, words)

/// Left-aligned layout that wraps its children onto new lines.
/// Call it as `QFlowLayout() { … }`: with defaulted init parameters, `Layout.callAsFunction`
/// needs the explicit parentheses (`QFlowLayout { … }` does not compile).
struct QFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    init(spacing: CGFloat = Theme.Spacing.s, lineSpacing: CGFloat = Theme.Spacing.s) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func measure(_ subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let proposedWidth: CGFloat? = maxWidth.isFinite ? maxWidth : nil
        return subview.sizeThatFits(ProposedViewSize(width: proposedWidth, height: nil))
    }

    private func makeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size: CGSize = measure(subviews[index], maxWidth: maxWidth)
            let lastIndex: Int = rows.count - 1
            let isEmptyRow: Bool = rows[lastIndex].indices.isEmpty
            let needed: CGFloat = isEmptyRow ? size.width : rows[lastIndex].width + spacing + size.width
            if needed > maxWidth && !isEmptyRow {
                rows.append(Row())
            }
            let target: Int = rows.count - 1
            let targetIsEmpty: Bool = rows[target].indices.isEmpty
            rows[target].width = targetIsEmpty ? size.width : rows[target].width + spacing + size.width
            rows[target].height = max(rows[target].height, size.height)
            rows[target].indices.append(index)
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth: CGFloat = proposal.width ?? .infinity
        let rows: [Row] = makeRows(maxWidth: maxWidth, subviews: subviews)
        let width: CGFloat = rows.map { $0.width }.max() ?? 0
        let heights: CGFloat = rows.reduce(CGFloat(0)) { $0 + $1.height }
        let gaps: CGFloat = CGFloat(max(rows.count - 1, 0)) * lineSpacing
        return CGSize(width: width, height: heights + gaps)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows: [Row] = makeRows(maxWidth: bounds.width, subviews: subviews)
        var y: CGFloat = bounds.minY
        for row in rows {
            var x: CGFloat = bounds.minX
            for index in row.indices {
                let size: CGSize = measure(subviews[index], maxWidth: bounds.width)
                let origin = CGPoint(x: x, y: y + (row.height - size.height) / 2)
                subviews[index].place(at: origin, anchor: .topLeading,
                                      proposal: ProposedViewSize(width: size.width, height: size.height))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }
}

// MARK: - Progress bar

struct QProgressBar: View {
    let value: Double
    var height: CGFloat = 8
    var track: Color = Theme.separator
    var fill: Color = Theme.ink

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(fill)
                    .frame(width: geometry.size.width * CGFloat(min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Small views

struct QSectionTitle: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(Theme.Font.headline)
            .tracking(-0.2)
            .foregroundStyle(Theme.primaryText)
            .accessibilityAddTraits(.isHeader)
    }
}

struct QBadge: View {
    let text: String
    let systemImage: String
    var tint: Color = Theme.ink
    var fill: Color = Theme.surface

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .medium))
                .accessibilityHidden(true)
            Text(text)
        }
        .font(Theme.Font.badge)
        .foregroundStyle(tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(fill))
        .accessibilityElement(children: .combine)
    }
}

/// Icon + text block on a soft background (feedback, tips, notices).
struct QCallout<Content: View>: View {
    let systemImage: String
    let tint: Color
    let fill: Color
    let content: Content

    init(systemImage: String, tint: Color = Theme.ink, fill: Color = Theme.accentSoft,
         @ViewBuilder content: () -> Content) {
        self.systemImage = systemImage
        self.tint = tint
        self.fill = fill
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s + 2) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(tint)
                .frame(width: 22)
                .accessibilityHidden(true)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(fill)
        )
    }
}

struct QStatTile: View {
    let value: String
    let label: String
    var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(value)
                .font(Theme.Font.miniStatValue.monospacedDigit())
                .foregroundStyle(Theme.primaryText)
            Text(label)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.tertiaryText)
            if let note {
                Text(note)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// Listen button (native text-to-speech through the shared `SpeechService`).
struct QSpeakerButton: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.speechEnabled) private var speechEnabled
    let text: String
    let slow: Bool

    init(text: String, slow: Bool = false) {
        self.text = text
        self.slow = slow
    }

    var body: some View {
        if speechEnabled { button }
    }

    private var button: some View {
        Button {
            env.speech.speak(spokenText, locale: env.store.learningSpeechLocale, slow: slow)
        } label: {
            QIconView(icon: slow ? .speakerSlow : .speaker, size: 18)
                .foregroundStyle(Theme.ink)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.surface))
                .frame(minWidth: Theme.minTapSize, minHeight: Theme.minTapSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .accessibilityLabel(slow ? "Écouter lentement" : "Écouter")
    }

    /// Blanks ("___") are not read aloud.
    private var spokenText: String {
        text.replacingOccurrences(of: "_+", with: "…", options: .regularExpression)
    }
}

/// Selectable chip / token button.
struct QChipButtonStyle: ButtonStyle {
    var isSelected: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.callout(.semibold))
            .foregroundStyle(isSelected ? Theme.onInk : Theme.ink)
            .padding(.horizontal, 18)
            .frame(minHeight: 48)
            .background(Capsule().fill(isSelected ? Theme.ink : Theme.surface))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

// MARK: - Stable shuffle (same order on every launch for a given seed)

struct StableRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: String) {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        state = hash
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z: UInt64 = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

extension Array {
    /// Fisher-Yates shuffle driven by a seeded generator: deterministic across launches and OS versions.
    func stableShuffled(seed: String) -> [Element] {
        var result: [Element] = self
        guard result.count > 1 else { return result }
        var generator = StableRandom(seed: seed)
        var i: Int = result.count - 1
        while i > 0 {
            let j = Int(generator.next() % UInt64(i + 1))
            if i != j { result.swapAt(i, j) }
            i -= 1
        }
        return result
    }
}

// MARK: - Text helpers

enum QMarkdown {
    /// Inline Markdown (bold, italic) from AI replies; falls back to the raw string.
    static func attributed(_ string: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let parsed = try? AttributedString(markdown: string, options: options) {
            return parsed
        }
        return AttributedString(string)
    }
}

enum FrenchLabels {
    private static let partsOfSpeech: [String: String] = [
        "noun": "nom", "n": "nom", "verb": "verbe", "v": "verbe",
        "adjective": "adjectif", "adj": "adjectif", "adverb": "adverbe", "adv": "adverbe",
        "preposition": "préposition", "prep": "préposition", "pronoun": "pronom", "pron": "pronom",
        "conjunction": "conjonction", "conj": "conjonction", "determiner": "déterminant",
        "article": "article", "interjection": "interjection", "exclamation": "interjection",
        "numeral": "nombre", "number": "nombre", "expression": "expression", "phrase": "expression",
        "modal": "verbe modal", "modal verb": "verbe modal", "auxiliary": "verbe auxiliaire",
        "auxiliary verb": "verbe auxiliaire", "phrasal verb": "verbe à particule",
        "particle": "particule", "quantifier": "quantificateur", "greeting": "salutation",
    ]

    static func partOfSpeech(_ raw: String) -> String {
        let key: String = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return partsOfSpeech[key] ?? raw
    }

    static let formLabels: [(key: String, label: String)] = [
        (key: "thirdPerson", label: "3ᵉ personne du singulier"),
        (key: "past", label: "Passé (prétérit)"),
        (key: "pastParticiple", label: "Participe passé"),
        (key: "ing", label: "Forme en -ing"),
        (key: "plural", label: "Pluriel"),
        (key: "comparative", label: "Comparatif"),
        (key: "superlative", label: "Superlatif"),
    ]

    static func percent(_ value: Double) -> String {
        let clamped: Double = min(max(value, 0), 1)
        return "\(Int((clamped * 100).rounded()))\u{00A0}%"
    }

    static func duration(seconds: Int) -> String {
        let total: Int = max(seconds, 0)
        if total < 60 { return "\(total) s" }
        let minutes: Int = total / 60
        if minutes < 60 { return "\(minutes) min" }
        let hours: Int = minutes / 60
        let rest: Int = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(String(format: "%02d", rest))"
    }

    static func days(_ count: Int) -> String {
        count > 1 ? "\(count) jours" : "\(count) jour"
    }

    /// "du matin", "de l'après-midi", "du soir"
    static func slotPhrase(_ slot: SessionSlot) -> String {
        switch slot {
        case .morning: return "du matin"
        case .afternoon: return "de l'après-midi"
        case .evening: return "du soir"
        }
    }
}

// MARK: - Store conveniences (language of the studied content)

extension LearningStore {
    /// Language code of the studied language ("en").
    var learningLanguageCode: String { engine?.language.code ?? "en" }
    /// Locale used by text-to-speech ("en-GB").
    var learningSpeechLocale: String { engine?.language.ttsLocale ?? "en-GB" }
}

extension LocalDay {
    /// "12 oct. 2026" in the user's locale.
    var shortDisplay: String {
        startDate().formatted(date: .abbreviated, time: .omitted)
    }
}

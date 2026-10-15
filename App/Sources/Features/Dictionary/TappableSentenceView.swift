import SwiftUI
import LearningCore

/// A sentence in the studied language whose words open their dictionary card.
/// Punctuation stays outside the buttons. Font and color follow the environment (`.font(...)`).
/// Words are marked by a dotted underline (never a blue link color) and keep a 44 pt tap target.
struct TappableSentenceView: View {
    let text: String
    let languageCode: String

    @Environment(AppEnvironment.self) private var env
    @ScaledMetric(relativeTo: .body) private var wordSpacing: CGFloat = 4
    @State private var sheet: WordLookupSheet?

    init(text: String, languageCode: String) {
        self.text = text
        self.languageCode = languageCode
    }

    var body: some View {
        Group {
            if languageCode == "fr" {
                Text(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                QFlowLayout(spacing: wordSpacing, lineSpacing: 0) {
                    ForEach(chunks) { chunk in
                        ChunkView(chunk: chunk) { open(chunk.core) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .word(let item):
                WordSheet(item: item)
            case .tutor(let request):
                TutorSheet(subject: request.subject)
            }
        }
    }

    // MARK: Splitting

    fileprivate struct Chunk: Identifiable {
        let id: Int
        let lead: String
        let core: String
        let trail: String
    }

    private var chunks: [Chunk] {
        let pieces: [String] = text
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0) }
        var result: [Chunk] = []
        for (index, piece) in pieces.enumerated() {
            result.append(Self.split(piece, id: index))
        }
        return result
    }

    private static func split(_ piece: String, id: Int) -> Chunk {
        let characters: [Character] = Array(piece)
        guard let first = characters.firstIndex(where: { $0.isLetter || $0.isNumber }),
              let last = characters.lastIndex(where: { $0.isLetter || $0.isNumber }) else {
            return Chunk(id: id, lead: piece, core: "", trail: "")
        }
        let lead = String(characters[characters.startIndex..<first])
        let core = String(characters[first...last])
        let trail = String(characters[characters.index(after: last)..<characters.endIndex])
        return Chunk(id: id, lead: lead, core: core, trail: trail)
    }

    // MARK: Lookup

    private func open(_ rawWord: String) {
        let word: String = rawWord.replacingOccurrences(of: "\u{2019}", with: "'")
        let lowercased: String = word.lowercased()
        if let item = env.store.dictionaryEntry(for: word) {
            sheet = .word(item)
        } else if lowercased != word, let item = env.store.dictionaryEntry(for: lowercased) {
            sheet = .word(item)
        } else {
            sheet = .tutor(TutorRequest(subject: .word(word, sentence: text)))
        }
    }

    // MARK: Subviews

    private struct ChunkView: View {
        let chunk: Chunk
        let action: () -> Void

        var body: some View {
            HStack(spacing: 0) {
                if !chunk.lead.isEmpty {
                    Text(chunk.lead)
                }
                if !chunk.core.isEmpty {
                    Button(action: action) {
                        Text(chunk.core)
                            .underline(true, pattern: .dot, color: Theme.onPastelSecondary)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 2)
                            .frame(minHeight: Theme.minTapSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(chunk.core)
                    .accessibilityHint("Ouvre la fiche du mot")
                }
                if !chunk.trail.isEmpty {
                    Text(chunk.trail)
                }
            }
            .padding(.vertical, chunk.core.isEmpty ? 10 : 0)
        }
    }
}

enum WordLookupSheet: Identifiable {
    case word(DictionaryItem)
    case tutor(TutorRequest)

    var id: String {
        switch self {
        case .word(let item): return "word-" + item.id
        case .tutor(let request): return "tutor-" + request.id.uuidString
        }
    }
}

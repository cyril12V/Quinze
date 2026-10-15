import SwiftUI

/// Privacy policy (French, RGPD), read from the bundled `PrivacyPolicy.md`.
/// A calm text page: big title, short intro, one white card per numbered section.
struct PrivacyPolicyView: View {
    private struct Block: Identifiable {
        enum Kind { case title, heading, subheading, bullet, paragraph }
        let id: Int
        let kind: Kind
        let text: String
    }

    /// A white card: its heading (nil for the intro) and the blocks that follow it.
    private struct Page: Identifiable {
        let id: Int
        let heading: String?
        let blocks: [Block]
    }

    @State private var blocks: [Block] = []

    var body: some View {
        let pages = Self.pages(from: blocks)
        QScreen {
            VStack(alignment: .leading, spacing: Theme.Spacing.card) {
                ForEach(pages) { page in
                    if page.heading == nil {
                        intro(page.blocks)
                    } else {
                        card(page)
                    }
                }
            }
        }
        .navigationTitle("Confidentialité")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .tint(Theme.ink)
        .task { if blocks.isEmpty { blocks = Self.load() } }
    }

    // MARK: Layout

    /// Title and opening paragraphs, without a card.
    private func intro(_ blocks: [Block]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            ForEach(blocks) { block in
                switch block.kind {
                case .title:
                    ScreenTitle(block.text)
                default:
                    Text(Self.attributed(block.text))
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.secondaryText)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.bottom, Theme.Spacing.card)
    }

    private func card(_ page: Page) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if let heading = page.heading {
                Text(Self.attributed(heading))
                    .font(Theme.Font.title)
                    .tracking(Theme.Tracking.title)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(page.blocks) { block in
                view(for: block)
            }
        }
        .card()
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block.kind {
        case .title, .heading:
            Text(Self.attributed(block.text))
                .font(Theme.Font.title)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
        case .subheading:
            Text(Self.attributed(block.text))
                .font(Theme.Font.headline)
                .foregroundStyle(Theme.primaryText)
                .padding(.top, Theme.Spacing.xs)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Text("•")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.ink)
                    .accessibilityHidden(true)
                Text(Self.attributed(block.text))
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.primaryText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .paragraph:
            Text(Self.attributed(block.text))
                .font(Theme.Font.body)
                .foregroundStyle(Theme.primaryText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Parsing

    /// Groups the flat list of blocks: everything before the first `##` heading is the intro, then one page per heading.
    private static func pages(from blocks: [Block]) -> [Page] {
        var result: [Page] = []
        var currentHeading: String?
        var current: [Block] = []
        var started = false

        func flush() {
            guard started else { return }
            result.append(Page(id: result.count, heading: currentHeading, blocks: current))
        }

        for block in blocks {
            if block.kind == .heading {
                flush()
                currentHeading = block.text
                current = []
                started = true
            } else {
                if !started {
                    started = true
                    currentHeading = nil
                }
                current.append(block)
            }
        }
        flush()
        return result
    }

    private static func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private static func load() -> [Block] {
        guard let url = Bundle.main.url(forResource: "PrivacyPolicy", withExtension: "md"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return [Block(id: 0, kind: .paragraph,
                          text: "La politique de confidentialité est disponible sur le site de l'application.")]
        }
        var result: [Block] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let id = result.count
            if trimmed.hasPrefix("### ") {
                result.append(Block(id: id, kind: .subheading, text: String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("## ") {
                result.append(Block(id: id, kind: .heading, text: String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("# ") {
                result.append(Block(id: id, kind: .title, text: String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("- ") {
                result.append(Block(id: id, kind: .bullet, text: String(trimmed.dropFirst(2))))
            } else {
                result.append(Block(id: id, kind: .paragraph, text: trimmed))
            }
        }
        return result
    }
}

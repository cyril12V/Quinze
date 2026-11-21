import SwiftUI

// MARK: - Course document

/// One chapter's course, written as a small Markdown file (`cours-m01.md` …) and read like a book.
///
/// The format, one block per line or paragraph:
/// - `# Titre` the chapter title (first line), `> texte` the lead under it;
/// - `## Titre` a section (it goes into the table of contents), `### Titre` a sub-title;
/// - a paragraph is a group of lines; `**gras**` and `*italique*` work inside;
/// - `- élément` a list;
/// - `!! texte` a box « À retenir »;
/// - `» texte` a quotation (Bible, Father of the Church);
/// - `@ date | événement` one line of a timeline;
/// - `? question | réponse` a question to test yourself, with its hidden answer;
/// - `%% l101 l102` under a section: the lessons that this section teaches (the lesson opens the course there).
struct CourseChapter: Identifiable, Hashable {
    let id: String
    let number: Int
    let title: String
    let lead: String
    let blocks: [CourseBlock]
    /// Lesson number (101, 1003…) → index of the block where its section starts.
    let lessons: [Int: Int]

    var sections: [(index: Int, title: String)] {
        blocks.enumerated().compactMap { offset, block in
            if case .section(let title) = block { return (offset, title) }
            return nil
        }
    }

    /// Minutes of reading, at about 200 words a minute.
    var minutes: Int {
        let words = blocks.reduce(0) { $0 + $1.wordCount }
        return max(1, Int((Double(words) / 200).rounded()))
    }

    static func == (a: CourseChapter, b: CourseChapter) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Every chapter found in the app, in order.
    static let all: [CourseChapter] = (1...30).compactMap { load(String(format: "m%02d", $0), number: $0) }

    static func load(_ id: String, number: Int) -> CourseChapter? {
        let name = "cours-" + id
        let url = Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "Content/cours")
            ?? Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "cours")
            ?? Bundle.main.url(forResource: name, withExtension: "md")
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text, id: id, number: number)
    }

    /// The chapter and the place in it that teach a lesson (« eg.l103 », or an exercise « eg.l103.e01 »).
    static func place(for lessonOrExercise: String) -> (chapter: CourseChapter, block: Int?)? {
        guard let lesson = lessonNumber(lessonOrExercise) else { return nil }
        let module = lesson / 100
        guard let chapter = all.first(where: { $0.number == module }) else { return nil }
        return (chapter, chapter.lessons[lesson])
    }

    static func lessonNumber(_ id: String) -> Int? {
        let parts = id.split(separator: ".")
        guard parts.count >= 2, parts[1].hasPrefix("l") else { return nil }
        return Int(parts[1].dropFirst())
    }

    static func parse(_ text: String, id: String, number: Int) -> CourseChapter {
        var title = ""
        var lead: [String] = []
        var blocks: [CourseBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var dates: [CourseDate] = []
        var lessons: [Int: Int] = [:]

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
            if !bullets.isEmpty { blocks.append(.bullets(bullets)); bullets = [] }
            if !dates.isEmpty { blocks.append(.dates(dates)); dates = [] }
        }

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("%% ") {
                flush()
                let section = blocks.lastIndex { if case .section = $0 { return true } else { return false } } ?? 0
                for word in line.dropFirst(3).split(separator: " ") {
                    if let n = Int(word.drop { !$0.isNumber }) { lessons[n] = section }
                }
            } else if line.hasPrefix("### ") {
                flush(); blocks.append(.subtitle(String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                flush(); blocks.append(.section(String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                flush(); title = String(line.dropFirst(2))
            } else if line.hasPrefix("> ") {
                flush(); lead.append(String(line.dropFirst(2)))
            } else if line.hasPrefix("!! ") {
                flush(); blocks.append(.keep(String(line.dropFirst(3))))
            } else if line.hasPrefix("» ") {
                flush(); blocks.append(.quote(String(line.dropFirst(2))))
            } else if line.hasPrefix("@ ") {
                if !paragraph.isEmpty || !bullets.isEmpty {
                    let keep = dates; dates = []; flush(); dates = keep
                }
                let parts = line.dropFirst(2).split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                dates.append(CourseDate(when: parts.first ?? "", what: parts.count > 1 ? parts[1] : ""))
            } else if line.hasPrefix("? ") {
                flush()
                let parts = line.dropFirst(2).split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                blocks.append(.check(parts.first ?? "", parts.count > 1 ? parts[1] : ""))
            } else if line.hasPrefix("- ") {
                if !paragraph.isEmpty || !dates.isEmpty {
                    let keep = bullets; bullets = []; flush(); bullets = keep
                }
                bullets.append(String(line.dropFirst(2)))
            } else {
                if !bullets.isEmpty || !dates.isEmpty {
                    let keep = paragraph; paragraph = []; flush(); paragraph = keep
                }
                paragraph.append(line)
            }
        }
        flush()
        return CourseChapter(id: id, number: number, title: title, lead: lead.joined(separator: " "),
                             blocks: blocks, lessons: lessons)
    }
}

struct CourseDate: Hashable {
    let when: String
    let what: String
}

enum CourseBlock: Hashable {
    case section(String)
    case subtitle(String)
    case paragraph(String)
    case bullets([String])
    case keep(String)
    case quote(String)
    case dates([CourseDate])
    case check(String, String)

    var wordCount: Int {
        func count(_ s: String) -> Int { s.split(whereSeparator: { $0 == " " }).count }
        switch self {
        case .section(let s), .subtitle(let s), .paragraph(let s), .keep(let s), .quote(let s): return count(s)
        case .bullets(let items): return items.reduce(0) { $0 + count($1) }
        case .dates(let rows): return rows.reduce(0) { $0 + count($1.when) + count($1.what) }
        case .check(let q, let a): return count(q) + count(a)
        }
    }
}

// MARK: - Reading progress

/// Where the reader stopped in each chapter (index of the last section reached), kept on the phone.
enum CourseProgress {
    private static let key = "nofri.course.sections"

    static func section(_ chapter: String) -> Int {
        (UserDefaults.standard.dictionary(forKey: key)?[chapter] as? Int) ?? 0
    }

    static func save(_ section: Int, for chapter: String) {
        var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        all[chapter] = section
        UserDefaults.standard.set(all, forKey: key)
    }
}

// MARK: - List of chapters

/// « Cours » : every chapter, to read like a book.
struct NofriCourseList: View {
    @State private var refresh = 0

    var body: some View {
        let _ = refresh
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cours")
                        .font(Theme.Font.largeTitle)
                        .foregroundStyle(Theme.primaryText)
                    Text("Chaque chapitre en entier, à lire comme un livre. Les leçons et les examens viennent de ce cours.")
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 6)
                ForEach(CourseChapter.all) { chapter in
                    NavigationLink {
                        CourseReader(chapter: chapter)
                    } label: {
                        CourseRow(chapter: chapter)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: Theme.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .onAppear { refresh += 1 }
    }
}

private struct CourseRow: View {
    let chapter: CourseChapter

    var body: some View {
        let total = max(1, chapter.sections.count)
        let reached = min(total, CourseProgress.section(chapter.id) + 1)
        let started = CourseProgress.section(chapter.id) > 0
        HStack(alignment: .top, spacing: 14) {
            Text("\(chapter.number)")
                .font(Theme.Font.jakarta(18, .bold, relativeTo: .headline))
                .foregroundStyle(Theme.onInk)
                .frame(width: 40, height: 40)
                .background(Theme.burgundy, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(chapter.title)
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.primaryText)
                    .multilineTextAlignment(.leading)
                Text(chapter.lead)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    Text("\(chapter.minutes) min de lecture")
                    Text("·")
                    Text(started ? "Partie \(reached) sur \(total)" : "\(total) parties")
                }
                .font(Theme.Font.badge)
                .foregroundStyle(started ? Theme.ink : Theme.tertiaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.separator, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

// MARK: - Reader

/// A chapter read like a PDF: one long page, big text (A− / A+ or pinch to zoom), a table of contents,
/// and it opens again where you stopped.
struct CourseReader: View {
    let chapter: CourseChapter
    /// Block to open at (a lesson's section); otherwise the place where the reader stopped.
    var start: Int? = nil
    @AppStorage("nofri.course.textSize") private var size: Double = 19
    @State private var pinchBase: Double?
    @State private var showContents = false
    @State private var jump: Int?
    @State private var resumed = false

    private var next: CourseChapter? {
        CourseChapter.all.first { $0.number == chapter.number + 1 }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                    ForEach(Array(chapter.blocks.enumerated()), id: \.offset) { index, block in
                        CourseBlockView(block: block, size: size)
                            .id(index)
                            .onAppear {
                                if case .section = block, resumed { CourseProgress.save(index, for: chapter.id) }
                            }
                    }
                    footer
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
                .frame(maxWidth: Theme.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.surface.ignoresSafeArea())
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let base = pinchBase ?? size
                        pinchBase = base
                        size = min(30, max(15, base * value.magnification))
                    }
                    .onEnded { _ in pinchBase = nil }
            )
            .onChange(of: jump) { _, target in
                guard let target else { return }
                withAnimation(.easeInOut) { proxy.scrollTo(target, anchor: .top) }
                jump = nil
            }
            .onAppear {
                let saved = start ?? CourseProgress.section(chapter.id)
                if saved > 0, !resumed {
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        proxy.scrollTo(saved, anchor: .top)
                        try? await Task.sleep(for: .milliseconds(300))
                        resumed = true
                    }
                } else {
                    resumed = true
                }
            }
        }
        .navigationTitle("Chapitre \(chapter.number)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { size = max(15, size - 2) } label: {
                    Text("A−").font(Theme.Font.jakarta(15, .semibold))
                }
                .accessibilityLabel("Texte plus petit")
                Button { size = min(30, size + 2) } label: {
                    Text("A+").font(Theme.Font.jakarta(19, .bold))
                }
                .accessibilityLabel("Texte plus grand")
                Button { showContents = true } label: {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel("Sommaire")
            }
        }
        .sheet(isPresented: $showContents) {
            CourseContents(chapter: chapter) { index in
                showContents = false
                jump = index
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CHAPITRE \(chapter.number)")
                .font(Theme.Font.jakarta(12, .bold, relativeTo: .caption))
                .tracking(1.5)
                .foregroundStyle(Theme.ink)
            Text(chapter.title)
                .font(Theme.Font.jakarta(size + 11, .bold, relativeTo: .largeTitle))
                .foregroundStyle(Theme.primaryText)
            if !chapter.lead.isEmpty {
                Text(CourseText.styled(chapter.lead))
                    .font(Theme.Font.jakarta(size, .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .lineSpacing(size * 0.35)
            }
            Button { showContents = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet")
                    Text("Sommaire · \(chapter.sections.count) parties · \(chapter.minutes) min")
                }
                .font(Theme.Font.button)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.background, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(Theme.separator).frame(height: 1).padding(.top, 30)
            Text("Fin du chapitre \(chapter.number)")
                .font(Theme.Font.jakarta(size - 2, .semibold))
                .foregroundStyle(Theme.secondaryText)
            if let next {
                NavigationLink {
                    CourseReader(chapter: next)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Chapitre suivant")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.onInk.opacity(0.8))
                            Text(next.title)
                                .font(Theme.Font.headline)
                                .foregroundStyle(Theme.onInk)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.onInk)
                    }
                    .padding(16)
                    .background(Theme.burgundy, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CourseContents: View {
    let chapter: CourseChapter
    let go: (Int) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(chapter.sections.enumerated()), id: \.offset) { number, section in
                    Button { go(section.index) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(number + 1)")
                                .font(Theme.Font.jakarta(14, .bold))
                                .foregroundStyle(Theme.ink)
                                .frame(width: 24, alignment: .trailing)
                            Text(section.title)
                                .font(Theme.Font.body)
                                .foregroundStyle(Theme.primaryText)
                        }
                    }
                }
            }
            .navigationTitle(chapter.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - From a lesson

/// « Lire dans le cours » : opens the chapter's course at the section that teaches this lesson.
struct CourseLinkButton: View {
    /// Lesson id (« eg.l103 ») or exercise id (« eg.l103.e01 »).
    let id: String
    var title = "Lire ce passage dans le cours"
    @State private var open = false

    var body: some View {
        if let place = CourseChapter.place(for: id) {
            Button { open = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "book.pages")
                    Text(title)
                }
                .font(Theme.Font.button)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(Theme.separator, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $open) {
                NavigationStack {
                    CourseReader(chapter: place.chapter, start: place.block)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Fermer") { open = false }
                            }
                        }
                }
            }
        }
    }
}

// MARK: - Blocks

enum CourseText {
    /// `**gras**` and `*italique*` inside a line.
    static func styled(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

private struct CourseBlockView: View {
    let block: CourseBlock
    let size: Double
    @State private var revealed = false

    var body: some View {
        switch block {
        case .section(let title):
            Text(title)
                .font(Theme.Font.jakarta(size + 6, .bold, relativeTo: .title))
                .foregroundStyle(Theme.ink)
                .padding(.top, 34)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        case .subtitle(let title):
            Text(title)
                .font(Theme.Font.jakarta(size + 1, .bold, relativeTo: .title3))
                .foregroundStyle(Theme.primaryText)
                .padding(.top, 20)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            Text(CourseText.styled(text))
                .font(Theme.Font.jakarta(size, .regular))
                .foregroundStyle(Theme.primaryText)
                .lineSpacing(size * 0.4)
                .padding(.top, 14)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(Theme.ink).frame(width: 6, height: 6).offset(y: -size * 0.15)
                        Text(CourseText.styled(item))
                            .font(Theme.Font.jakarta(size, .regular))
                            .foregroundStyle(Theme.primaryText)
                            .lineSpacing(size * 0.3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 14)
        case .keep(let text):
            VStack(alignment: .leading, spacing: 6) {
                Text("À RETENIR")
                    .font(Theme.Font.jakarta(11, .bold, relativeTo: .caption2))
                    .tracking(1.2)
                    .foregroundStyle(Theme.onGold)
                Text(CourseText.styled(text))
                    .font(Theme.Font.jakarta(size - 1, .semibold))
                    .foregroundStyle(Theme.onGold)
                    .lineSpacing(size * 0.3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.gold.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.gold).frame(width: 4).padding(.vertical, 10)
            }
            .padding(.top, 18)
        case .quote(let text):
            Text(CourseText.styled(text))
                .font(Theme.Font.jakarta(size - 1, .medium))
                .italic()
                .foregroundStyle(Theme.secondaryText)
                .lineSpacing(size * 0.3)
                .padding(.leading, 16)
                .overlay(alignment: .leading) { Rectangle().fill(Theme.ink.opacity(0.5)).frame(width: 3) }
                .padding(.top, 16)
                .fixedSize(horizontal: false, vertical: true)
        case .dates(let rows):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(row.when)
                            .font(Theme.Font.jakarta(size - 2, .bold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: size * 5.2, alignment: .leading)
                        Text(CourseText.styled(row.what))
                            .font(Theme.Font.jakarta(size - 2, .regular))
                            .foregroundStyle(Theme.primaryText)
                            .lineSpacing(size * 0.25)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 9)
                    if index < rows.count - 1 { Rectangle().fill(Theme.separator).frame(height: 1) }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 16)
        case .check(let question, let answer):
            Button { withAnimation(.easeOut(duration: 0.2)) { revealed.toggle() } } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: revealed ? "checkmark.circle.fill" : "questionmark.circle")
                            .foregroundStyle(Theme.ink)
                        Text(CourseText.styled(question))
                            .font(Theme.Font.jakarta(size - 1, .semibold))
                            .foregroundStyle(Theme.primaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if revealed {
                        Text(CourseText.styled(answer))
                            .font(Theme.Font.jakarta(size - 1, .regular))
                            .foregroundStyle(Theme.secondaryText)
                            .lineSpacing(size * 0.3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 28)
                    } else {
                        Text("Touche pour voir la réponse")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.tertiaryText)
                            .padding(.leading, 28)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
    }
}

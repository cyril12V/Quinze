import SwiftUI
import PhotosUI
import UIKit

/// One chant, laid out like the player of the reference: the sheets in a big card (swipe left and right),
/// the name, the page bar, and black buttons to go to the chant before or after.
struct SongView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var currentID: UUID
    @State private var page = 0
    @State private var choice: Mode?
    @State private var viewer: ViewerStart?
    @State private var edited: SongRef?
    @State private var picking = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var scanning = false
    @State private var confirmDelete = false
    @State private var confirmRemovePage = false
    @State private var writing: TextDraft?

    /// What the page shows: the hazzat sheets, or one of the texts.
    enum Mode: Hashable {
        case sheets
        case text(UUID)
    }

    init(songID: UUID) {
        _currentID = State(initialValue: songID)
    }

    var body: some View {
        Group {
            if let entry = library.locate(currentID) {
                content(entry)
            } else {
                VStack(spacing: 0) {
                    TopBar()
                    Spacer()
                    Text("Ce chant n'existe plus.").font(Typo.caption).foregroundStyle(Palette.muted)
                    Spacer()
                }
            }
        }
        .background(Palette.background)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { library.markOpened(currentID) }
        .onChange(of: currentID) { _, id in
            page = 0
            choice = nil
            library.markOpened(id)
        }
        .photosPicker(isPresented: $picking, selection: $picked, maxSelectionCount: 30,
                      selectionBehavior: .ordered, matching: .images)
        .onChange(of: picked) { _, items in importPhotos(items) }
        .fullScreenCover(isPresented: $scanning) {
            DocumentScanner { images in
                scanning = false
                let names = images.compactMap { library.storeImage($0) }
                addSheets(names)
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $viewer) { start in
            if let song = library.song(currentID) {
                SheetViewer(images: song.images, title: song.title, start: start.page)
            }
        }
        .sheet(item: $edited) { SongEditor(songID: $0.id).environment(library) }
        .sheet(item: $writing) { draft in
            TextEditorSheet(songID: draft.songID, text: draft.text, isNew: draft.isNew) { saved in
                choice = saved.map { Mode.text($0) }
            }
            .environment(library)
        }
        .confirmationDialog("Supprimer ce chant ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer le chant", role: .destructive) {
                let id = currentID
                dismiss()
                library.deleteSongs([id])
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Ses feuilles et ses textes seront effacés du téléphone.")
        }
        .confirmationDialog("Retirer cette feuille ?", isPresented: $confirmRemovePage, titleVisibility: .visible) {
            Button("Retirer la feuille \(page + 1)", role: .destructive) { removeCurrentPage() }
            Button("Annuler", role: .cancel) {}
        }
    }

    // MARK: Layout

    private func isFranco(_ entry: Library.Entry) -> Bool {
        HomeView.fold(entry.period.name) == "franco"
    }

    private func content(_ entry: Library.Entry) -> some View {
        let song = entry.song
        let texts = song.writtenTexts
        let textFirst = isFranco(entry) || song.images.isEmpty
        let fallback: Mode = textFirst && !texts.isEmpty ? .text(texts[0].id) : .sheets
        var mode = choice ?? fallback
        if case .text(let id) = mode, !texts.contains(where: { $0.id == id }) { mode = fallback }
        let shown = texts.first { if case .text(let id) = mode { return $0.id == id } else { return false } }
        let previous = library.neighbor(of: song.id, step: -1).flatMap { library.song($0) }
        let next = library.neighbor(of: song.id, step: 1).flatMap { library.song($0) }
        return VStack(spacing: 0) {
            TopBar(caption: entry.place)
            ScrollView {
                VStack(spacing: 0) {
                    ModePicker(tabs: tabs(texts, textsFirst: isFranco(entry)),
                               mode: Binding(get: { mode }, set: { choice = $0 })) { language in
                        writing = TextDraft(songID: song.id, text: SongText(language: language), isNew: true)
                    }
                    .padding(.top, 2)
                    .padding(.bottom, 10)
                    if let shown {
                        titleRow(entry).padding(.top, 8)
                        TextReader(text: shown)
                            .padding(.horizontal, 24)
                            .padding(.top, 22)
                        Button {
                            writing = TextDraft(songID: song.id, text: shown, isNew: false)
                        } label: {
                            Label("Modifier le texte", systemImage: "pencil")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Palette.line, lineWidth: 1.5))
                        }
                        .plainButton()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                    } else {
                        if song.images.isEmpty {
                            if isFranco(entry) && texts.isEmpty {
                                writeTile(song.id)
                            } else {
                                addTile(song.id)
                            }
                        } else {
                            SheetCarousel(images: song.images, page: $page) { viewer = ViewerStart(page: page) }
                            PageDots(page: page, count: song.images.count)
                        }
                        titleRow(entry).padding(.top, 16)
                    }
                    NeighborBar(previous: previous, next: next) { go(to: $0) }
                        .padding(.top, 26)
                }
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .bottom) {
            if importing {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Ajout des feuilles…").font(Typo.caption).foregroundStyle(Palette.ink)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white, in: Capsule())
                .softShadow()
                .padding(.bottom, 30)
            }
        }
    }

    /// « Hazzat », then one tab per text (« Franco », « Arabe »…); in Franco the texts come first.
    private func tabs(_ texts: [SongText], textsFirst: Bool) -> [(title: String, mode: Mode)] {
        var counts: [TextLanguage: Int] = [:]
        let textTabs: [(title: String, mode: Mode)] = texts.map { text in
            counts[text.language, default: 0] += 1
            let n = counts[text.language] ?? 1
            let total = texts.filter { $0.language == text.language }.count
            return (total > 1 ? "\(text.language.label) \(n)" : text.language.label, Mode.text(text.id))
        }
        let sheets: [(title: String, mode: Mode)] = [("Hazzat", .sheets)]
        return textsFirst ? textTabs + sheets : sheets + textTabs
    }

    /// The big dashed tile with a « + », where a sheet or a text will be.
    private func dashedTile(icon: String, caption: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.iconOff.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(Palette.iconOn)
                Text(caption)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.muted)
            }
        }
        .aspectRatio(0.8, contentMode: .fit)
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    /// No sheet yet: a big « + » where the sheet will be (photos, scan or a text).
    private func addTile(_ songID: UUID) -> some View {
        Menu {
            Button { picking = true } label: { Label("Choisir des photos", systemImage: "photo.on.rectangle") }
            if DocumentScanner.isAvailable {
                Button { scanning = true } label: { Label("Scanner des feuilles", systemImage: "doc.viewfinder") }
            }
            Menu {
                ForEach(TextLanguage.allCases, id: \.self) { language in
                    Button(language.label) {
                        writing = TextDraft(songID: songID, text: SongText(language: language), isNew: true)
                    }
                }
            } label: {
                Label("Écrire un texte", systemImage: "text.alignleft")
            }
        } label: {
            dashedTile(icon: "plus", caption: "Feuille ou texte")
        }
        .accessibilityLabel("Ajouter une feuille ou un texte")
    }

    /// Franco is only text: the « + » opens the writing at once.
    private func writeTile(_ songID: UUID) -> some View {
        Button {
            writing = TextDraft(songID: songID, text: SongText(language: .franco), isNew: true)
        } label: {
            dashedTile(icon: "plus", caption: "Écrire le texte en franco")
        }
        .plainButton()
        .accessibilityLabel("Écrire le texte en franco")
    }

    private func titleRow(_ entry: Library.Entry) -> some View {
        let song = entry.song
        return HStack(alignment: .center, spacing: 2) {
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.place)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 8)
            IconButton(systemName: song.favorite ? "bookmark.fill" : "bookmark",
                       label: song.favorite ? "Retirer des favoris" : "Ajouter aux favoris") {
                library.toggleFavorite(song.id)
            }
            MoreMenu {
                Menu {
                    ForEach(TextLanguage.allCases, id: \.self) { language in
                        Button(language.label) {
                            writing = TextDraft(songID: song.id, text: SongText(language: language), isNew: true)
                        }
                    }
                } label: {
                    Label("Ajouter un texte", systemImage: "text.alignleft")
                }
                Button { picking = true } label: { Label("Ajouter des photos", systemImage: "photo.on.rectangle") }
                if DocumentScanner.isAvailable {
                    Button { scanning = true } label: { Label("Scanner des feuilles", systemImage: "doc.viewfinder") }
                }
                Button { edited = SongRef(id: song.id) } label: {
                    Label("Modifier (nom, partie, ordre des feuilles…)", systemImage: "slider.horizontal.3")
                }
                if !song.images.isEmpty {
                    Button(role: .destructive) { confirmRemovePage = true } label: {
                        Label("Retirer cette feuille", systemImage: "minus.rectangle")
                    }
                }
                Divider()
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Supprimer le chant", systemImage: "trash")
                }
            }
        }
        .padding(.leading, 24)
        .padding(.trailing, 12)
    }

    // MARK: Actions

    private func go(to id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) { currentID = id }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        importing = true
        Task {
            var names: [String] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let name = library.storeImage(data) {
                    names.append(name)
                }
            }
            addSheets(names)
            picked = []
            importing = false
        }
    }

    private func addSheets(_ names: [String]) {
        guard !names.isEmpty else { return }
        let before = library.song(currentID)?.images.count ?? 0
        library.addImages(names, to: currentID)
        choice = .sheets
        page = before
    }

    private func removeCurrentPage() {
        guard let song = library.song(currentID), song.images.indices.contains(page) else { return }
        library.removeImage(song.images[page], from: currentID)
        page = max(0, min(page, song.images.count - 2))
    }
}

// MARK: - Pieces

struct ViewerStart: Identifiable {
    let page: Int
    var id: Int { page }
}

/// « Hazzat · Franco · Arabe… + », black when chosen with a small orange bar; « + » adds a text.
struct ModePicker: View {
    let tabs: [(title: String, mode: SongView.Mode)]
    @Binding var mode: SongView.Mode
    let add: (TextLanguage) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 22) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { _, tab in
                    item(tab.title, tab.mode)
                }
                Menu {
                    ForEach(TextLanguage.allCases, id: \.self) { language in
                        Button(language.label) { add(language) }
                    }
                } label: {
                    VStack(spacing: 5) {
                        HStack(spacing: 3) {
                            Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                            Text("Texte").font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(Palette.iconOff)
                        Capsule().fill(.clear).frame(width: 16, height: 3)
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityLabel("Ajouter un texte")
            }
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
    }

    private func item(_ title: String, _ value: SongView.Mode) -> some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { mode = value } } label: {
            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 13, weight: mode == value ? .bold : .medium))
                    .foregroundStyle(mode == value ? Palette.ink : Palette.iconOff)
                Capsule()
                    .fill(mode == value ? Palette.accent : .clear)
                    .frame(width: 16, height: 3)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .plainButton()
        .accessibilityAddTraits(mode == value ? .isSelected : [])
    }
}

/// A text to read: big letters, comfortable lines; Arabic from right to left, Coptic with a Coptic font.
struct TextReader: View {
    let text: SongText

    var body: some View {
        Text(text.body)
            .font(Typo.text(text.language))
            .lineSpacing(9)
            .foregroundStyle(Palette.ink)
            .multilineTextAlignment(text.language.rightToLeft ? .trailing : .leading)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: text.language.rightToLeft ? .trailing : .leading)
            .environment(\.layoutDirection, text.language.rightToLeft ? .rightToLeft : .leftToRight)
    }
}

struct TextDraft: Identifiable {
    let id = UUID()
    let songID: UUID
    let text: SongText
    let isNew: Bool
}

/// Writing or changing one text of a chant, in copte, franco, arabe or français.
struct TextEditorSheet: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    let songID: UUID
    @State private var text: SongText
    let isNew: Bool
    /// Called after saving with the id of the text (nil when it was removed).
    let done: (UUID?) -> Void
    @State private var confirmDelete = false
    @FocusState private var focused: Bool

    init(songID: UUID, text: SongText, isNew: Bool, done: @escaping (UUID?) -> Void = { _ in }) {
        self.songID = songID
        _text = State(initialValue: text)
        self.isNew = isNew
        self.done = done
    }

    private var placeholder: String {
        switch text.language {
        case .copte: "Colle ou écris le texte copte…"
        case .franco: "Écris le texte en franco (ex. Efrahi ya Mariam…)"
        case .arabe: "اكتب النص بالعربية…"
        case .francais: "Écris le texte en français…"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Langue", selection: $text.language) {
                    ForEach(TextLanguage.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                ZStack(alignment: text.language.rightToLeft ? .topTrailing : .topLeading) {
                    TextEditor(text: $text.body)
                        .font(Typo.text(text.language))
                        .lineSpacing(6)
                        .multilineTextAlignment(text.language.rightToLeft ? .trailing : .leading)
                        .environment(\.layoutDirection, text.language.rightToLeft ? .rightToLeft : .leftToRight)
                        .autocorrectionDisabled(text.language != .francais)
                        .textInputAutocapitalization(text.language == .francais ? .sentences : .never)
                        .scrollContentBackground(.hidden)
                        .focused($focused)
                    if text.body.isEmpty {
                        Text(placeholder)
                            .font(Typo.text(text.language))
                            .foregroundStyle(Palette.iconOff)
                            .padding(.top, 8)
                            .padding(.horizontal, 5)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 16)
                if !isNew {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Text("Supprimer ce texte").font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.vertical, 12)
                }
            }
            .background(Color.white)
            .navigationTitle(isNew ? "Nouveau texte" : "Texte \(text.language.label.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundStyle(Palette.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") {
                        library.saveText(text, in: songID)
                        let kept = library.song(songID)?.texts.contains { $0.id == text.id } ?? false
                        done(kept ? text.id : nil)
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Palette.accent)
                }
            }
            .onAppear { focused = isNew }
            .confirmationDialog("Supprimer ce texte ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    library.removeText(text.id, from: songID)
                    done(nil)
                    dismiss()
                }
                Button("Annuler", role: .cancel) {}
            }
        }
    }
}

/// The sheets, one card per photo; swipe left and right. Touch one to read it in full screen.
struct SheetCarousel: View {
    let images: [String]
    @Binding var page: Int
    let open: () -> Void

    var body: some View {
        TabView(selection: $page) {
            ForEach(Array(images.enumerated()), id: \.offset) { index, name in
                SheetCard(name: name)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .padding(.bottom, 26)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: open)
                    .tag(index)
                    .accessibilityLabel("Feuille \(index + 1) sur \(images.count)")
                    .accessibilityHint("Touche pour lire en plein écran")
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .aspectRatio(0.8, contentMode: .fit)
        .onChange(of: images.count) { _, count in page = min(page, max(0, count - 1)) }
    }
}

struct SheetCard: View {
    let name: String

    var body: some View {
        ZStack {
            Color.white
            if let image = Images.image(name, maxPixel: 1800) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Palette.iconOff)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .softShadow()
    }
}

/// Small marks under the sheets: which one is shown.
struct PageDots: View {
    let page: Int
    let count: Int

    var body: some View {
        Group {
            if count > 12 {
                Text("\(page + 1) / \(count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.muted)
            } else if count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<count, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Palette.accent : Palette.track)
                            .frame(width: index == page ? 18 : 6, height: 6)
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Feuille \(page + 1) sur \(count)")
    }
}

/// The chant before and the chant after, in the order of the period.
struct NeighborBar: View {
    let previous: Song?
    let next: Song?
    let go: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.line).frame(height: 1)
            HStack(alignment: .top, spacing: 12) {
                side(previous, label: "Précédent", leading: true)
                side(next, label: "Suivant", leading: false)
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func side(_ song: Song?, label: String, leading: Bool) -> some View {
        Button { if let song { go(song.id) } } label: {
            HStack(spacing: 8) {
                if leading { chevron("chevron.left", on: song != nil) }
                VStack(alignment: leading ? .leading : .trailing, spacing: 2) {
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                    Text(song?.title ?? "—")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(song == nil ? Palette.iconOff : Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(leading ? .leading : .trailing)
                }
                if !leading { chevron("chevron.right", on: song != nil) }
            }
            .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
            .contentShape(Rectangle())
        }
        .plainButton()
        .disabled(song == nil)
        .accessibilityLabel(song.map { "\(label) : \($0.title)" } ?? "Pas de chant \(label.lowercased())")
    }

    private func chevron(_ name: String, on: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(on ? Palette.iconOn : Palette.iconOff)
    }
}

// MARK: - Full screen

/// The sheets in full screen: swipe between them, pinch or double-tap to zoom.
struct SheetViewer: View {
    let images: [String]
    let title: String
    @State private var page: Int
    @Environment(\.dismiss) private var dismiss

    init(images: [String], title: String, start: Int) {
        self.images = images
        self.title = title
        _page = State(initialValue: min(max(0, start), max(0, images.count - 1)))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.white.ignoresSafeArea()
            TabView(selection: $page) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, name in
                    ZoomablePage(name: name).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Palette.iconOn)
                        .frame(width: 44, height: 44)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 3)
                }
                .plainButton()
                .accessibilityLabel("Fermer")
                Spacer()
                VStack(spacing: 1) {
                    Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                    Text("\(page + 1) / \(images.count)").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
        }
        .statusBarHidden()
    }
}

struct ZoomablePage: View {
    let name: String

    var body: some View {
        if let image = UIImage(contentsOfFile: Library.imageURL(name).path) {
            ZoomableImage(image: image)
        } else {
            Color.white
        }
    }
}

struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.backgroundColor = .white
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 6
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.delegate = context.coordinator
        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            view.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            view.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            view.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            view.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        context.coordinator.imageView = view
        context.coordinator.scrollView = scroll
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        weak var scrollView: UIScrollView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            guard let scroll = scrollView else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = recognizer.location(in: imageView)
                let size = CGSize(width: scroll.bounds.width / 2.5, height: scroll.bounds.height / 2.5)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
            }
        }
    }
}

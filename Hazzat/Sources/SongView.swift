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

    enum Mode: Hashable { case sheets, lyrics }

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
        .confirmationDialog("Supprimer ce chant ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer le chant", role: .destructive) {
                let id = currentID
                dismiss()
                library.deleteSongs([id])
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Ses feuilles et ses paroles seront effacées du téléphone.")
        }
        .confirmationDialog("Retirer cette feuille ?", isPresented: $confirmRemovePage, titleVisibility: .visible) {
            Button("Retirer la feuille \(page + 1)", role: .destructive) { removeCurrentPage() }
            Button("Annuler", role: .cancel) {}
        }
    }

    // MARK: Layout

    private func content(_ entry: Library.Entry) -> some View {
        let song = entry.song
        let mode = choice ?? (song.images.isEmpty && !song.text.isEmpty ? .lyrics : .sheets)
        let previous = library.neighbor(of: song.id, step: -1)
        let next = library.neighbor(of: song.id, step: 1)
        return VStack(spacing: 0) {
            TopBar(caption: entry.place)
            ScrollView {
                VStack(spacing: 0) {
                    if !song.text.isEmpty {
                        ModePicker(mode: Binding(get: { mode }, set: { choice = $0 }))
                            .padding(.top, 2)
                            .padding(.bottom, 10)
                    }
                    if mode == .sheets {
                        if song.images.isEmpty {
                            emptySheets(entry)
                        } else {
                            SheetCarousel(images: song.images, page: $page) { viewer = ViewerStart(page: page) }
                        }
                        titleRow(entry).padding(.top, 20)
                        if !song.images.isEmpty {
                            PageBar(page: page, count: song.images.count).padding(.top, 18)
                        }
                    } else {
                        titleRow(entry).padding(.top, 8)
                        Text(song.text)
                            .font(Typo.lyrics)
                            .lineSpacing(9)
                            .foregroundStyle(Palette.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.top, 22)
                    }
                    controls(previous: previous, next: next, song: song, mode: mode)
                        .padding(.top, 16)
                }
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            NextStrip(entry: entry, next: next.flatMap { library.song($0) }) {
                if let next { go(to: next) }
            }
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
                .padding(.bottom, 70)
            }
        }
    }

    private func emptySheets(_ entry: Library.Entry) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Palette.cover(for: entry.period.name)
                VStack(spacing: 10) {
                    Text(entry.song.title.uppercased())
                        .font(.system(size: 22, weight: .semibold))
                        .tracking(4)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .minimumScaleFactor(0.6)
                    Text(entry.period.name.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .tracking(3)
                        .opacity(0.7)
                }
                .foregroundStyle(.white)
                .padding(30)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .softShadow()
            .padding(.horizontal, 24)
            .padding(.top, 8)
            HStack(spacing: 10) {
                SmallButton("Ajouter des photos") { picking = true }
                if DocumentScanner.isAvailable {
                    SmallButton("Scanner") { scanning = true }
                }
            }
        }
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

    private func controls(previous: UUID?, next: UUID?, song: Song, mode: Mode) -> some View {
        HStack {
            Button { if let previous { go(to: previous) } } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(previous == nil ? Palette.track : Color(hex: 0x8A8A8A))
                    .frame(width: 56, height: 56)
            }
            .plainButton()
            .disabled(previous == nil)
            .accessibilityLabel("Chant précédent")
            Spacer()
            Button {
                if song.images.isEmpty { picking = true } else { viewer = ViewerStart(page: mode == .sheets ? page : 0) }
            } label: {
                Image(systemName: song.images.isEmpty ? "plus" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundStyle(Palette.iconOn)
                    .frame(width: 70, height: 70)
            }
            .plainButton()
            .accessibilityLabel(song.images.isEmpty ? "Ajouter des feuilles" : "Lire en plein écran")
            Spacer()
            Button { if let next { go(to: next) } } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(next == nil ? Palette.track : Color(hex: 0x8A8A8A))
                    .frame(width: 56, height: 56)
            }
            .plainButton()
            .disabled(next == nil)
            .accessibilityLabel("Chant suivant")
        }
        .padding(.horizontal, 44)
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

/// « Hazzat · Paroles », black when chosen with a small orange bar.
struct ModePicker: View {
    @Binding var mode: SongView.Mode

    var body: some View {
        HStack(spacing: 26) {
            tab("Hazzat", .sheets)
            tab("Paroles", .lyrics)
        }
    }

    private func tab(_ title: String, _ value: SongView.Mode) -> some View {
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

/// Orange progress across the sheets, like the time bar of the reference.
struct PageBar: View {
    let page: Int
    let count: Int

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let fraction = count <= 1 ? 1 : CGFloat(page) / CGFloat(count - 1)
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.track).frame(height: 3)
                    Capsule().fill(Palette.accent).frame(width: max(3, width * fraction), height: 3)
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: 12, height: 12)
                        .offset(x: min(max(0, width * fraction - 6), width - 12))
                }
                .frame(height: 12)
            }
            .frame(height: 12)
            HStack {
                Text("Feuille \(page + 1)")
                Spacer()
                Text("\(count)")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 24)
        .animation(.easeOut(duration: 0.2), value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Feuille \(page + 1) sur \(count)")
    }
}

/// The thin bar at the very bottom: the next chant, and where this one is in the period.
struct NextStrip: View {
    let entry: Library.Entry
    let next: Song?
    let action: () -> Void

    private var position: String {
        let index = (entry.period.songs.firstIndex { $0.id == entry.song.id } ?? 0) + 1
        return "\(index)/\(entry.period.songs.count)"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.iconOn)
                if let next {
                    Text("Suivant · \(next.title)")
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                } else {
                    Text("Dernier chant de \(entry.period.name)")
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(entry.period.name + ".")
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                Text(position)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
            .font(.system(size: 12))
            .padding(.horizontal, 24)
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .background(Color.white.shadow(.drop(color: .black.opacity(0.06), radius: 12, x: 0, y: -2)))
        }
        .plainButton()
        .disabled(next == nil)
        .accessibilityLabel(next.map { "Chant suivant : \($0.title)" } ?? "Dernier chant de la période")
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

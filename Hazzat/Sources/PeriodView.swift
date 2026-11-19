import SwiftUI

/// A period: its chants grouped by part, folded. Touch one to unfold its hazzat sheets and its words.
struct PeriodView: View {
    @Environment(Library.self) private var library
    let periodID: UUID
    /// A chant to open and show at once (from the search).
    let focus: UUID?
    @State private var opened: Set<UUID> = []
    @State private var editing: SongRef?
    @State private var zoomed: ZoomTarget?

    var body: some View {
        let period = library.period(periodID)
        let parts = period?.parts ?? []
        let named = parts.enumerated().filter { !$0.element.section.isEmpty }
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(summary(period, parts: parts))
                        .font(Typo.body(14, .medium))
                        .foregroundStyle(Palette.muted)
                        .padding(.horizontal, 20)

                    if named.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(named, id: \.offset) { index, part in
                                    Button {
                                        withAnimation(.easeInOut) { proxy.scrollTo("part-\(index)", anchor: .top) }
                                    } label: {
                                        Text(part.section)
                                            .font(Typo.body(13, .semibold))
                                            .foregroundStyle(Palette.ink)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(Palette.card, in: Capsule())
                                            .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
                                    }
                                    .buttonStyle(PressStyle())
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.top, 14)
                    }

                    if parts.isEmpty {
                        Text("Aucun chant pour l'instant. Ajoute-les depuis « Gérer », sur l'accueil.")
                            .font(Typo.body(15))
                            .foregroundStyle(Palette.muted)
                            .padding(20)
                    }

                    ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                        VStack(alignment: .leading, spacing: 10) {
                            if !part.section.isEmpty {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(part.section.uppercased())
                                        .font(Typo.body(12, .bold, relativeTo: .caption))
                                        .tracking(1.1)
                                        .foregroundStyle(Palette.accent)
                                    Spacer()
                                    Text("\(part.songs.count)")
                                        .font(Typo.body(12, .semibold, relativeTo: .caption))
                                        .foregroundStyle(Palette.muted)
                                }
                                .padding(.horizontal, 6)
                            }
                            VStack(spacing: 0) {
                                ForEach(Array(part.songs.enumerated()), id: \.element.id) { row, song in
                                    if row > 0 { Hairline().padding(.leading, 18) }
                                    SongRow(song: song,
                                            isOpen: opened.contains(song.id),
                                            toggle: { toggle(song.id) },
                                            zoom: { zoomed = ZoomTarget(name: $0) },
                                            edit: { editing = SongRef(id: song.id) })
                                        .id(song.id)
                                }
                            }
                            .card()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                        .id("part-\(index)")
                    }
                }
                .padding(.bottom, 48)
            }
            .onAppear {
                guard let focus, !opened.contains(focus) else { return }
                opened.insert(focus)
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    withAnimation(.easeInOut) { proxy.scrollTo(focus, anchor: .top) }
                }
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(period?.name ?? "")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $editing) { SongEditor(songID: $0.id).environment(library) }
        .fullScreenCover(item: $zoomed) { ZoomView(name: $0.name) }
    }

    private func toggle(_ id: UUID) {
        withAnimation(.snappy(duration: 0.25)) {
            if opened.contains(id) { opened.remove(id) } else { opened.insert(id) }
        }
    }

    private func summary(_ period: Period?, parts: [(section: String, songs: [Song])]) -> String {
        let count = period?.songs.count ?? 0
        let chants = count == 1 ? "1 chant" : "\(count) chants"
        let named = parts.filter { !$0.section.isEmpty }.count
        return named > 1 ? "\(chants) · \(named) parties" : chants
    }
}

/// One chant, folded. Unfolded: its sheets (touch one to zoom), its words, and a way to change it.
struct SongRow: View {
    let song: Song
    let isOpen: Bool
    let toggle: () -> Void
    let zoom: (String) -> Void
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Text(song.title)
                        .font(Typo.body(16, .semibold))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !song.images.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "music.note")
                            if song.images.count > 1 { Text("\(song.images.count)") }
                        }
                        .font(Typo.body(12, .bold, relativeTo: .caption))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Palette.accentSoft, in: Capsule())
                        .accessibilityLabel(song.images.count == 1 ? "1 feuille" : "\(song.images.count) feuilles")
                    }
                    if !song.text.isEmpty {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                            .accessibilityLabel("paroles")
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 15)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityHint(isOpen ? "Replier" : "Déplier")

            if isOpen {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(song.images, id: \.self) { name in
                        if let image = UIImage(contentsOfFile: Library.imageURL(name).path) {
                            Button { zoom(name) } label: {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.line, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Feuille de \(song.title), toucher pour agrandir")
                        }
                    }
                    if !song.text.isEmpty {
                        Text(song.text)
                            .font(Typo.body(17))
                            .lineSpacing(7)
                            .foregroundStyle(Palette.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(Palette.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    HStack {
                        if song.images.isEmpty && song.text.isEmpty {
                            Text("Pas encore de feuille.")
                                .font(Typo.body(14))
                                .foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Button(action: edit) {
                            Label(song.images.isEmpty && song.text.isEmpty ? "Ajouter la feuille" : "Modifier",
                                  systemImage: song.images.isEmpty && song.text.isEmpty ? "plus" : "pencil")
                                .font(Typo.body(14, .semibold))
                                .foregroundStyle(Palette.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Palette.accentSoft, in: Capsule())
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
                .transition(.opacity)
            }
        }
    }
}

struct ZoomTarget: Identifiable {
    let name: String
    var id: String { name }
}

/// A sheet in full screen: pinch to zoom, drag to move.
struct ZoomView: View {
    let name: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let image = UIImage(contentsOfFile: Library.imageURL(name).path) {
                ZoomableImage(image: image)
                    .ignoresSafeArea()
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.5))
                    .padding(16)
            }
            .accessibilityLabel("Fermer")
        }
    }
}

struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
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
            view.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])
        context.coordinator.imageView = view
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    }
}

import SwiftUI

/// A period: its chants, folded. Touch one to unfold its hazzat sheets.
struct PeriodView: View {
    @Environment(Library.self) private var library
    let periodID: UUID

    var body: some View {
        let period = library.period(periodID)
        List {
            if period?.songs.isEmpty ?? true {
                ContentUnavailableView("Aucun chant", systemImage: "music.note",
                                       description: Text("Ajoute des chants depuis « Gérer », sur l'accueil."))
            }
            ForEach(Array((period?.parts ?? []).enumerated()), id: \.offset) { _, part in
                Section {
                    ForEach(part.songs) { SongDisclosure(song: $0, subtitle: nil) }
                } header: {
                    if !part.section.isEmpty {
                        Text(part.section)
                            .font(.headline)
                            .foregroundStyle(Palette.burgundy)
                            .textCase(nil)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.parchment.ignoresSafeArea())
        .navigationTitle(period?.name ?? "")
        .navigationBarTitleDisplayMode(.large)
    }
}

/// One folded chant. Unfolded: its sheets (touch one to zoom) and its words in franco.
struct SongDisclosure: View {
    let song: Song
    let subtitle: String?
    @State private var isOpen = false
    @State private var zoomed: ZoomTarget?

    var body: some View {
        DisclosureGroup(isExpanded: $isOpen) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(song.images, id: \.self) { name in
                    if let image = UIImage(contentsOfFile: Library.imageURL(name).path) {
                        Button { zoomed = ZoomTarget(name: name) } label: {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Feuille de \(song.title), toucher pour agrandir")
                    }
                }
                if !song.text.isEmpty {
                    Text(song.text)
                        .font(.system(size: 19))
                        .lineSpacing(6)
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if song.images.isEmpty && song.text.isEmpty {
                    Text("Rien encore pour ce chant. Ajoute la feuille ou le texte depuis « Gérer ».")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 12))
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(song.title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    if song.done {
                        Text("✅").font(.footnote).accessibilityLabel("coché")
                    }
                    if !song.images.isEmpty {
                        Image(systemName: "photo")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("feuille")
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
        }
        .fullScreenCover(item: $zoomed) { target in
            ZoomView(name: target.name)
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

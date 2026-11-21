import SwiftUI
import PhotosUI

struct SongRef: Identifiable {
    let id: UUID
}

/// Everything about one chant: name, period and part, the sheets (add many, reorder, remove), the words.
/// Every change is saved at once.
struct SongEditor: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    let songID: UUID
    @State private var draft = Song(title: "")
    @State private var periodID = UUID()
    @State private var loaded = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var scanning = false
    @State private var writing: TextDraft?

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom") {
                    TextField("Nom du chant", text: $draft.title)
                }
                Section {
                    Picker("Période", selection: $periodID) {
                        ForEach(library.periods) { Text($0.name).tag($0.id) }
                    }
                    HStack {
                        TextField("Partie (ex. Messe, Franco)", text: $draft.section)
                        let names = library.period(periodID)?.sectionNames ?? []
                        if !names.isEmpty {
                            Menu {
                                Button("Aucune") { draft.section = "" }
                                ForEach(names, id: \.self) { name in Button(name) { draft.section = name } }
                            } label: {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Palette.iconOn)
                            }
                            .accessibilityLabel("Choisir une partie existante")
                        }
                    }
                } header: {
                    Text("Rangement")
                } footer: {
                    Text("Un chant changé de période va à la fin de cette période.")
                }
                Section {
                    ForEach(Array(draft.images.enumerated()), id: \.element) { index, name in
                        HStack(spacing: 14) {
                            if let image = Images.image(name, maxPixel: 240) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 56, height: 72, alignment: .top)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            Text("Feuille \(index + 1)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                        }
                    }
                    .onMove { draft.images.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { offsets in
                        for i in offsets { library.removeImageFile(draft.images[i]) }
                        draft.images.remove(atOffsets: offsets)
                    }
                    let addTitle = importing ? "Ajout en cours…" : "Ajouter des photos (plusieurs d'un coup)"
                    PhotosPicker(selection: $picked, maxSelectionCount: 30, selectionBehavior: .ordered, matching: .images) {
                        Label(addTitle, systemImage: "photo.on.rectangle")
                            .foregroundStyle(Palette.ink)
                    }
                    .disabled(importing)
                    if DocumentScanner.isAvailable {
                        Button { scanning = true } label: {
                            Label("Scanner des feuilles", systemImage: "doc.viewfinder")
                                .foregroundStyle(Palette.ink)
                        }
                    }
                } header: {
                    Text("Feuilles de hazzat")
                } footer: {
                    Text("Elles s'affichent dans cet ordre et défilent de gauche à droite. « Modifier » en haut pour changer l'ordre ; glisse vers la gauche pour en retirer une.")
                }
                Section {
                    ForEach(draft.texts) { text in
                        Button { writing = TextDraft(songID: songID, text: text, isNew: false) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(text.language.label)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Palette.ink)
                                Text(text.body)
                                    .font(Typo.text(text.language, size: 13))
                                    .foregroundStyle(Palette.muted)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .onMove { draft.texts.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { draft.texts.remove(atOffsets: $0) }
                    Menu {
                        ForEach(TextLanguage.allCases, id: \.self) { language in
                            Button(language.label) {
                                writing = TextDraft(songID: songID, text: SongText(language: language), isNew: true)
                            }
                        }
                    } label: {
                        Label("Ajouter un texte (copte, franco, arabe, français)", systemImage: "text.alignleft")
                            .foregroundStyle(Palette.ink)
                    }
                } header: {
                    Text("Textes")
                } footer: {
                    Text("Autant de textes que tu veux. Ils s'affichent en onglets sur la page du chant.")
                }
                Section {
                    Toggle("Dans mes favoris", isOn: $draft.favorite)
                        .tint(Palette.accent)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("Modifier le chant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton().foregroundStyle(Palette.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") { dismiss() }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Palette.accent)
                }
            }
            .onAppear {
                guard !loaded, let song = library.song(songID), let pid = library.periodID(ofSong: songID) else { return }
                draft = song
                periodID = pid
                loaded = true
            }
            .onChange(of: draft) { _, _ in persist() }
            .onChange(of: periodID) { _, _ in persist() }
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                importing = true
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let name = library.storeImage(data) {
                            draft.images.append(name)
                        }
                    }
                    picked = []
                    importing = false
                }
            }
            .sheet(item: $writing, onDismiss: {
                // The text was saved in the library: take it back so that this screen does not overwrite it.
                if let saved = library.song(songID) { draft.texts = saved.texts }
            }) { draft in
                TextEditorSheet(songID: draft.songID, text: draft.text, isNew: draft.isNew).environment(library)
            }
            .fullScreenCover(isPresented: $scanning) {
                DocumentScanner { images in
                    scanning = false
                    draft.images += images.compactMap { library.storeImage($0) }
                }
                .ignoresSafeArea()
            }
        }
    }

    private func persist() {
        guard loaded, !draft.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        library.update(draft, in: periodID)
    }
}

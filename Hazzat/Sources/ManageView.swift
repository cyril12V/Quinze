import SwiftUI
import PhotosUI

/// « Gérer » : the same list, but everything can be renamed, moved, added or removed.
struct ManageView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var askName = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(library.periods) { period in
                        NavigationLink(value: period.id) {
                            HStack {
                                Text(period.name).font(.headline)
                                Spacer()
                                Text("\(period.songs.count)").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onMove { library.movePeriods(from: $0, to: $1) }
                    .onDelete { library.deletePeriods(at: $0) }
                } header: {
                    Text("Périodes")
                } footer: {
                    Text("Appui long puis glisse pour changer l'ordre. Glisse vers la gauche pour supprimer.")
                }
                Button {
                    newName = ""
                    askName = true
                } label: {
                    Label("Nouvelle période", systemImage: "plus.circle.fill")
                }
            }
            .navigationTitle("Gérer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) { Button("OK") { dismiss() }.bold() }
            }
            .navigationDestination(for: UUID.self) { ManagePeriodView(periodID: $0) }
            .alert("Nouvelle période", isPresented: $askName) {
                TextField("Nom (ex. Kiahk)", text: $newName)
                Button("Ajouter") { library.addPeriod(named: newName) }
                Button("Annuler", role: .cancel) {}
            }
        }
    }
}

struct ManagePeriodView: View {
    @Environment(Library.self) private var library
    let periodID: UUID
    @State private var name = ""
    @State private var newTitle = ""
    @State private var askTitle = false
    @State private var edited: SongRef?

    var body: some View {
        let songs = library.period(periodID)?.songs ?? []
        List {
            Section("Nom de la période") {
                TextField("Nom", text: $name)
                    .onSubmit { library.renamePeriod(periodID, to: name) }
                    .onChange(of: name) { _, value in library.renamePeriod(periodID, to: value) }
            }
            Section {
                ForEach(songs) { song in
                    Button { edited = SongRef(id: song.id) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title).foregroundStyle(Palette.ink)
                                Text(summary(song)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "pencil").foregroundStyle(.secondary)
                        }
                    }
                }
                .onMove { library.moveSongs(from: $0, to: $1, in: periodID) }
                .onDelete { library.deleteSongs(at: $0, in: periodID) }
            } header: {
                Text("Chants")
            } footer: {
                Text("Touche un chant pour changer son nom, sa feuille ou sa période.")
            }
            Button {
                newTitle = ""
                askTitle = true
            } label: {
                Label("Nouveau chant", systemImage: "plus.circle.fill")
            }
        }
        .navigationTitle(library.period(periodID)?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onAppear { name = library.period(periodID)?.name ?? "" }
        .alert("Nouveau chant", isPresented: $askTitle) {
            TextField("Nom du chant", text: $newTitle)
            Button("Ajouter") {
                if let id = library.addSong(titled: newTitle, to: periodID) { edited = SongRef(id: id) }
            }
            Button("Annuler", role: .cancel) {}
        }
        .sheet(item: $edited) { SongEditor(songID: $0.id) }
    }

    private func summary(_ song: Song) -> String {
        var parts: [String] = []
        if song.done { parts.append("✅") }
        if !song.section.isEmpty { parts.append(song.section) }
        if !song.images.isEmpty { parts.append(song.images.count == 1 ? "1 feuille" : "\(song.images.count) feuilles") }
        if !song.text.isEmpty { parts.append("texte") }
        return parts.isEmpty ? "Pas encore de feuille" : parts.joined(separator: " · ")
    }
}

struct SongRef: Identifiable {
    let id: UUID
}

/// Editing one chant: name, period, kind, sheets, words. Every change is saved at once.
struct SongEditor: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    let songID: UUID
    @State private var draft = Song(title: "")
    @State private var periodID = UUID()
    @State private var loaded = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var importing = false

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
                            }
                            .accessibilityLabel("Choisir une partie existante")
                        }
                    }
                    Toggle("✅ Coché", isOn: $draft.done)
                } header: {
                    Text("Rangement")
                } footer: {
                    Text("La partie regroupe les chants dans la période (Messe, Tasbeha, Franco…). L'ordre se change dans la liste de la période.")
                }
                Section {
                    ForEach(draft.images, id: \.self) { name in
                        if let image = UIImage(contentsOfFile: Library.imageURL(name).path) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 180)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .onMove { draft.images.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { offsets in
                        for i in offsets { library.removeImageFile(draft.images[i]) }
                        draft.images.remove(atOffsets: offsets)
                    }
                    PhotosPicker(selection: $picked, matching: .images) {
                        Label(importing ? "Ajout en cours…" : "Ajouter des feuilles (photos)", systemImage: "photo.badge.plus")
                    }
                    .disabled(importing)
                } header: {
                    Text("Feuilles de hazzat")
                } footer: {
                    Text("Les photos sont copiées dans l'app : elles restent même sans internet. Glisse vers la gauche pour en retirer une.")
                }
                Section("Paroles (franco)") {
                    TextEditor(text: $draft.text)
                        .frame(minHeight: 220)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Modifier le chant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) { Button("OK") { dismiss() }.bold() }
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
        }
    }

    private func persist() {
        guard loaded, !draft.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        library.update(draft, in: periodID)
    }
}

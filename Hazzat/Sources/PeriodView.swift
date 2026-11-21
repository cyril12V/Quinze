import SwiftUI

/// A period (category): its parts and chants. Everything can be changed here: add, rename, move, delete.
struct PeriodView: View {
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    let periodID: UUID

    @State private var editing = false
    @State private var selection = Set<UUID>()
    @State private var ask: Ask?
    @State private var field1 = ""
    @State private var field2 = ""
    @State private var danger: Danger?
    @State private var edited: SongRef?

    /// A name to type.
    enum Ask: Identifiable {
        case renamePeriod
        case newSong(part: Int?)
        case newPart
        case renamePart(Int)
        case renameSong(UUID)

        var id: String {
            switch self {
            case .renamePeriod: "period"
            case .newSong(let part): "song-\(part ?? -1)"
            case .newPart: "part"
            case .renamePart(let i): "rename-part-\(i)"
            case .renameSong(let id): "rename-\(id)"
            }
        }

        var title: String {
            switch self {
            case .renamePeriod: "Renommer la période"
            case .newSong: "Nouveau chant"
            case .newPart: "Nouvelle partie"
            case .renamePart: "Renommer la partie"
            case .renameSong: "Renommer le chant"
            }
        }
    }

    /// Something to delete, asked first.
    enum Danger: Identifiable {
        case period(String, Int)
        case part(Int, String, Int)
        case songs(Set<UUID>, String)

        var id: String {
            switch self {
            case .period: "period"
            case .part(let i, _, _): "part-\(i)"
            case .songs(let ids, _): "songs-\(ids.count)-\(ids.first?.uuidString ?? "")"
            }
        }

        var title: String {
            switch self {
            case .period(let name, _): "Supprimer « \(name) » ?"
            case .part(_, let name, _): "Supprimer la partie « \(name) » ?"
            case .songs(_, let label): "Supprimer \(label) ?"
            }
        }

        var message: String {
            switch self {
            case .period(_, let count): "Ses \(count) chants et toutes leurs feuilles seront effacés du téléphone."
            case .part(_, _, let count): "Elle contient \(count) chant\(count > 1 ? "s" : "")."
            case .songs: "Les feuilles de hazzat et les paroles seront effacées du téléphone."
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar {
                if editing {
                    Button("OK") {
                        withAnimation { editing = false }
                        selection = []
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Palette.accent)
                    .padding(.trailing, 6)
                } else {
                    MoreMenu { periodMenu }
                }
            }
            if let period = library.period(periodID) {
                list(period)
            } else {
                Spacer()
            }
        }
        .background(Palette.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if editing { bulkBar }
        }
        .alert(ask?.title ?? "", isPresented: Binding(get: { ask != nil }, set: { if !$0 { ask = nil } }), presenting: ask) { kind in
            switch kind {
            case .newPart:
                TextField("Nom de la partie (ex. Messe)", text: $field1)
                TextField("Premier chant", text: $field2)
            case .newSong:
                TextField("Nom du chant", text: $field1)
            default:
                TextField("Nom", text: $field1)
            }
            Button("OK") { apply(kind) }
            Button("Annuler", role: .cancel) {}
        }
        .confirmationDialog(danger?.title ?? "",
                            isPresented: Binding(get: { danger != nil }, set: { if !$0 { danger = nil } }),
                            titleVisibility: .visible,
                            presenting: danger) { item in
            switch item {
            case .period:
                Button("Supprimer la période", role: .destructive) {
                    dismiss()
                    library.deletePeriod(periodID)
                }
            case .part(let index, _, _):
                Button("Supprimer la partie et ses chants", role: .destructive) {
                    library.deletePart(of: periodID, at: index, keepSongs: false)
                }
                Button("Garder les chants (sans partie)") {
                    library.deletePart(of: periodID, at: index, keepSongs: true)
                }
            case .songs(let ids, _):
                Button("Supprimer", role: .destructive) {
                    library.deleteSongs(ids)
                    selection.subtract(ids)
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: { item in
            Text(item.message)
        }
        .sheet(item: $edited) { SongEditor(songID: $0.id).environment(library) }
    }

    // MARK: List

    private func list(_ period: Period) -> some View {
        let ranges = period.partRanges
        return List(selection: $selection) {
            VStack(alignment: .leading, spacing: 4) {
                Text(period.name)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text(summary(period, parts: ranges.count))
                    .font(Typo.caption)
                    .foregroundStyle(Palette.muted)
                if editing {
                    Text("Coche des chants pour les déplacer ou les supprimer. Glisse ≡ pour changer l'ordre.")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.accent)
                        .padding(.top, 6)
                }
            }
            .padding(.bottom, 6)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 24, bottom: 4, trailing: 24))
            .selectionDisabled()

            if period.songs.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Aucun chant pour l'instant.")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.muted)
                    SmallButton("Ajouter un chant") { start(.newSong(part: nil)) }
                }
                .padding(.top, 20)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                .selectionDisabled()
            }

            ForEach(Array(ranges.enumerated()), id: \.offset) { index, part in
                Section {
                    ForEach(period.songs[part.range]) { song in
                        NavigationLink(value: Route.song(song.id)) {
                            SongRow(song: song, period: period.name)
                        }
                        .tag(song.id)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 7, leading: 24, bottom: 7, trailing: 18))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                danger = .songs([song.id], "« \(song.title) »")
                            } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                            Button { start(.renameSong(song.id), text: song.title) } label: {
                                Label("Renommer", systemImage: "pencil")
                            }
                            .tint(Color(hex: 0x8E8E93))
                        }
                        .swipeActions(edge: .leading) {
                            Button { library.toggleFavorite(song.id) } label: {
                                Label(song.favorite ? "Retirer" : "Favori",
                                      systemImage: song.favorite ? "bookmark.slash.fill" : "bookmark.fill")
                            }
                            .tint(Palette.accent)
                        }
                        .contextMenu { songMenu(song) }
                    }
                    .onMove { library.moveSongs(inPart: index, of: periodID, from: $0, to: $1) }
                } header: {
                    partHeader(index: index, section: part.section, count: part.range.count, parts: ranges.count)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(editing ? .active : .inactive))
    }

    @ViewBuilder
    private func partHeader(index: Int, section: String, count: Int, parts: Int) -> some View {
        if section.isEmpty && parts == 1 {
            EmptyView()
        } else {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.isEmpty ? "Sans partie" : section)
                        .font(Typo.sectionTitle)
                        .foregroundStyle(section.isEmpty ? Palette.muted : Palette.ink)
                    Text(count == 1 ? "1 chant" : "\(count) chants")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
                Menu {
                    Button { start(.newSong(part: index)) } label: {
                        Label("Ajouter un chant ici", systemImage: "plus")
                    }
                    Button { start(.renamePart(index), text: section) } label: {
                        Label("Renommer la partie", systemImage: "pencil")
                    }
                    Button { library.movePart(of: periodID, at: index, by: -1) } label: {
                        Label("Monter", systemImage: "arrow.up")
                    }
                    .disabled(index == 0)
                    Button { library.movePart(of: periodID, at: index, by: 1) } label: {
                        Label("Descendre", systemImage: "arrow.down")
                    }
                    .disabled(index == parts - 1)
                    Divider()
                    Button(role: .destructive) {
                        danger = .part(index, section.isEmpty ? "Sans partie" : section, count)
                    } label: {
                        Label("Supprimer la partie", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Palette.iconOn)
                        .frame(width: 40, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Actions de la partie")
            }
            .padding(.top, 20)
            .padding(.bottom, 4)
            .padding(.horizontal, 24)
            .padding(.trailing, -10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .listRowInsets(EdgeInsets())
            .textCase(nil)
        }
    }

    // MARK: Menus

    @ViewBuilder
    private var periodMenu: some View {
        Button { start(.newSong(part: nil)) } label: { Label("Ajouter un chant", systemImage: "plus") }
        Button { start(.newPart) } label: { Label("Ajouter une partie", systemImage: "rectangle.stack.badge.plus") }
        Button {
            withAnimation { editing = true }
        } label: {
            Label("Sélectionner, déplacer…", systemImage: "checkmark.circle")
        }
        Button { start(.renamePeriod, text: library.period(periodID)?.name ?? "") } label: {
            Label("Renommer la période", systemImage: "pencil")
        }
        Divider()
        Button(role: .destructive) {
            if let period = library.period(periodID) { danger = .period(period.name, period.songs.count) }
        } label: {
            Label("Supprimer la période", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func songMenu(_ song: Song) -> some View {
        Button { library.toggleFavorite(song.id) } label: {
            Label(song.favorite ? "Retirer des favoris" : "Ajouter aux favoris",
                  systemImage: song.favorite ? "bookmark.slash" : "bookmark")
        }
        Button { start(.renameSong(song.id), text: song.title) } label: { Label("Renommer", systemImage: "pencil") }
        Button { edited = SongRef(id: song.id) } label: {
            Label("Feuilles, paroles, partie…", systemImage: "slider.horizontal.3")
        }
        Divider()
        Button(role: .destructive) { danger = .songs([song.id], "« \(song.title) »") } label: {
            Label("Supprimer", systemImage: "trash")
        }
    }

    /// Bottom bar while editing: select all, move, delete.
    private var bulkBar: some View {
        let all = Set(library.period(periodID)?.songs.map(\.id) ?? [])
        let count = selection.count
        return HStack(spacing: 12) {
            Button(selection == all && !all.isEmpty ? "Aucun" : "Tout") {
                selection = selection == all ? [] : all
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Palette.ink)
            Spacer()
            Menu {
                ForEach(library.periods) { target in
                    Menu(target.name) {
                        Button("Sans partie") { move(to: target.id, section: "") }
                        ForEach(target.sectionNames, id: \.self) { name in
                            Button(name) { move(to: target.id, section: name) }
                        }
                    }
                }
            } label: {
                Text("Déplacer")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(count == 0 ? Palette.iconOff : Palette.ink)
            }
            .disabled(count == 0)
            SmallButton(count == 0 ? "Supprimer" : "Supprimer (\(count))") {
                guard count > 0 else { return }
                danger = .songs(selection, count == 1 ? "1 chant" : "\(count) chants")
            }
            .opacity(count == 0 ? 0.4 : 1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color.white.shadow(.drop(color: .black.opacity(0.06), radius: 12, x: 0, y: -2)))
    }

    // MARK: Actions

    private func start(_ kind: Ask, text: String = "") {
        field1 = text
        field2 = ""
        ask = kind
    }

    private func apply(_ kind: Ask) {
        switch kind {
        case .renamePeriod:
            library.renamePeriod(periodID, to: field1)
        case .newSong(let part):
            if let id = library.addSong(titled: field1, to: periodID, inPart: part) { router.open(.song(id)) }
        case .newPart:
            let first = field2.trimmingCharacters(in: .whitespaces).isEmpty ? "Nouveau chant" : field2
            library.addPart(named: field1, firstSong: first, to: periodID)
        case .renamePart(let index):
            library.renamePart(of: periodID, at: index, to: field1)
        case .renameSong(let id):
            library.renameSong(id, to: field1)
        }
    }

    private func move(to target: UUID, section: String) {
        library.moveSongs(selection, to: target, section: section)
        selection = []
    }

    private func summary(_ period: Period, parts: Int) -> String {
        let count = period.songs.count
        let chants = count == 1 ? "1 chant" : "\(count) chants"
        let named = period.partRanges.filter { !$0.section.isEmpty }.count
        return named > 0 ? "\(chants) · \(parts) parties" : chants
    }
}

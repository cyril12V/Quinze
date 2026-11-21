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
        case newGroup

        var id: String {
            switch self {
            case .renamePeriod: "period"
            case .newSong(let part): "song-\(part ?? -1)"
            case .newPart: "part"
            case .renamePart(let i): "rename-part-\(i)"
            case .renameSong(let id): "rename-\(id)"
            case .newGroup: "group"
            }
        }

        var title: String {
            switch self {
            case .renamePeriod: "Renommer la période"
            case .newSong: "Nouveau chant"
            case .newPart: "Nouvelle partie"
            case .renamePart: "Renommer la partie"
            case .renameSong: "Renommer le chant"
            case .newGroup: "Nouveau groupe"
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
                    HStack(spacing: 0) {
                        Button("Modifier") { withAnimation { editing = true } }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .padding(.trailing, 2)
                        MoreMenu { periodMenu }
                    }
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
            case .newGroup:
                TextField("Nom du groupe (ex. Messe)", text: $field1)
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
                    Text("Maintiens ≡ et glisse un chant où tu veux, même dans une autre partie. Coche des chants pour les déplacer vers une autre période ou les supprimer.")
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

            if editing {
                // One list for the whole period: a chant can be dragged anywhere, even into another part
                // (it takes the part it lands in). Part titles stay in place.
                let rows = EditRow.rows(period)
                ForEach(rows) { row in
                    switch row {
                    case .header(_, let section):
                        Text(section.isEmpty ? "Sans partie" : section)
                            .font(Typo.sectionTitle)
                            .foregroundStyle(section.isEmpty ? Palette.muted : Palette.ink)
                            .padding(.top, 14)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 24, bottom: 2, trailing: 18))
                            .moveDisabled(true)
                            .selectionDisabled()
                    case .song(let song):
                        songRow(song, period: period)
                    }
                }
                .onMove { source, destination in
                    var moved = rows
                    moved.move(fromOffsets: source, toOffset: destination)
                    library.reorder(periodID, to: EditRow.order(moved))
                }
            } else {
            ForEach(Array(ranges.enumerated()), id: \.offset) { index, part in
                Section {
                    Group {
                        ForEach(RowItem.items(period.songs[part.range])) { item in
                            switch item {
                            case .single(let song):
                                songRow(song, period: period)
                            case .series(let base, let songs):
                                SeriesRow(base: base, songs: songs, period: period.name) { router.open(.song($0)) }
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 7, leading: 24, bottom: 7, trailing: 18))
                                    .selectionDisabled()
                            }
                        }
                    }
                } header: {
                    partHeader(index: index, section: part.section, count: part.range.count, parts: ranges.count)
                }
            }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(editing ? .active : .inactive))
    }

    private func songRow(_ song: Song, period: Period) -> some View {
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
        Menu {
            let current = library.period(periodID)?.group ?? ""
            Button { library.setGroup(of: periodID, to: "") } label: {
                if current.isEmpty { Label("Aucun groupe", systemImage: "checkmark") } else { Text("Aucun groupe") }
            }
            ForEach(library.groupNames, id: \.self) { group in
                Button { library.setGroup(of: periodID, to: group) } label: {
                    if current == group { Label(group, systemImage: "checkmark") } else { Text(group) }
                }
            }
            Button { start(.newGroup) } label: { Label("Nouveau groupe…", systemImage: "plus") }
        } label: {
            Label("Ranger dans un groupe", systemImage: "square.stack")
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
        case .newGroup:
            library.setGroup(of: periodID, to: field1)
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

/// In a part, chants numbered one after the other (« Doxologie 1, 2, 3… ») are shown as one row.
enum RowItem: Identifiable {
    case single(Song)
    case series(String, [Song])

    var id: UUID {
        switch self {
        case .single(let song): song.id
        case .series(_, let songs): songs[0].id
        }
    }

    /// « Doxologie 4 » → (« Doxologie », 4)
    static func numbered(_ title: String) -> (base: String, number: Int)? {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let digits = String(trimmed.reversed().prefix { $0.isASCII && $0.isNumber }.reversed())
        guard !digits.isEmpty, digits.count < trimmed.count, let number = Int(digits) else { return nil }
        let base = String(trimmed.dropLast(digits.count)).trimmingCharacters(in: .whitespaces)
        return base.isEmpty ? nil : (base, number)
    }

    static func items(_ songs: ArraySlice<Song>) -> [RowItem] {
        var out: [RowItem] = []
        var run: [Song] = []
        var runBase = ""
        func flush() {
            if run.count >= 3 {
                out.append(.series(runBase, run))
            } else {
                out += run.map { .single($0) }
            }
            run = []
        }
        for song in songs {
            if let hit = numbered(song.title) {
                if !run.isEmpty && hit.base.lowercased() != runBase.lowercased() { flush() }
                if run.isEmpty { runBase = hit.base }
                run.append(song)
            } else {
                flush()
                out.append(.single(song))
            }
        }
        flush()
        return out
    }
}

/// « Doxologie » with its numbers side by side: touch a number to open that one.
struct SeriesRow: View {
    let base: String
    let songs: [Song]
    let period: String
    let open: (UUID) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Cover(content: .song(songs.first(where: { !$0.images.isEmpty }) ?? songs[0], period: period), size: 48, radius: 10)
            VStack(alignment: .leading, spacing: 8) {
                Text(base)
                    .font(Typo.name)
                    .foregroundStyle(Palette.ink)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(songs) { song in
                            Button { open(song.id) } label: {
                                Text(RowItem.numbered(song.title).map { "\($0.number)" } ?? song.title)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(song.images.isEmpty ? Palette.ink : .white)
                                    .frame(minWidth: 34, minHeight: 30)
                                    .padding(.horizontal, 4)
                                    .background(song.images.isEmpty ? Palette.line : Palette.ink,
                                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(song.title)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

/// The period while editing: part titles and chants in one list, so that a chant can go anywhere.
enum EditRow: Identifiable {
    case header(Int, String)
    case song(Song)

    var id: String {
        switch self {
        case .header(let index, _): "part-\(index)"
        case .song(let song): song.id.uuidString
        }
    }

    static func rows(_ period: Period) -> [EditRow] {
        var rows: [EditRow] = []
        for (index, part) in period.partRanges.enumerated() {
            rows.append(.header(index, part.section))
            rows += period.songs[part.range].map { EditRow.song($0) }
        }
        return rows
    }

    /// Each chant with the part of the title above it.
    static func order(_ rows: [EditRow]) -> [(id: UUID, section: String)] {
        var section: String = {
            for row in rows { if case .header(_, let name) = row { return name } }
            return ""
        }()
        var out: [(id: UUID, section: String)] = []
        for row in rows {
            switch row {
            case .header(_, let name): section = name
            case .song(let song): out.append((song.id, section))
            }
        }
        return out
    }
}

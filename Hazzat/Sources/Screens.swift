import SwiftUI
import PhotosUI

// MARK: - Bibliothèque

/// Every period, in the order of the Coptic year (Nayrouz first); the masses under one « Messe » card.
/// « Modifier » to reorder or delete; « + » to add a period.
struct LibraryView: View {
    @Environment(Library.self) private var library
    @State private var editing = false
    @State private var askNew = false
    @State private var renaming: Period?
    @State private var deleting: Period?
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Bibliothèque")
                    .font(Typo.screenTitle)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Button(editing ? "OK" : "Modifier") { withAnimation { editing.toggle() } }
                    .font(.system(size: 15, weight: editing ? .bold : .semibold))
                    .foregroundStyle(editing ? Palette.accent : Palette.ink)
                    .padding(.trailing, 4)
                IconButton(systemName: "plus", label: "Nouvelle période", size: 20) {
                    name = ""
                    askNew = true
                }
            }
            .padding(.leading, 24)
            .padding(.trailing, 16)
            .padding(.top, 10)
            Text(summary)
                .font(Typo.caption)
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 24)
                .padding(.top, 2)
                .padding(.bottom, 10)
            List {
                ForEach(library.shelf) { item in
                    switch item {
                    case .period(let period):
                        PeriodListRow(period: period)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { deleting = period } label: { Label("Supprimer", systemImage: "trash") }
                                Button {
                                    name = period.name
                                    renaming = period
                                } label: { Label("Renommer", systemImage: "pencil") }
                                .tint(Color(hex: 0x8E8E93))
                            }
                    case .group(let group, let members):
                        NavigationLink(value: Route.group(group)) {
                            HStack(spacing: 14) {
                                Cover(content: .group(group), size: 56, radius: 12)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(group)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Palette.ink)
                                    Text(members.map(\.name).joined(separator: " · "))
                                        .font(Typo.caption)
                                        .foregroundStyle(Palette.muted)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 7, leading: 24, bottom: 7, trailing: 18))
                    }
                }
                .onMove { library.moveShelf(from: $0, to: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(editing ? .active : .inactive))
        }
        .background(Palette.background)
        .toolbar(.hidden, for: .navigationBar)
        .tabBarRoom()
        .alert("Nouvelle période", isPresented: $askNew) {
            TextField("Nom (ex. Kiahk)", text: $name)
            Button("Ajouter") { library.addPeriod(named: name) }
            Button("Annuler", role: .cancel) {}
        }
        .periodDialogs(renaming: $renaming, deleting: $deleting, name: $name)
    }

    private var summary: String {
        let songs = library.periods.reduce(0) { $0 + $1.songs.count }
        return "\(library.periods.count) périodes · \(songs) chants · dans l'ordre de l'année copte"
    }
}

/// The periods of a group (the masses: saint Basile, saint Grégoire, saint Cyrille…).
struct GroupView: View {
    @Environment(Library.self) private var library
    let name: String
    @State private var editing = false
    @State private var askNew = false
    @State private var renaming: Period?
    @State private var deleting: Period?
    @State private var newName = ""

    var body: some View {
        let members = library.members(of: name)
        VStack(alignment: .leading, spacing: 0) {
            TopBar {
                HStack(spacing: 2) {
                    Button(editing ? "OK" : "Modifier") { withAnimation { editing.toggle() } }
                        .font(.system(size: 15, weight: editing ? .bold : .semibold))
                        .foregroundStyle(editing ? Palette.accent : Palette.ink)
                    IconButton(systemName: "plus", label: "Ajouter dans \(name)", size: 20) {
                        newName = ""
                        askNew = true
                    }
                }
            }
            HStack(spacing: 16) {
                Cover(content: .group(name), size: 72, radius: 14)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Text(members.count == 1 ? "1 période" : "\(members.count) périodes")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            List {
                ForEach(members) { period in
                    PeriodListRow(period: period)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { deleting = period } label: { Label("Supprimer", systemImage: "trash") }
                            Button {
                                newName = period.name
                                renaming = period
                            } label: { Label("Renommer", systemImage: "pencil") }
                            .tint(Color(hex: 0x8E8E93))
                        }
                }
                .onMove { library.moveInGroup(name, from: $0, to: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(editing ? .active : .inactive))
        }
        .background(Palette.background)
        .toolbar(.hidden, for: .navigationBar)
        .alert("Nouvelle période dans « \(name) »", isPresented: $askNew) {
            TextField("Nom", text: $newName)
            Button("Ajouter") { library.addPeriod(named: newName, inGroup: name) }
            Button("Annuler", role: .cancel) {}
        }
        .periodDialogs(renaming: $renaming, deleting: $deleting, name: $newName)
    }
}

/// A period in a list: its cover, its name, how many chants and parts.
struct PeriodListRow: View {
    let period: Period

    private var detail: String {
        let count = period.songs.count
        let chants = count == 0 ? "Aucun chant" : (count == 1 ? "1 chant" : "\(count) chants")
        let parts = period.partRanges.filter { !$0.section.isEmpty }.count
        return parts > 0 ? "\(chants) · \(parts) partie\(parts > 1 ? "s" : "")" : chants
    }

    var body: some View {
        NavigationLink(value: Route.period(period.id)) {
            HStack(spacing: 14) {
                Cover(content: .period(period), size: 56, radius: 12)
                VStack(alignment: .leading, spacing: 3) {
                    Text(period.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(Typo.caption)
                        .foregroundStyle(Palette.muted)
                }
            }
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 7, leading: 24, bottom: 7, trailing: 18))
    }
}

extension View {
    /// Rename and delete a period, with a confirmation before deleting.
    func periodDialogs(renaming: Binding<Period?>, deleting: Binding<Period?>, name: Binding<String>) -> some View {
        modifier(PeriodDialogs(renaming: renaming, deleting: deleting, name: name))
    }
}

struct PeriodDialogs: ViewModifier {
    @Environment(Library.self) private var library
    @Binding var renaming: Period?
    @Binding var deleting: Period?
    @Binding var name: String

    func body(content: Content) -> some View {
        content
            .alert("Renommer la période",
                   isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
                   presenting: renaming) { period in
                TextField("Nom", text: $name)
                Button("OK") { library.renamePeriod(period.id, to: name) }
                Button("Annuler", role: .cancel) {}
            }
            .confirmationDialog(deleting.map { "Supprimer « \($0.name) » ?" } ?? "",
                                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible,
                                presenting: deleting) { period in
                Button("Supprimer la période", role: .destructive) { library.deletePeriod(period.id) }
                Button("Annuler", role: .cancel) {}
            } message: { period in
                Text("Ses \(period.songs.count) chants et toutes leurs feuilles seront effacés du téléphone.")
            }
    }
}

// MARK: - Favoris

struct FavoritesView: View {
    @Environment(Library.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Favoris")
                .font(Typo.screenTitle)
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 24)
                .padding(.top, 14)
            Text(library.favorites.isEmpty ? "Tes chants marqués d'un signet" : "\(library.favorites.count) chants")
                .font(Typo.caption)
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 24)
                .padding(.top, 2)
                .padding(.bottom, 10)
            if library.favorites.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Palette.iconOff)
                    Text("Touche le signet d'un chant\npour le retrouver ici.")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(library.favorites) { entry in
                        NavigationLink(value: Route.song(entry.song.id)) {
                            SongRow(song: entry.song, period: entry.period.name, place: entry.place)
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 7, leading: 24, bottom: 7, trailing: 18))
                        .swipeActions {
                            Button { library.toggleFavorite(entry.song.id) } label: {
                                Label("Retirer", systemImage: "bookmark.slash.fill")
                            }
                            .tint(Palette.accent)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Palette.background)
        .toolbar(.hidden, for: .navigationBar)
        .tabBarRoom()
    }
}

// MARK: - Profil

/// Today in the Church, the profile photo, and the numbers of the library.
struct ProfileView: View {
    @Environment(Library.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @State private var day = LiturgicalDay()
    @State private var photo: PhotosPickerItem?
    @State private var confirmClear = false

    private var sheetsCount: Int {
        library.periods.reduce(0) { total, period in total + period.songs.reduce(0) { $0 + $1.images.count } }
    }

    private var withSheets: Int {
        library.periods.reduce(0) { total, period in total + period.songs.filter { !$0.images.isEmpty }.count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Profil")
                    .font(Typo.screenTitle)
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 14)
                HStack(spacing: 16) {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Avatar(size: 72)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(Palette.accent, in: Circle())
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            }
                    }
                    .accessibilityLabel("Changer la photo de profil")
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Mes chants")
                            .font(Typo.sectionTitle)
                            .foregroundStyle(Palette.ink)
                        Text("Tout est sur le téléphone, sans internet.")
                            .font(Typo.caption)
                            .foregroundStyle(Palette.muted)
                    }
                }
                .padding(.top, 22)

                Text("Aujourd'hui")
                    .font(Typo.sectionTitle)
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 36)
                VStack(spacing: 0) {
                    row("Jour", "\(day.tune.rawValue)\(day.tomorrowTune.map { " · demain \($0.rawValue)" } ?? "")")
                    row("Date copte", day.coptic.formatted)
                    row("Période", day.season)
                    if let fast = day.fast { row("Jeûne", fast) }
                    if let next = day.next {
                        row("Ensuite", next.days == 1 ? "\(next.season), demain" : "\(next.season), dans \(next.days) jours")
                    }
                }
                .padding(.top, 8)

                Text("Ma bibliothèque")
                    .font(Typo.sectionTitle)
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 36)
                HStack(spacing: 10) {
                    stat("\(library.periods.count)", "périodes")
                    stat("\(library.periods.reduce(0) { $0 + $1.songs.count })", "chants")
                    stat("\(withSheets)", "avec feuille")
                    stat("\(sheetsCount)", "photos")
                }
                .padding(.top, 14)

                Button { confirmClear = true } label: {
                    Text("Effacer le dernier chant ouvert")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                }
                .plainButton()
                .disabled(library.recentIDs.isEmpty)
                .opacity(library.recentIDs.isEmpty ? 0.4 : 1)
                .padding(.top, 36)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(Palette.background)
        .toolbar(.hidden, for: .navigationBar)
        .tabBarRoom()
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { library.setAvatar(data) }
                photo = nil
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { day = LiturgicalDay() }
        }
        .confirmationDialog("Effacer le dernier chant ouvert ?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Effacer", role: .destructive) { library.clearRecents() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Seule la carte du dernier chant ouvert disparaît de l'accueil. Tes chants et tes feuilles restent.")
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(Typo.caption).foregroundStyle(Palette.muted)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.ink)
            Text(label).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Recherche

struct SearchView: View {
    @Environment(Library.self) private var library
    @State private var query = ""
    @FocusState private var focused: Bool

    private var needle: String { HomeView.fold(query.trimmingCharacters(in: .whitespaces)) }

    private var hits: [Library.Entry] {
        guard !needle.isEmpty else { return [] }
        return library.periods.flatMap { period in
            period.songs
                .filter {
                    HomeView.fold($0.title).contains(needle) || HomeView.fold($0.text).contains(needle)
                        || HomeView.fold($0.section).contains(needle) || HomeView.fold(period.name).contains(needle)
                }
                .map { Library.Entry(song: $0, period: period) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar(caption: "Recherche")
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Palette.iconOn)
                TextField("", text: $query, prompt: Text("Chant, partie, paroles…").foregroundStyle(Palette.iconOff))
                    .font(.system(size: 16))
                    .foregroundStyle(Palette.ink)
                    .focused($focused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.iconOff)
                    }
                    .plainButton()
                    .accessibilityLabel("Effacer")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 4)
            .padding(.horizontal, 24)
            .padding(.top, 4)
            if !needle.isEmpty {
                Text(hits.isEmpty ? "Aucun chant trouvé" : (hits.count == 1 ? "1 chant" : "\(hits.count) chants"))
                    .font(Typo.caption)
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
            }
            List {
                ForEach(hits) { entry in
                    NavigationLink(value: Route.song(entry.song.id)) {
                        SongRow(song: entry.song, period: entry.period.name, place: entry.place)
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 7, leading: 24, bottom: 7, trailing: 18))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Palette.background)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { focused = true }
    }
}

import Foundation
import Observation
import UIKit

/// Language of a text: Coptic, franco (Coptic or Arabic written with French letters), Arabic, French.
enum TextLanguage: String, Codable, CaseIterable, Hashable, Sendable {
    case copte, franco, arabe, francais

    var label: String {
        switch self {
        case .copte: "Copte"
        case .franco: "Franco"
        case .arabe: "Arabe"
        case .francais: "Français"
        }
    }

    /// Arabic is written from right to left.
    var rightToLeft: Bool { self == .arabe }
}

/// One text of a chant, in one language.
struct SongText: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var language: TextLanguage
    var body: String

    init(language: TextLanguage, body: String = "") {
        self.language = language
        self.body = body
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        language = (try? c.decodeIfPresent(TextLanguage.self, forKey: .language)) ?? .franco
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
    }
}

/// One chant: its hazzat sheets (images kept on the phone) and its texts (copte, franco, arabe, français).
struct Song: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var title: String
    /// Part of the period it belongs to (« Messe », « Tasbeha semaine », « Franco »…); empty for none.
    var section = ""
    /// Kept only so that older saved files still read; no longer shown.
    var done = false
    /// Former single text (franco); moved into `texts` when read. Kept so that nothing is ever lost.
    var text = ""
    /// The texts of the chant, in the order they were added.
    var texts: [SongText] = []
    /// File names of the sheets, in reading order (stored in Documents/images).
    var images: [String] = []
    /// In « Favoris ».
    var favorite = false

    init(title: String, section: String = "") {
        self.title = title
        self.section = section
    }

    // Every field is optional when reading, so that a later version of the app never loses saved data.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Sans nom"
        section = try c.decodeIfPresent(String.self, forKey: .section) ?? ""
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        images = try c.decodeIfPresent([String].self, forKey: .images) ?? []
        favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        texts = try c.decodeIfPresent([SongText].self, forKey: .texts) ?? []
        if texts.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            texts = [SongText(language: .franco, body: text)]
            text = ""
        }
    }

    /// Texts that have something written in them.
    var writtenTexts: [SongText] {
        texts.filter { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Everything written in the chant, for the search.
    var allText: String { texts.map(\.body).joined(separator: "\n") }
}

struct Period: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var songs: [Song] = []
    /// Periods with the same group are shown together under one card (« Messe »); empty for none.
    var group = ""

    init(name: String) { self.name = name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Sans nom"
        songs = try c.decodeIfPresent([Song].self, forKey: .songs) ?? []
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? ""
    }

    /// The chants cut into consecutive parts of the same section, in the order of the list.
    var parts: [(section: String, songs: [Song])] {
        var out: [(section: String, songs: [Song])] = []
        for song in songs {
            if let last = out.last, last.section == song.section {
                out[out.count - 1].songs.append(song)
            } else {
                out.append((section: song.section, songs: [song]))
            }
        }
        return out
    }

    /// Where each part starts and ends in `songs`.
    var partRanges: [(section: String, range: Range<Int>)] {
        var out: [(section: String, range: Range<Int>)] = []
        for (i, song) in songs.enumerated() {
            if let last = out.last, last.section == song.section {
                out[out.count - 1].range = last.range.lowerBound..<(i + 1)
            } else {
                out.append((section: song.section, range: i..<(i + 1)))
            }
        }
        return out
    }

    var sectionNames: [String] {
        var seen: [String] = []
        for song in songs where !song.section.isEmpty && !seen.contains(song.section) { seen.append(song.section) }
        return seen
    }
}

/// Everything the app knows, saved as one JSON file on the phone. No network, ever.
@MainActor
@Observable
final class Library {
    private(set) var periods: [Period] = []
    /// Chants opened lately, most recent first.
    private(set) var recentIDs: [UUID] = []
    /// Changes when the profile photo changes, so that it is drawn again.
    private(set) var avatarVersion = 0

    private static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private static var dataURL: URL { folder.appendingPathComponent("hazzat.json") }
    private static var imagesFolder: URL { folder.appendingPathComponent("images", isDirectory: true) }

    static func imageURL(_ name: String) -> URL { imagesFolder.appendingPathComponent(name) }

    /// Version of the bundled list (seed.json). 2 = chants in the order of the services;
    /// 3 = precise parts, Messe and Franco categories, periods in the order of the Coptic year.
    static let seedVersion = 3
    private static let seedVersionKey = "seedVersion"

    init() {
        recentIDs = (UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []).compactMap(UUID.init(uuidString:))
        try? FileManager.default.createDirectory(at: Self.imagesFolder, withIntermediateDirectories: true)
        let seed = Self.loadSeed()
        if let data = try? Data(contentsOf: Self.dataURL) {
            if let saved = try? JSONDecoder().decode([Period].self, from: data) {
                periods = saved
                if UserDefaults.standard.integer(forKey: Self.seedVersionKey) < Self.seedVersion {
                    // Keep a copy of the library as it was, then put the chants in their new order.
                    let backup = Self.folder.appendingPathComponent("hazzat-avant-v\(Self.seedVersion).json")
                    if !FileManager.default.fileExists(atPath: backup.path) { try? data.write(to: backup, options: .atomic) }
                    periods = Self.migrated(saved, by: seed)
                    UserDefaults.standard.set(Self.seedVersion, forKey: Self.seedVersionKey)
                    save()
                }
                return
            }
            // Never overwrite a file we cannot read: keep it aside.
            let backup = Self.folder.appendingPathComponent("hazzat-illisible-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: Self.dataURL, to: backup)
        }
        // First launch: the list of chants, by period, with no sheet yet.
        periods = seed.map { seedPeriod in
            var period = Period(name: seedPeriod.name)
            period.group = seedPeriod.group ?? ""
            period.songs = seedPeriod.songs.map { Song(title: $0.title, section: $0.section ?? "") }
            return period
        }
        UserDefaults.standard.set(Self.seedVersion, forKey: Self.seedVersionKey)
        save()
    }

    // MARK: Bundled list

    /// Where a chant of the bundled list was in the previous list: its period, its part, its name, and which
    /// one it was among chants of the same part and name.
    struct SeedOrigin: Decodable, Hashable {
        var period: String?
        var section: String
        var title: String
        var n: Int
    }

    struct SeedSong: Decodable {
        var title: String
        var section: String?
        var from: SeedOrigin?
    }

    struct SeedPeriod: Decodable {
        var name: String
        var group: String?
        /// Former names of this period (« Messe » became « Messe de saint Basile »).
        var was: [String]?
        var songs: [SeedSong]
    }

    private static func loadSeed() -> [SeedPeriod] {
        guard let url = Bundle.main.url(forResource: "seed", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let seed = try? JSONDecoder().decode([SeedPeriod].self, from: data) else { return [] }
        return seed
    }

    /// Puts a saved library in the shape of the bundled list without losing anything. Each chant keeps its
    /// id, sheets, words and favourite, and goes to its new period, part and place. A chant the user deleted
    /// stays deleted. A chant the user added or renamed is not in the list: it stays right after the chant it
    /// followed. A period the user created or renamed is kept, after the others.
    static func migrated(_ saved: [Period], by seed: [SeedPeriod]) -> [Period] {
        guard !seed.isEmpty else { return saved }
        struct Place { let period: Int; let song: Int }
        var index: [SeedOrigin: Place] = [:]
        for (p, period) in saved.enumerated() {
            var seen: [String: Int] = [:]
            for (i, song) in period.songs.enumerated() {
                let pair = song.section + "\u{1F}" + song.title
                let n = seen[pair, default: 0]
                seen[pair] = n + 1
                index[SeedOrigin(period: period.name, section: song.section, title: song.title, n: n)] = Place(period: p, song: i)
            }
        }

        var claimed: [UUID: String] = [:]          // id of a placed chant → its new part
        var usedPeriods = Set<UUID>()
        var result: [Period] = []
        for seedPeriod in seed {
            let names = [seedPeriod.name] + (seedPeriod.was ?? [])
            let base = names.lazy.compactMap { name in saved.first { $0.name == name && !usedPeriods.contains($0.id) } }.first
            var period = base ?? Period(name: seedPeriod.name)
            period.name = seedPeriod.name
            period.group = seedPeriod.group ?? ""
            var songs: [Song] = []
            var claimedHere = 0
            for seedSong in seedPeriod.songs {
                if let origin = seedSong.from {
                    guard let place = index[origin] else { continue }
                    var song = saved[place.period].songs[place.song]
                    guard claimed[song.id] == nil else { continue }
                    song.title = seedSong.title
                    song.section = seedSong.section ?? ""
                    claimed[song.id] = song.section
                    songs.append(song)
                    claimedHere += 1
                } else {
                    songs.append(Song(title: seedSong.title, section: seedSong.section ?? ""))
                }
            }
            let allNew = seedPeriod.songs.allSatisfy { $0.from == nil }
            guard base != nil || claimedHere > 0 || allNew else { continue }
            if let base { usedPeriods.insert(base.id) }
            period.songs = songs
            result.append(period)
        }

        // Chants the list does not know follow the chant they came after (or open their period).
        var following: [UUID: [Song]] = [:]
        var heads: [UUID: [Song]] = [:]
        for period in saved {
            var anchor: Song?
            for song in period.songs {
                if claimed[song.id] != nil { anchor = song; continue }
                var moved = song
                if let anchor {
                    if moved.section == anchor.section, let section = claimed[anchor.id] { moved.section = section }
                    following[anchor.id, default: []].append(moved)
                } else {
                    heads[period.id, default: []].append(moved)
                }
            }
        }
        for p in result.indices {
            var songs = heads.removeValue(forKey: result[p].id) ?? []
            for song in result[p].songs {
                songs.append(song)
                songs += following.removeValue(forKey: song.id) ?? []
            }
            result[p].songs = songs
        }
        // Periods the list does not know (created or renamed by the user), with what is left in them.
        for period in saved where !usedPeriods.contains(period.id) {
            var kept = period
            kept.songs = heads.removeValue(forKey: period.id) ?? []
            if !period.songs.contains(where: { claimed[$0.id] != nil }) { kept.songs = period.songs }
            result.append(kept)
        }
        return result
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(periods) else { return }
        try? data.write(to: Self.dataURL, options: .atomic)
    }

    // MARK: Periods

    func addPeriod(named name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        periods.append(Period(name: clean))
        save()
    }

    func renamePeriod(_ id: UUID, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let i = periods.firstIndex(where: { $0.id == id }) else { return }
        periods[i].name = clean
        save()
    }

    /// Removes a period with all its chants and their sheets.
    func deletePeriod(_ id: UUID) {
        guard let i = periods.firstIndex(where: { $0.id == id }) else { return }
        for song in periods[i].songs { removeFiles(of: song) }
        periods.remove(at: i)
        save()
    }

    func movePeriods(from source: IndexSet, to destination: Int) {
        periods.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: Shelf (periods and groups, as shown in the library)

    /// A period on its own, or a group of periods shown under one card (« Messe »).
    enum Shelf: Identifiable {
        case period(Period)
        case group(String, [Period])

        var id: String {
            switch self {
            case .period(let period): period.id.uuidString
            case .group(let name, _): "group-" + name
            }
        }

        var name: String {
            switch self {
            case .period(let period): period.name
            case .group(let name, _): name
            }
        }

        var periods: [Period] {
            switch self {
            case .period(let period): [period]
            case .group(_, let members): members
            }
        }
    }

    /// The library as shown: each group at the place of its first period.
    var shelf: [Shelf] {
        var seen = Set<String>()
        var out: [Shelf] = []
        for period in periods {
            if period.group.isEmpty {
                out.append(.period(period))
            } else if !seen.contains(period.group) {
                seen.insert(period.group)
                out.append(.group(period.group, periods.filter { $0.group == period.group }))
            }
        }
        return out
    }

    var groupNames: [String] {
        var seen: [String] = []
        for period in periods where !period.group.isEmpty && !seen.contains(period.group) { seen.append(period.group) }
        return seen
    }

    func members(of group: String) -> [Period] { periods.filter { $0.group == group } }

    /// Reorders the cards of the library; a group moves with all its periods.
    func moveShelf(from source: IndexSet, to destination: Int) {
        var items = shelf
        items.move(fromOffsets: source, toOffset: destination)
        periods = items.flatMap(\.periods)
        save()
    }

    /// Reorders the periods inside a group.
    func moveInGroup(_ group: String, from source: IndexSet, to destination: Int) {
        let slots = periods.indices.filter { periods[$0].group == group }
        var members = slots.map { periods[$0] }
        members.move(fromOffsets: source, toOffset: destination)
        for (slot, period) in zip(slots, members) { periods[slot] = period }
        save()
    }

    /// Puts a period in a group (next to the other periods of that group), or takes it out ("").
    func setGroup(of periodID: UUID, to group: String) {
        let clean = group.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let i = periods.firstIndex(where: { $0.id == periodID }) else { return }
        var period = periods.remove(at: i)
        period.group = clean
        if !clean.isEmpty, let last = periods.lastIndex(where: { $0.group == clean }) {
            periods.insert(period, at: last + 1)
        } else {
            periods.insert(period, at: min(i, periods.count))
        }
        save()
    }

    /// A new period inside a group, after its other periods.
    func addPeriod(named name: String, inGroup group: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var period = Period(name: clean)
        period.group = group
        if let last = periods.lastIndex(where: { $0.group == group }) {
            periods.insert(period, at: last + 1)
        } else {
            periods.append(period)
        }
        save()
    }

    func period(_ id: UUID) -> Period? { periods.first { $0.id == id } }

    // MARK: Parts of a period

    func renamePart(of periodID: UUID, at index: Int, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let p = periods.firstIndex(where: { $0.id == periodID }) else { return }
        let ranges = periods[p].partRanges
        guard ranges.indices.contains(index) else { return }
        for j in ranges[index].range { periods[p].songs[j].section = clean }
        save()
    }

    /// Moves a whole part up (-1) or down (+1), with its chants.
    func movePart(of periodID: UUID, at index: Int, by delta: Int) {
        guard let p = periods.firstIndex(where: { $0.id == periodID }) else { return }
        var ranges = periods[p].partRanges
        let target = index + delta
        guard ranges.indices.contains(index), ranges.indices.contains(target) else { return }
        ranges.swapAt(index, target)
        let songs = periods[p].songs
        periods[p].songs = ranges.flatMap { Array(songs[$0.range]) }
        save()
    }

    /// Removes a part: with its chants, or keeping them without a part.
    func deletePart(of periodID: UUID, at index: Int, keepSongs: Bool) {
        guard let p = periods.firstIndex(where: { $0.id == periodID }) else { return }
        let ranges = periods[p].partRanges
        guard ranges.indices.contains(index) else { return }
        let range = ranges[index].range
        if keepSongs {
            for j in range { periods[p].songs[j].section = "" }
        } else {
            for j in range { removeFiles(of: periods[p].songs[j]) }
            periods[p].songs.removeSubrange(range)
        }
        save()
    }

    /// A new part, created with its first chant at the end of the period.
    @discardableResult
    func addPart(named name: String, firstSong title: String, to periodID: UUID) -> UUID? {
        let part = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let p = periods.firstIndex(where: { $0.id == periodID }) else { return nil }
        let song = Song(title: clean, section: part)
        periods[p].songs.append(song)
        save()
        return song.id
    }

    // MARK: Songs

    /// Adds a chant at the end of a part (the last part when none is given).
    @discardableResult
    func addSong(titled title: String, to periodID: UUID, inPart index: Int? = nil) -> UUID? {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let p = periods.firstIndex(where: { $0.id == periodID }) else { return nil }
        let ranges = periods[p].partRanges
        if let index, ranges.indices.contains(index) {
            let song = Song(title: clean, section: ranges[index].section)
            periods[p].songs.insert(song, at: ranges[index].range.upperBound)
            save()
            return song.id
        }
        let song = Song(title: clean, section: periods[p].songs.last?.section ?? "")
        periods[p].songs.append(song)
        save()
        return song.id
    }

    func song(_ id: UUID) -> Song? {
        for period in periods {
            if let song = period.songs.first(where: { $0.id == id }) { return song }
        }
        return nil
    }

    func periodID(ofSong id: UUID) -> UUID? {
        periods.first { $0.songs.contains { $0.id == id } }?.id
    }

    /// A chant with the period it belongs to.
    struct Entry: Identifiable {
        let song: Song
        let period: Period
        var id: UUID { song.id }
        /// « Kiahk · Messe »
        var place: String { song.section.isEmpty ? period.name : "\(period.name) · \(song.section)" }
    }

    func locate(_ id: UUID) -> Entry? {
        for period in periods {
            if let song = period.songs.first(where: { $0.id == id }) { return Entry(song: song, period: period) }
        }
        return nil
    }

    /// The chant before (-1) or after (+1) in its period.
    func neighbor(of id: UUID, step: Int) -> UUID? {
        guard let period = periods.first(where: { $0.songs.contains { $0.id == id } }),
              let i = period.songs.firstIndex(where: { $0.id == id }),
              period.songs.indices.contains(i + step) else { return nil }
        return period.songs[i + step].id
    }

    /// Saves the edited chant, and moves it to another period when asked.
    func update(_ song: Song, in periodID: UUID) {
        guard let from = periods.firstIndex(where: { $0.songs.contains { $0.id == song.id } }),
              let at = periods[from].songs.firstIndex(where: { $0.id == song.id }) else { return }
        if periods[from].id == periodID {
            periods[from].songs[at] = song
        } else if let to = periods.firstIndex(where: { $0.id == periodID }) {
            periods[from].songs.remove(at: at)
            periods[to].songs.append(song)
        }
        save()
    }

    private func change(_ id: UUID, _ edit: (inout Song) -> Void) {
        for i in periods.indices {
            if let j = periods[i].songs.firstIndex(where: { $0.id == id }) {
                edit(&periods[i].songs[j])
                save()
                return
            }
        }
    }

    func renameSong(_ id: UUID, to title: String) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        change(id) { $0.title = clean }
    }

    func toggleFavorite(_ id: UUID) { change(id) { $0.favorite.toggle() } }

    /// Adds or replaces a text of a chant. An empty text is removed.
    func saveText(_ text: SongText, in songID: UUID) {
        change(songID) { song in
            let empty = text.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if let i = song.texts.firstIndex(where: { $0.id == text.id }) {
                if empty { song.texts.remove(at: i) } else { song.texts[i] = text }
            } else if !empty {
                song.texts.append(text)
            }
        }
    }

    func removeText(_ textID: UUID, from songID: UUID) {
        change(songID) { $0.texts.removeAll { $0.id == textID } }
    }

    /// Removes chants (anywhere) with their sheets.
    func deleteSongs(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for i in periods.indices {
            for song in periods[i].songs where ids.contains(song.id) { removeFiles(of: song) }
            periods[i].songs.removeAll { ids.contains($0.id) }
        }
        save()
    }

    /// Moves chants, in their order, to the end of a part of a period (a new part when it does not exist yet).
    func moveSongs(_ ids: Set<UUID>, to periodID: UUID, section: String) {
        guard !ids.isEmpty, periods.contains(where: { $0.id == periodID }) else { return }
        var moving: [Song] = []
        for i in periods.indices {
            moving += periods[i].songs.filter { ids.contains($0.id) }
            periods[i].songs.removeAll { ids.contains($0.id) }
        }
        for j in moving.indices { moving[j].section = section }
        guard let p = periods.firstIndex(where: { $0.id == periodID }) else { return }
        if let last = periods[p].partRanges.last(where: { $0.section == section }) {
            periods[p].songs.insert(contentsOf: moving, at: last.range.upperBound)
        } else {
            periods[p].songs.append(contentsOf: moving)
        }
        save()
    }

    /// Puts the chants of a period in a new order, each in the given part. Only known chants are kept in
    /// the order given; any chant not listed stays at the end (nothing is ever lost).
    func reorder(_ periodID: UUID, to order: [(id: UUID, section: String)]) {
        guard let p = periods.firstIndex(where: { $0.id == periodID }) else { return }
        var byID = Dictionary(uniqueKeysWithValues: periods[p].songs.map { ($0.id, $0) })
        var songs: [Song] = []
        for item in order {
            guard var song = byID.removeValue(forKey: item.id) else { continue }
            song.section = item.section
            songs.append(song)
        }
        songs += periods[p].songs.filter { byID[$0.id] != nil }
        periods[p].songs = songs
        save()
    }

    /// Reorders chants inside one part (indexes counted in that part).
    func moveSongs(inPart index: Int, of periodID: UUID, from source: IndexSet, to destination: Int) {
        guard let p = periods.firstIndex(where: { $0.id == periodID }) else { return }
        let ranges = periods[p].partRanges
        guard ranges.indices.contains(index) else { return }
        let range = ranges[index].range
        var part = Array(periods[p].songs[range])
        part.move(fromOffsets: source, toOffset: destination)
        periods[p].songs.replaceSubrange(range, with: part)
        save()
    }

    // MARK: Recently opened

    private static let recentKey = "recent"

    func markOpened(_ id: UUID) {
        recentIDs.removeAll { $0 == id }
        recentIDs.insert(id, at: 0)
        if recentIDs.count > 40 { recentIDs.removeLast(recentIDs.count - 40) }
        UserDefaults.standard.set(recentIDs.map(\.uuidString), forKey: Self.recentKey)
    }

    func clearRecents() {
        recentIDs = []
        UserDefaults.standard.removeObject(forKey: Self.recentKey)
    }

    var recents: [Entry] { recentIDs.compactMap { locate($0) } }

    var favorites: [Entry] {
        periods.flatMap { period in period.songs.filter(\.favorite).map { Entry(song: $0, period: period) } }
    }

    // MARK: Sheets (images)

    /// Stores a picked photo on the phone and returns its file name.
    func storeImage(_ data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        return storeImage(image)
    }

    /// Stores a photo or a scanned page on the phone and returns its file name.
    func storeImage(_ image: UIImage) -> String? {
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            try jpeg.write(to: Self.imageURL(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    /// Adds sheets, in this order, after the ones the chant already has.
    func addImages(_ names: [String], to id: UUID) {
        guard !names.isEmpty else { return }
        change(id) { $0.images.append(contentsOf: names) }
    }

    func removeImage(_ name: String, from id: UUID) {
        change(id) { $0.images.removeAll { $0 == name } }
        removeImageFile(name)
    }

    func removeImageFile(_ name: String) {
        try? FileManager.default.removeItem(at: Self.imageURL(name))
    }

    private func removeFiles(of song: Song) {
        for name in song.images { removeImageFile(name) }
    }

    // MARK: Profile photo

    static var avatarURL: URL { folder.appendingPathComponent("profil.jpg") }

    func setAvatar(_ data: Data) {
        guard let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.85) else { return }
        try? jpeg.write(to: Self.avatarURL, options: .atomic)
        avatarVersion += 1
    }
}

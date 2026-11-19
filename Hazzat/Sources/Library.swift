import Foundation
import Observation
import UIKit

/// One chant: its hazzat sheets (images kept on the phone) and, for a cantique, its words written in franco.
struct Song: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var title: String
    /// Part of the period it belongs to (« Messe », « Tasbeha semaine », « Franco »…); empty for none.
    var section = ""
    /// Kept only so that older saved files still read; no longer shown.
    var done = false
    /// Words, for a cantique written in franco.
    var text = ""
    /// File names of the sheets, in reading order (stored in Documents/images).
    var images: [String] = []

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
    }
}

struct Period: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var songs: [Song] = []

    init(name: String) { self.name = name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Sans nom"
        songs = try c.decodeIfPresent([Song].self, forKey: .songs) ?? []
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

    private static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private static var dataURL: URL { folder.appendingPathComponent("hazzat.json") }
    private static var imagesFolder: URL { folder.appendingPathComponent("images", isDirectory: true) }

    static func imageURL(_ name: String) -> URL { imagesFolder.appendingPathComponent(name) }

    /// Version of the bundled list (seed.json). 2 = chants in the order of the services.
    static let seedVersion = 2
    private static let seedVersionKey = "seedVersion"

    init() {
        try? FileManager.default.createDirectory(at: Self.imagesFolder, withIntermediateDirectories: true)
        let seed = Self.loadSeed()
        if let data = try? Data(contentsOf: Self.dataURL) {
            if let saved = try? JSONDecoder().decode([Period].self, from: data) {
                periods = saved
                if UserDefaults.standard.integer(forKey: Self.seedVersionKey) < Self.seedVersion {
                    // Keep a copy of the library as it was, then put the chants in their new order.
                    let backup = Self.folder.appendingPathComponent("hazzat-avant-v\(Self.seedVersion).json")
                    if !FileManager.default.fileExists(atPath: backup.path) { try? data.write(to: backup, options: .atomic) }
                    periods = Self.reordered(saved, by: seed)
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
            period.songs = seedPeriod.songs.map { Song(title: $0.title, section: $0.section ?? "") }
            return period
        }
        UserDefaults.standard.set(Self.seedVersion, forKey: Self.seedVersionKey)
        save()
    }

    // MARK: Bundled list

    /// Where a chant of the bundled list was in the previous list: its part, its name, and which one it was
    /// among chants of the same part and name.
    struct SeedOrigin: Decodable, Hashable {
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
        var songs: [SeedSong]
    }

    private static func loadSeed() -> [SeedPeriod] {
        guard let url = Bundle.main.url(forResource: "seed", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let seed = try? JSONDecoder().decode([SeedPeriod].self, from: data) else { return [] }
        return seed
    }

    /// Puts the chants of a saved library in the order of the bundled list, without losing anything: sheets,
    /// words and ids stay with their chant. A chant the user added or renamed is not in the list; it stays
    /// right after the chant it followed. A period the user renamed is left as it is.
    static func reordered(_ saved: [Period], by seed: [SeedPeriod]) -> [Period] {
        saved.map { period in
            guard let seedPeriod = seed.first(where: { $0.name == period.name }) else { return period }
            let songs = period.songs
            var indexByOrigin: [SeedOrigin: Int] = [:]
            var seen: [String: Int] = [:]
            for (i, song) in songs.enumerated() {
                let pair = song.section + "\u{1F}" + song.title
                let n = seen[pair, default: 0]
                seen[pair] = n + 1
                indexByOrigin[SeedOrigin(section: song.section, title: song.title, n: n)] = i
            }
            // Chants found in the list, in the new order, with their new name and part.
            var placed: [Int] = []
            var renamed: [Int: (title: String, section: String)] = [:]
            for seedSong in seedPeriod.songs {
                guard let origin = seedSong.from, let i = indexByOrigin[origin], renamed[i] == nil else { continue }
                placed.append(i)
                renamed[i] = (seedSong.title, seedSong.section ?? "")
            }
            guard !placed.isEmpty else { return period }
            // Every other chant follows the last found chant that came before it.
            var following: [Int: [Int]] = [:]
            var head: [Int] = []
            var anchor: Int?
            for i in songs.indices {
                if renamed[i] != nil { anchor = i; continue }
                if let anchor { following[anchor, default: []].append(i) } else { head.append(i) }
            }
            var result: [Song] = []
            func appendOwn(_ i: Int, after anchorIndex: Int?) {
                var song = songs[i]
                // A chant added inside a part moves with it into the part's new name.
                if let a = anchorIndex, song.section == songs[a].section, let new = renamed[a] { song.section = new.section }
                result.append(song)
            }
            for i in head { appendOwn(i, after: nil) }
            for i in placed {
                var song = songs[i]
                if let new = renamed[i] { song.title = new.title; song.section = new.section }
                result.append(song)
                for j in following[i] ?? [] { appendOwn(j, after: i) }
            }
            var out = period
            out.songs = result
            return out
        }
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

    func deletePeriods(at offsets: IndexSet) {
        for i in offsets { for song in periods[i].songs { removeFiles(of: song) } }
        periods.remove(atOffsets: offsets)
        save()
    }

    func movePeriods(from source: IndexSet, to destination: Int) {
        periods.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func period(_ id: UUID) -> Period? { periods.first { $0.id == id } }

    // MARK: Songs

    @discardableResult
    func addSong(titled title: String, to periodID: UUID) -> UUID? {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let i = periods.firstIndex(where: { $0.id == periodID }) else { return nil }
        let song = Song(title: clean, section: periods[i].songs.last?.section ?? "")
        periods[i].songs.append(song)
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

    func deleteSongs(at offsets: IndexSet, in periodID: UUID) {
        guard let i = periods.firstIndex(where: { $0.id == periodID }) else { return }
        for j in offsets { removeFiles(of: periods[i].songs[j]) }
        periods[i].songs.remove(atOffsets: offsets)
        save()
    }

    func moveSongs(from source: IndexSet, to destination: Int, in periodID: UUID) {
        guard let i = periods.firstIndex(where: { $0.id == periodID }) else { return }
        periods[i].songs.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: Sheets (images)

    /// Stores a picked photo on the phone and returns its file name.
    func storeImage(_ data: Data) -> String? {
        guard let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.85) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            try jpeg.write(to: Self.imageURL(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    func removeImageFile(_ name: String) {
        try? FileManager.default.removeItem(at: Self.imageURL(name))
    }

    private func removeFiles(of song: Song) {
        for name in song.images { removeImageFile(name) }
    }
}

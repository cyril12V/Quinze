import Foundation
import Observation
import UIKit

/// One chant: its hazzat sheets (images kept on the phone) and, for a cantique, its words written in franco.
struct Song: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var title: String
    /// Part of the period it belongs to (« Messe », « Tasbeha semaine », « Franco »…); empty for none.
    var section = ""
    /// The ✅ of the learner's list.
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

    var doneCount: Int { songs.filter(\.done).count }

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

    init() {
        try? FileManager.default.createDirectory(at: Self.imagesFolder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: Self.dataURL) {
            if let saved = try? JSONDecoder().decode([Period].self, from: data) {
                periods = saved
                return
            }
            // Never overwrite a file we cannot read: keep it aside.
            let backup = Self.folder.appendingPathComponent("hazzat-illisible-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: Self.dataURL, to: backup)
        }
        // First launch: the list of chants, by period, with no sheet yet.
        if let url = Bundle.main.url(forResource: "seed", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let seed = try? JSONDecoder().decode([Period].self, from: data) {
            periods = seed
        }
        save()
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

    func toggleDone(_ songID: UUID) {
        for i in periods.indices {
            if let j = periods[i].songs.firstIndex(where: { $0.id == songID }) {
                periods[i].songs[j].done.toggle()
                save()
                return
            }
        }
    }

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

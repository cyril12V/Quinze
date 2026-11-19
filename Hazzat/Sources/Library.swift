import Foundation
import Observation
import UIKit

/// One chant: its hazzat sheets (images kept on the phone) and, for a cantique, its words written in franco.
struct Song: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var title: String
    /// A cantique written in franco (shown in the « Franco » section of its period).
    var isFranco = false
    var text = ""
    /// File names of the sheets, in reading order (stored in Documents/images).
    var images: [String] = []
}

struct Period: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var songs: [Song] = []
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
        if let data = try? Data(contentsOf: Self.dataURL),
           let saved = try? JSONDecoder().decode([Period].self, from: data) {
            periods = saved
        } else {
            periods = [Period(name: "Kiahk", songs: [
                Song(title: "Efrahi ya Mariam", isFranco: true),
                Song(title: "Al sugud yalik", isFranco: true),
                Song(title: "Al 3oleka", isFranco: true),
                Song(title: "Marahmak", isFranco: true)
            ])]
            save()
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
        let song = Song(title: clean)
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

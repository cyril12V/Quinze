import SwiftUI

/// Home: one big button per period, and a search across every chant.
struct HomeView: View {
    @Environment(Library.self) private var library
    @State private var query = ""
    @State private var showManage = false

    private var results: [(song: Song, period: String)] {
        let needle = query.trimmingCharacters(in: .whitespaces).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        guard !needle.isEmpty else { return [] }
        return library.periods.flatMap { period in
            period.songs
                .filter { $0.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).contains(needle) }
                .map { (song: $0, period: $0.section.isEmpty ? period.name : "\(period.name) · \($0.section)") }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    periodButtons
                } else {
                    searchResults
                }
            }
            .background(Palette.parchment.ignoresSafeArea())
            .navigationTitle("Hazzat")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Chercher un chant")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Gérer") { showManage = true }
                }
            }
            .navigationDestination(for: UUID.self) { PeriodView(periodID: $0) }
            .sheet(isPresented: $showManage) { ManageView() }
        }
    }

    private var periodButtons: some View {
        ScrollView {
            VStack(spacing: 14) {
                if library.periods.isEmpty {
                    ContentUnavailableView("Aucune période", systemImage: "music.note.list",
                                           description: Text("Touche « Gérer » pour créer ta première période."))
                        .padding(.top, 60)
                }
                ForEach(Array(library.periods.enumerated()), id: \.element.id) { index, period in
                    NavigationLink(value: period.id) {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(period.name)
                                    .font(.system(size: 28, weight: .bold))
                                    .multilineTextAlignment(.leading)
                                Text((period.songs.count == 1 ? "1 chant" : "\(period.songs.count) chants")
                                     + (period.doneCount > 0 ? " · \(period.doneCount) ✅" : ""))
                                    .font(.subheadline.weight(.medium))
                                    .opacity(0.85)
                            }
                            Spacer(minLength: 12)
                            Image(systemName: "chevron.right")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Palette.gold)
                        }
                        .foregroundStyle(.white)
                        .padding(22)
                        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Palette.card(index)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    private var searchResults: some View {
        List {
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
            ForEach(results, id: \.song.id) { item in
                SongDisclosure(song: item.song, subtitle: item.period)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

import SwiftUI

/// « Mes chants » : today, the chants opened lately, the periods, and the last chant opened.
struct HomeView: View {
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var day = LiturgicalDay()

    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    private func period(named name: String) -> Period? {
        library.periods.first { Self.fold($0.name) == Self.fold(name) }
    }

    /// The period to open from « Aujourd'hui »: the one in progress, else the next one.
    private var todayTarget: Period? {
        if let current = period(named: day.season) { return current }
        if let next = day.next { return period(named: next.season) }
        return nil
    }

    private var todayLine: String {
        var parts = [day.season]
        if let next = day.next {
            parts.append(next.days == 1 ? "\(next.season) demain" : "\(next.season) dans \(next.days) jours")
        }
        if let tomorrow = day.tomorrowTune { parts.append("demain \(tomorrow.rawValue)") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                today
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                categories.padding(.top, 34)
            }
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Palette.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if let last = library.recents.first {
                    LastSongCard(entry: last) { router.open(.song(last.song.id)) }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                }
                Color.clear.frame(height: TabBar.height)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { day = LiturgicalDay() }
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 10) {
            Text("Mes chants")
                .font(Typo.screenTitle)
                .foregroundStyle(Palette.ink)
            Spacer()
            IconButton(systemName: "magnifyingglass", label: "Chercher", size: 22) { router.open(.search) }
            Button { router.tab = .profile } label: { Avatar(size: 38) }
                .plainButton()
                .accessibilityLabel("Profil")
        }
        .padding(.leading, 24)
        .padding(.trailing, 18)
    }

    /// The day, in a frame, centred: Adam or Watos, the Coptic date, the period.
    private var today: some View {
        VStack(spacing: 6) {
            Text("JOUR")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundStyle(Palette.muted)
            Text(day.tune.rawValue)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Palette.ink)
            Text(day.coptic.formatted)
                .font(Typo.smallTitle)
                .foregroundStyle(Palette.ink)
            Text(todayLine)
                .font(Typo.caption)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let target = todayTarget {
                SmallButton(target.name) { router.open(.period(target.id)) }
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 14, x: 0, y: 6)
        .accessibilityElement(children: .combine)
    }

    /// Messe and Franco first, then the year from Nayrouz.
    private var shelf: [Library.Shelf] {
        let all = library.shelf
        func first(_ item: Library.Shelf) -> Int {
            switch Self.fold(item.name) {
            case "messe": 0
            case "franco": 1
            default: 2
            }
        }
        return all.enumerated().sorted { (first($0.element), $0.offset) < (first($1.element), $1.offset) }.map(\.element)
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHead(title: "Mes catégories",
                        subtitle: "De Nayrouz à la Nahda, la messe et le franco",
                        button: "Voir tout") { router.tab = .library }
            ScrollView(.horizontal) {
                LazyHGrid(rows: [GridItem(.fixed(CoverCard.height), spacing: 18),
                                 GridItem(.fixed(CoverCard.height))],
                          alignment: .top, spacing: 12) {
                    ForEach(shelf) { item in
                        switch item {
                        case .period(let period):
                            let current = Self.fold(period.name) == Self.fold(day.season)
                            Button { router.open(.period(period.id)) } label: {
                                CoverCard(cover: .period(period),
                                          title: period.name,
                                          subtitle: current ? "En cours" : countLabel(period.songs.count),
                                          highlight: current)
                            }
                            .plainButton()
                        case .group(let name, let members):
                            Button { router.open(.group(name)) } label: {
                                CoverCard(cover: .group(name),
                                          title: name,
                                          subtitle: members.count == 1 ? "1 période" : "\(members.count) \(Self.fold(name) == "messe" ? "messes" : "périodes")")
                            }
                            .plainButton()
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func countLabel(_ count: Int) -> String {
        switch count {
        case 0: "Aucun chant"
        case 1: "1 chant"
        default: "\(count) chants"
        }
    }
}

/// Square cover with the name in black and a grey line under it.
struct CoverCard: View {
    static let side: CGFloat = 118
    static let height: CGFloat = side + 44

    let cover: Cover.Content
    let title: String
    let subtitle: String
    var highlight = false

    var body: some View {
        VStack(spacing: 0) {
            Cover(content: cover, size: Self.side)
            Text(title)
                .font(Typo.smallTitle)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .padding(.top, 8)
            Text(subtitle)
                .font(.system(size: 12, weight: highlight ? .semibold : .regular))
                .foregroundStyle(highlight ? Palette.accent : Palette.muted)
                .lineLimit(1)
                .padding(.top, 2)
        }
        .frame(width: Self.side, height: Self.height, alignment: .top)
        .accessibilityElement(children: .combine)
    }
}

/// The floating card at the bottom: the last chant opened.
struct LastSongCard: View {
    let entry: Library.Entry
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                Cover(content: .song(entry.song, period: entry.period.name), size: 50, radius: 10)
                    .softShadow()
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.song.title)
                        .font(Typo.name)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(entry.place)
                        .font(Typo.caption)
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Palette.iconOn)
                    .padding(.trailing, 4)
            }
            .padding(12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .softShadow()
        }
        .plainButton()
        .accessibilityLabel("Dernier chant ouvert : \(entry.song.title)")
    }
}

import SwiftUI

/// Where a tap leads: a period, or one chant inside it (from the search).
enum Route: Hashable {
    case period(UUID)
    case song(period: UUID, song: UUID)
}

/// Home: today (Adam or Watos, the period), the search, and one big button per period.
struct HomeView: View {
    @Environment(Library.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @State private var query = ""
    @State private var showManage = false
    @State private var path: [Route] = []
    @State private var day = LiturgicalDay()

    private struct Hit: Identifiable {
        let song: Song
        let periodID: UUID
        let place: String
        var id: UUID { song.id }
    }

    private var needle: String { Self.fold(query.trimmingCharacters(in: .whitespaces)) }

    private var hits: [Hit] {
        guard !needle.isEmpty else { return [] }
        return library.periods.flatMap { period in
            period.songs
                .filter { Self.fold($0.title).contains(needle) || Self.fold($0.text).contains(needle) }
                .map { Hit(song: $0, periodID: period.id,
                           place: $0.section.isEmpty ? period.name : "\(period.name) · \($0.section)") }
        }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    private func period(named name: String) -> Period? {
        library.periods.first { Self.fold($0.name) == Self.fold(name) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TodayCard(day: day,
                              periodID: { period(named: $0)?.id },
                              open: { path.append(.period($0)) })
                    SearchField(text: $query)
                    if needle.isEmpty {
                        periods
                    } else {
                        results
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Hazzat")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showManage = true } label: {
                        Text("Gérer").font(Typo.body(16, .semibold))
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .period(let id): PeriodView(periodID: id, focus: nil)
                case .song(let id, let song): PeriodView(periodID: id, focus: song)
                }
            }
            .sheet(isPresented: $showManage) { ManageView().environment(library) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { day = LiturgicalDay() }
        }
    }

    // MARK: Periods

    private var periods: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Périodes")
                .font(Typo.title(28))
                .foregroundStyle(Palette.ink)
                .padding(.top, 8)
                .padding(.leading, 4)
            if library.periods.isEmpty {
                Text("Aucune période. Touche « Gérer » pour créer la première.")
                    .font(Typo.body(15))
                    .foregroundStyle(Palette.muted)
                    .padding(.vertical, 30)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(library.periods) { period in
                    NavigationLink(value: Route.period(period.id)) {
                        PeriodTile(period: period, isCurrent: Self.fold(period.name) == Self.fold(day.season))
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
    }

    // MARK: Search

    private var results: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(hits.isEmpty ? "Aucun chant trouvé" : (hits.count == 1 ? "1 chant" : "\(hits.count) chants"))
                .font(Typo.body(13, .semibold))
                .foregroundStyle(Palette.muted)
                .padding(.leading, 6)
            if !hits.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                        if index > 0 { Hairline().padding(.leading, 18) }
                        NavigationLink(value: Route.song(period: hit.periodID, song: hit.song.id)) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(hit.song.title)
                                        .font(Typo.body(16, .semibold))
                                        .foregroundStyle(Palette.ink)
                                        .multilineTextAlignment(.leading)
                                    Text(hit.place)
                                        .font(Typo.body(13, .medium))
                                        .foregroundStyle(Palette.muted)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Palette.muted)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                    }
                }
                .card()
            }
        }
    }
}

// MARK: - Today

/// Today in the Church: the date, Adam or Watos, the period in progress and the next one.
struct TodayCard: View {
    let day: LiturgicalDay
    /// The period of the list that has this name, if any.
    let periodID: (String) -> UUID?
    let open: (UUID) -> Void

    private static let french = Locale(identifier: "fr_FR")

    private var dateLine: String {
        let civil = day.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Self.french))
        return "\(civil) · \(day.coptic.formatted)".uppercased()
    }

    private var tuneDays: String { day.tune == .adam ? "dim. → mar." : "mer. → sam." }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(dateLine)
                .font(Typo.body(11.5, .bold, relativeTo: .caption))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.7))

            HStack(alignment: .firstTextBaseline) {
                Text("Jour \(day.tune.rawValue)")
                    .font(Typo.title(42, relativeTo: .largeTitle))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Text(tuneDays)
                    .font(Typo.body(12, .semibold, relativeTo: .caption))
                    .foregroundStyle(Palette.gold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .overlay(Capsule().stroke(Palette.gold.opacity(0.6), lineWidth: 1))
            }
            .padding(.top, 8)

            if let tomorrow = day.tomorrowTune {
                Text("Demain : jour \(tomorrow.rawValue)")
                    .font(Typo.body(14, .semibold))
                    .foregroundStyle(Palette.gold)
                    .padding(.top, 2)
            }

            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(height: 1)
                .padding(.vertical, 16)

            link(to: day.season) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PÉRIODE EN COURS")
                            .font(Typo.body(11, .bold, relativeTo: .caption))
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.6))
                        Text(day.season)
                            .font(Typo.titleSemi(28))
                            .foregroundStyle(.white)
                        if let fast = day.fast {
                            Text(fast)
                                .font(Typo.body(13, .medium))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    Spacer(minLength: 8)
                    if periodID(day.season) != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }

            if let next = day.next {
                link(to: next.season) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ensuite")
                                .font(Typo.body(12, .semibold, relativeTo: .caption))
                                .foregroundStyle(.white.opacity(0.6))
                            Text(next.season)
                                .font(Typo.body(16, .bold))
                                .foregroundStyle(.white)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(next.days == 1 ? "demain" : "dans \(next.days) jours")
                                .font(Typo.body(14, .bold))
                                .foregroundStyle(Palette.gold)
                            Text(next.start.formatted(.dateTime.day().month(.abbreviated).locale(Self.french)))
                                .font(Typo.body(12, .medium, relativeTo: .caption))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.top, 16)
            }
        }
        .padding(22)
        .background(
            LinearGradient(colors: [Palette.hero, Palette.heroDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }

    /// A tappable row when the period exists in the list, plain text otherwise.
    @ViewBuilder
    private func link<Content: View>(to season: String, @ViewBuilder _ content: () -> Content) -> some View {
        if let id = periodID(season) {
            Button { open(id) } label: { content().contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityHint("Ouvre les chants de \(season)")
        } else {
            content()
        }
    }
}

// MARK: - Pieces

struct PeriodTile: View {
    let period: Period
    let isCurrent: Bool

    private var count: String {
        switch period.songs.count {
        case 0: "Aucun chant"
        case 1: "1 chant"
        default: "\(period.songs.count) chants"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Capsule()
                    .fill(isCurrent ? Palette.accent : Palette.gold)
                    .frame(width: 22, height: 3)
                Spacer(minLength: 0)
                if isCurrent {
                    Text("EN COURS")
                        .font(Typo.body(9.5, .bold, relativeTo: .caption2))
                        .tracking(0.8)
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Palette.accentSoft, in: Capsule())
                }
            }
            .frame(height: 18)
            Spacer(minLength: 10)
            Text(period.name)
                .font(Typo.titleSemi(24))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(count)
                .font(Typo.body(13, .medium))
                .foregroundStyle(Palette.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isCurrent ? Palette.accent : Palette.line, lineWidth: isCurrent ? 1.5 : 1)
        )
    }
}

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.muted)
            TextField("", text: $text, prompt: Text("Chercher un chant").foregroundStyle(Palette.muted))
                .font(Typo.body(16))
                .foregroundStyle(Palette.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted)
                }
                .accessibilityLabel("Effacer")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
        .card(radius: 16)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Palette.line).frame(height: 1)
    }
}

/// Cards and tiles darken slightly while touched.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Palette.cardPressed : .clear)
    }
}

extension View {
    /// White card (dark grey at night) with a thin border.
    func card(radius: CGFloat = 20) -> some View {
        self
            .background(Palette.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Palette.line, lineWidth: 1))
    }
}

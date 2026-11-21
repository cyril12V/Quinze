import SwiftUI
import UIKit
import ImageIO

/// White everywhere, black text, one orange for actions.
enum Palette {
    static let background = Color.white
    static let ink = Color(hex: 0x080808)
    static let muted = Color(hex: 0x777777)
    static let line = Color(hex: 0xF1F1F1)
    static let accent = Color(hex: 0xF04418)
    static let iconOn = Color.black
    static let iconOff = Color(hex: 0xA0A0A0)
    static let track = Color(hex: 0xE9E9E9)

    /// Cover colours, one per period, always the same for a given name.
    private static let named: [String: UInt32] = [
        "kiahk": 0x1F3A5F, "rameaux": 0x2F5D50, "semaine sainte": 0x1B1B1B, "tasbeha": 0x7A5A2C,
        "tawzih": 0x4B4277, "resurrection": 0xB4533C, "ascension": 0x2C5F7C, "pentecote": 0xA8432F,
        "nayrouz": 0x8C6A1F, "fete de la croix": 0x6B2232, "jeune des apotres": 0x3F5A3A, "nahda": 0x3A6A8C,
        "messe": 0x5E2B4F, "nativite": 0x7E3A2A, "epiphanie": 0x2E6E73, "grand careme": 0x3B3B46,
        "jonas": 0x22545E, "entree en egypte": 0x9A6B2A, "noces de cana": 0x7A3B5C, "messe eveque": 0x4A3A2A,
    ]
    private static let spare: [UInt32] = [0x1F3A5F, 0x2F5D50, 0x7A5A2C, 0x4B4277, 0xB4533C, 0x2C5F7C, 0x6B2232, 0x3F5A3A]

    /// Name of a category made simple: « Fête de la croix » → « fete-de-la-croix ».
    static func key(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
    }

    /// The drawn cover of a category (Nahda: the Virgin, Rameaux: palms…), if there is one.
    static func art(for name: String) -> UIImage? {
        UIImage(named: "cover-" + key(name))
    }

    static func cover(for name: String) -> Color {
        let key = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
        if let fixed = named[key] { return Color(hex: fixed) }
        var hash: UInt32 = 5381
        for scalar in key.unicodeScalars { hash = (hash &* 33) &+ scalar.value }
        return Color(hex: spare[Int(hash % UInt32(spare.count))])
    }
}

/// SF Pro, black and sharp.
enum Typo {
    static let screenTitle = Font.system(size: 26, weight: .bold)
    static let sectionTitle = Font.system(size: 19, weight: .bold)
    static let smallTitle = Font.system(size: 13, weight: .semibold)
    static let name = Font.system(size: 14, weight: .semibold)
    static let caption = Font.system(size: 12.5)
    static let lyrics = Font.system(size: 18)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension View {
    /// A very soft shadow, as under the covers of the reference.
    func softShadow() -> some View {
        shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 8)
    }

    /// Text that never turns blue or grey when it sits in a button.
    func plainButton() -> some View { buttonStyle(.plain) }
}

// MARK: - Images

/// Sheets read from the phone, made smaller for the screen, and kept in memory once drawn.
@MainActor
enum Images {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(_ name: String, maxPixel: CGFloat) -> UIImage? {
        let key = "\(name)@\(Int(maxPixel))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let source = CGImageSourceCreateWithURL(Library.imageURL(name) as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: key)
        return image
    }
}

// MARK: - Covers

/// Square cover: the first sheet when there is one, otherwise the period colour with the name in capitals.
struct Cover: View {
    enum Content {
        case song(Song, period: String)
        case period(Period)
        case group(String)
    }

    let content: Content
    var size: CGFloat
    var radius: CGFloat = 14

    var body: some View {
        ZStack {
            switch content {
            case .song(let song, let period):
                if let first = song.images.first, let image = Images.image(first, maxPixel: size * 3) {
                    Color.white
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size, alignment: .top)
                        .clipped()
                } else if let art = Palette.art(for: period) {
                    Image(uiImage: art).resizable().scaledToFill()
                } else {
                    Palette.cover(for: period)
                    label(song.title, under: period)
                }
            case .period(let period):
                named(period.name)
            case .group(let name):
                named(name)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func named(_ name: String) -> some View {
        if let art = Palette.art(for: name) {
            Image(uiImage: art).resizable().scaledToFill()
        } else {
            Palette.cover(for: name)
            label(name, under: nil)
        }
    }

    @ViewBuilder
    private func label(_ title: String, under: String?) -> some View {
        if size < 70 {
            Text(Self.initials(title))
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .padding(4)
        } else {
            VStack(spacing: size * 0.05) {
                Text(title.uppercased())
                    .font(.system(size: size * 0.105, weight: .semibold))
                    .tracking(size * 0.025)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                if let under {
                    Text(under.uppercased())
                        .font(.system(size: size * 0.065, weight: .bold))
                        .tracking(size * 0.02)
                        .opacity(0.7)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .padding(size * 0.1)
        }
    }

    static func initials(_ text: String) -> String {
        let words = text.split { !$0.isLetter && !$0.isNumber }
        return words.prefix(2).compactMap { $0.first.map { String($0).uppercased() } }.joined()
    }
}

/// Round profile picture (the one chosen in « Profil », or a plain silhouette).
struct Avatar: View {
    @Environment(Library.self) private var library
    var size: CGFloat = 36

    var body: some View {
        let _ = library.avatarVersion
        Group {
            if let image = UIImage(contentsOfFile: Library.avatarURL.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color(hex: 0xEDEDED)
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.45, weight: .bold))
                        .foregroundStyle(Palette.iconOff)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

// MARK: - Buttons and bars

/// Small orange rectangle, like « MORE » in the reference.
struct SmallButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(Palette.accent, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .plainButton()
    }
}

/// Back arrow on a small white tile with a soft shadow.
struct BackButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.iconOn)
                .frame(width: 44, height: 44)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 3)
        }
        .plainButton()
        .accessibilityLabel("Retour")
    }
}

/// Top of a pushed screen: back arrow, a small centred caption, and buttons on the right.
struct TopBar<Trailing: View>: View {
    var caption: String = ""
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ZStack {
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 76)
            HStack {
                BackButton()
                Spacer()
                trailing()
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 60)
    }
}

extension TopBar where Trailing == EmptyView {
    init(caption: String = "") {
        self.caption = caption
        self.trailing = { EmptyView() }
    }
}

/// Black icon, no background.
struct IconButton: View {
    let systemName: String
    let label: String
    var size: CGFloat = 20
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(Palette.iconOn)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .plainButton()
        .accessibilityLabel(label)
    }
}

/// « ⋮ » that opens a menu.
struct MoreMenu<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu(content: content) {
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Palette.iconOn)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Plus d'actions")
    }
}

/// Section title with its grey line under it and, on the right, an orange button.
struct SectionHead: View {
    let title: String
    var subtitle: String = ""
    var button: String?
    var action: () -> Void = {}

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Typo.sectionTitle).foregroundStyle(Palette.ink)
                if !subtitle.isEmpty {
                    Text(subtitle).font(Typo.caption).foregroundStyle(Palette.muted)
                }
            }
            Spacer(minLength: 12)
            if let button { SmallButton(button, action: action) }
        }
        .padding(.horizontal, 24)
    }
}

/// One chant in a list: little cover, name, and what it has (sheets, words).
struct SongRow: View {
    let song: Song
    /// Name of its period (gives the colour of the cover).
    let period: String
    /// « Kiahk · Messe », shown in lists that mix periods.
    var place: String?

    private var detail: String {
        var parts: [String] = []
        if let place { parts.append(place) }
        switch song.images.count {
        case 0: break
        case 1: parts.append("1 feuille")
        default: parts.append("\(song.images.count) feuilles")
        }
        if !song.text.isEmpty { parts.append("Paroles") }
        if song.images.isEmpty && song.text.isEmpty { parts.append("Pas de feuille") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 14) {
            Cover(content: .song(song, period: period), size: 48, radius: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(Typo.name)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                Text(detail)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if song.favorite {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.accent)
                    .accessibilityLabel("favori")
            }
        }
        .contentShape(Rectangle())
    }
}

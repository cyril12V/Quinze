import SwiftUI

@main
struct HazzatApp: App {
    @State private var library = Library()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(library)
                .tint(Palette.burgundy)
        }
    }
}

enum Palette {
    static let burgundy = Color(red: 0.43, green: 0.11, blue: 0.15)
    static let gold = Color(red: 0.91, green: 0.75, blue: 0.35)
    static let parchment = Color(red: 0.96, green: 0.94, blue: 0.89)
    static let ink = Color(red: 0.17, green: 0.10, blue: 0.08)

    private static let cards: [Color] = [
        burgundy,
        Color(red: 0.12, green: 0.23, blue: 0.42),
        Color(red: 0.20, green: 0.36, blue: 0.24),
        Color(red: 0.45, green: 0.30, blue: 0.10),
        Color(red: 0.33, green: 0.20, blue: 0.42)
    ]

    static func card(_ index: Int) -> Color { cards[index % cards.count] }
}

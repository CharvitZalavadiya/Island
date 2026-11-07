import SwiftUI

/// Twelve mascots that all smile, each feeling something different.
extension MascotDefinition {
    static let sunny = MascotDefinition(id: "sunny", name: "Sunny (happy)", bodyColor: Color(hex: 0xFFD93D), emotion: .happy)
    static let giggles = MascotDefinition(id: "giggles", name: "Giggles (laughing)", bodyColor: Color(hex: 0xFF8FB8), emotion: .laughing)
    static let winky = MascotDefinition(id: "winky", name: "Winky (playful)", bodyColor: Color(hex: 0xFFA14A), emotion: .winking)
    static let lovey = MascotDefinition(id: "lovey", name: "Lovey (in love)", bodyColor: Color(hex: 0xFF7B8A), emotion: .loving)
    static let cooly = MascotDefinition(id: "cooly", name: "Cooly (cool)", bodyColor: Color(hex: 0x6CB8FF), emotion: .cool)
    static let blushy = MascotDefinition(id: "blushy", name: "Blushy (shy)", bodyColor: Color(hex: 0xFFC9B0), emotion: .shy)
    static let silly = MascotDefinition(id: "silly", name: "Silly (cheeky)", bodyColor: Color(hex: 0x8CE06B), emotion: .silly)
    static let starry = MascotDefinition(id: "starry", name: "Starry (amazed)", bodyColor: Color(hex: 0xB68BFF), emotion: .starry)
    static let dreamy = MascotDefinition(
        id: "dreamy", name: "Dreamy (sleepy)", bodyColor: Color(hex: 0xCDB4FF), emotion: .dreamy,
        accessory: { _ in
            AnyView(
                ZStack {
                    Text("z").font(.system(size: 5, weight: .heavy, design: .rounded)).position(x: 20.5, y: 5.2)
                    Text("z").font(.system(size: 3.6, weight: .heavy, design: .rounded)).position(x: 23.2, y: 2.6)
                }
                .foregroundStyle(Color(hex: 0xCDB4FF)))
        })
    static let zen = MascotDefinition(id: "zen", name: "Zen (calm)", bodyColor: Color(hex: 0x5EE0C0), emotion: .zen)
    static let proud = MascotDefinition(id: "proud", name: "Proud (proud)", bodyColor: Color(hex: 0x8F95FF), emotion: .proud)
    static let joyful = MascotDefinition(id: "joyful", name: "Joyful (thrilled)", bodyColor: Color(hex: 0xB8E836), emotion: .joyful)
}

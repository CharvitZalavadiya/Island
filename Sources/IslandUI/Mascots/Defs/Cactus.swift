import SwiftUI

private let green = Color(hex: 0x7BD88F)

extension MascotDefinition {
    static let cactus = MascotDefinition(id: "cactus", name: "Cactus", bodyColor: green) { _ in
        AnyView(ZStack {
            Capsule().fill(green).frame(width: 3.2, height: 8).position(x: 2, y: 13)
            Capsule().fill(green).frame(width: 5, height: 3.2).position(x: 4, y: 16.5)
            Capsule().fill(green).frame(width: 3.2, height: 8).position(x: 24, y: 11)
            Capsule().fill(green).frame(width: 5, height: 3.2).position(x: 22, y: 14.5)
            mascotDot(9, 18.5, 0.6, Color.white.opacity(0.85))
            mascotDot(17, 18.5, 0.6, Color.white.opacity(0.85))
            mascotDot(13, 20, 0.6, Color.white.opacity(0.85))
        })
    }
}

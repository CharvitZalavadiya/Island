import SwiftUI

private let water = Color(hex: 0x5BD6E8)

extension MascotDefinition {
    static let droplet = MascotDefinition(id: "droplet", name: "Droplet", bodyColor: water) { _ in
        AnyView(ZStack {
            Polygon((13, 0), (19.8, 8), (6.2, 8)).fill(water)
            mascotDot(8.4, 17, 1.2, Color.white.opacity(0.7))
        })
    }
}

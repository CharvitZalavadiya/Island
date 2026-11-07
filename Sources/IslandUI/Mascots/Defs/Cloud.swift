import SwiftUI

private let sky = Color(hex: 0x8FD3FF)

extension MascotDefinition {
    static let cloud = MascotDefinition(id: "cloud", name: "Cloud", bodyColor: sky) { _ in
        AnyView(ZStack {
            mascotDot(8.5, 6.8, 4, sky)
            mascotDot(13, 4.6, 4.6, sky)
            mascotDot(17.6, 6.8, 4, sky)
        })
    }
}

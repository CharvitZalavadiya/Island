import SwiftUI

private let fur = Color(hex: 0xFFB36B)

extension MascotDefinition {
    static let cat = MascotDefinition(id: "cat", name: "Cat", bodyColor: fur) { _ in
        AnyView(ZStack {
            Polygon((4.5, 9), (5.5, 1.5), (11.5, 4.6)).fill(fur)
            Polygon((21.5, 9), (20.5, 1.5), (14.5, 4.6)).fill(fur)
            Polygon((6.3, 7.2), (6.6, 3.9), (9.2, 5.3)).fill(Color(hex: 0xFF8FA3))
            Polygon((19.7, 7.2), (19.4, 3.9), (16.8, 5.3)).fill(Color(hex: 0xFF8FA3))
        })
    }
}

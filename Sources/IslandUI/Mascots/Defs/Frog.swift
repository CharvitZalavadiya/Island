import SwiftUI

private let leaf = Color(hex: 0x8BE04E)

extension MascotDefinition {
    static let frog = MascotDefinition(id: "frog", name: "Frog", bodyColor: leaf) { _ in
        AnyView(ZStack {
            mascotDot(8, 5.6, 3.6, leaf)
            mascotDot(18, 5.6, 3.6, leaf)
            mascotDot(6.6, 16.5, 1.7, Color(hex: 0xFF9EC0).opacity(0.8))
            mascotDot(19.4, 16.5, 1.7, Color(hex: 0xFF9EC0).opacity(0.8))
        })
    }
}

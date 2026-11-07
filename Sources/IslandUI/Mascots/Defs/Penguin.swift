import SwiftUI

private let ice = Color(hex: 0xBFD7EA)
private let orange = Color(hex: 0xFFA94D)

extension MascotDefinition {
    static let penguin = MascotDefinition(id: "penguin", name: "Penguin", bodyColor: ice) { _ in
        AnyView(ZStack {
            Ellipse().fill(Color.white).frame(width: 12, height: 8.5).position(x: 13, y: 17.6)
            Polygon((11.3, 14.4), (14.7, 14.4), (13, 16.7)).fill(orange)
            mascotDot(10, 21.2, 1.3, orange)
            mascotDot(16, 21.2, 1.3, orange)
        })
    }
}

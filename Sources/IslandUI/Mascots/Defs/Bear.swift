import SwiftUI

private let brown = Color(hex: 0xC99A6B)

extension MascotDefinition {
    static let bear = MascotDefinition(id: "bear", name: "Bear", bodyColor: brown) { _ in
        AnyView(ZStack {
            mascotDot(6.5, 5.4, 3.4, brown)
            mascotDot(19.5, 5.4, 3.4, brown)
            mascotDot(6.5, 5.4, 1.6, Color(hex: 0x9C6F45))
            mascotDot(19.5, 5.4, 1.6, Color(hex: 0x9C6F45))
            Ellipse().fill(Color(hex: 0xF0D2AE)).frame(width: 7, height: 5).position(x: 13, y: 17)
            mascotDot(13, 15.8, 1, Color(hex: 0x4A3320))
        })
    }
}

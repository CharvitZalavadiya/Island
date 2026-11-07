import SwiftUI

private let fluff = Color(hex: 0xFFD1E3)

extension MascotDefinition {
    static let bunny = MascotDefinition(id: "bunny", name: "Bunny", bodyColor: fluff) { _ in
        AnyView(ZStack {
            Capsule().fill(fluff).frame(width: 4.4, height: 11).position(x: 9, y: 1.5)
            Capsule().fill(fluff).frame(width: 4.4, height: 11).position(x: 17, y: 1.5)
            Capsule().fill(Color(hex: 0xFF9EC0)).frame(width: 1.8, height: 7).position(x: 9, y: 2)
            Capsule().fill(Color(hex: 0xFF9EC0)).frame(width: 1.8, height: 7).position(x: 17, y: 2)
        })
    }
}

import SwiftUI

private let ember = Color(hex: 0xFF7A45)

extension MascotDefinition {
    static let flame = MascotDefinition(id: "flame", name: "Flame", bodyColor: ember) { _ in
        AnyView(ZStack {
            Polygon((13, 0), (17.4, 6), (18.4, 10), (7.6, 10), (8.6, 6)).fill(ember)
            Polygon((13, 3.6), (15.2, 7), (15.6, 10), (10.4, 10), (10.8, 7)).fill(Color(hex: 0xFFD166))
        })
    }
}

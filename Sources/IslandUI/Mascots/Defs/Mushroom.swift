import SwiftUI

private let cream = Color(hex: 0xF7E8D0)

/// A flat-bottomed mushroom cap in the 26x26 design space.
private struct CapShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 1.5, y: 10.2))
        path.addCurve(
            to: CGPoint(x: 24.5, y: 10.2), control1: CGPoint(x: 1.5, y: -1.5), control2: CGPoint(x: 24.5, y: -1.5))
        path.closeSubpath()
        return path
    }
}

extension MascotDefinition {
    static let mushroom = MascotDefinition(id: "mushroom", name: "Mushroom", bodyColor: cream) { _ in
        AnyView(ZStack {
            CapShape().fill(Color(hex: 0xFF5A5F))
            mascotDot(7.5, 6.4, 1.8, .white)
            mascotDot(13, 3.9, 1.6, .white)
            mascotDot(18.6, 6.6, 1.9, .white)
        })
    }
}

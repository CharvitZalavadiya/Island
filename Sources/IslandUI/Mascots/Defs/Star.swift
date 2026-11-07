import SwiftUI

private let gold = Color(hex: 0xFFD84D)

/// A five-point star centered at (cx, cy) in the 26x26 design space.
private struct StarShape: Shape {
    let cx: CGFloat, cy: CGFloat, outer: CGFloat, inner: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 0..<10 {
            let radius = i.isMultiple(of: 2) ? outer : inner
            let angle = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
            let point = CGPoint(x: cx + radius * cos(angle), y: cy + radius * sin(angle))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

extension MascotDefinition {
    static let star = MascotDefinition(id: "star", name: "Star", bodyColor: gold) { _ in
        AnyView(StarShape(cx: 13, cy: 2.4, outer: 3.6, inner: 1.5).fill(Color(hex: 0xFFF3A3)))
    }
}

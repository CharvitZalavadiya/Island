import SwiftUI

public enum MascotMood: CaseIterable {
    case focus, rest, done
}

/// One mascot: a color and a small accessory drawn over the shared blob body.
/// Accessories are drawn in a 26x26 design space with (0, 0) at the top-left, on top of the body and under the face.
public struct MascotDefinition: Identifiable {
    public let id: String
    public let name: String
    let bodyColor: Color
    let accessory: (MascotMood) -> AnyView
    /// A smiling face of its own. Nil for the classic mascots, which share the plain blob face.
    let emotion: MascotEmotion?

    public init(
        id: String, name: String, bodyColor: Color,
        accessory: @escaping (MascotMood) -> AnyView = { _ in AnyView(EmptyView()) }
    ) {
        self.init(id: id, name: name, bodyColor: bodyColor, emotion: nil, accessory: accessory)
    }

    init(
        id: String, name: String, bodyColor: Color, emotion: MascotEmotion?,
        accessory: @escaping (MascotMood) -> AnyView = { _ in AnyView(EmptyView()) }
    ) {
        self.id = id
        self.name = name
        self.bodyColor = bodyColor
        self.emotion = emotion
        self.accessory = accessory
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

/// A closed polygon whose points are absolute coordinates in the 26x26 design space.
struct Polygon: Shape {
    let points: [CGPoint]

    init(_ coordinates: (CGFloat, CGFloat)...) {
        points = coordinates.map { CGPoint(x: $0.0, y: $0.1) }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
}

/// A filled circle centered at (x, y) in the 26x26 design space.
func mascotDot(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ color: Color) -> some View {
    Circle().fill(color).frame(width: radius * 2, height: radius * 2).position(x: x, y: y)
}

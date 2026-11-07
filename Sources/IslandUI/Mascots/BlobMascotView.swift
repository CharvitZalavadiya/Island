import SwiftUI
import IslandCore

/// The shared silhouette: a rounded dome with a wavy, ghost-like bottom edge, in a 26x26 design space.
struct BlobBody: Shape {
    func path(in rect: CGRect) -> Path {
        let k: CGFloat = 0.5523 * 9  // control-point offset for a quarter circle of radius 9
        var path = Path()
        path.move(to: CGPoint(x: 4, y: 22))
        path.addLine(to: CGPoint(x: 4, y: 12))
        path.addCurve(
            to: CGPoint(x: 13, y: 3), control1: CGPoint(x: 4, y: 12 - k), control2: CGPoint(x: 13 - k, y: 3))
        path.addCurve(
            to: CGPoint(x: 22, y: 12), control1: CGPoint(x: 13 + k, y: 3), control2: CGPoint(x: 22, y: 12 - k))
        for (x, y) in [(22.0, 22.0), (19, 20), (16, 22), (13, 20), (10, 22), (7, 20)] {
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.closeSubpath()
        return path
    }
}

/// Two dot eyes plus a small change of expression per mood.
struct BlobFace: View {
    let mood: MascotMood
    private let ink = Color(red: 0.07, green: 0.07, blue: 0.07)
    private let eyeXs: [CGFloat] = [10, 16]

    var body: some View {
        ZStack {
            switch mood {
            case .focus:
                openEye(x: 10)
                openEye(x: 16)
                stroke { path in
                    path.move(to: CGPoint(x: 8.6, y: 6.8))
                    path.addLine(to: CGPoint(x: 12, y: 8.2))
                }
                stroke { path in
                    path.move(to: CGPoint(x: 17.4, y: 6.8))
                    path.addLine(to: CGPoint(x: 14, y: 8.2))
                }
            case .rest:
                ForEach(eyeXs, id: \.self) { x in
                    stroke { path in
                        path.move(to: CGPoint(x: x - 1.7, y: 12))
                        path.addQuadCurve(to: CGPoint(x: x + 1.7, y: 12), control: CGPoint(x: x, y: 14.2))
                    }
                }
            case .done:
                ForEach(eyeXs, id: \.self) { x in
                    stroke { path in
                        path.move(to: CGPoint(x: x - 1.7, y: 12.8))
                        path.addQuadCurve(to: CGPoint(x: x + 1.7, y: 12.8), control: CGPoint(x: x, y: 10.2))
                    }
                }
                stroke { path in
                    path.move(to: CGPoint(x: 10.5, y: 15.6))
                    path.addQuadCurve(to: CGPoint(x: 15.5, y: 15.6), control: CGPoint(x: 13, y: 18.6))
                }
            }
        }
    }

    private func openEye(x: CGFloat) -> some View {
        Circle().fill(ink).frame(width: 3.2, height: 3.2).position(x: x, y: 12)
    }

    private func stroke(_ build: @escaping (inout Path) -> Void) -> some View {
        Path { build(&$0) }
            .stroke(ink, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
    }
}

/// A blob buddy: the shared body and face with one mascot's color and accessory.
public struct BlobMascotView: View {
    private let definition: MascotDefinition
    private let mood: MascotMood
    private let size: CGFloat
    private let animated: Bool

    /// - Parameter animated: whether the mascot drifts about (and hops when celebrating). The drift is a Core Animation
    ///   loop, so it costs the app almost nothing; when off there is nothing running at all.
    public init(_ definition: MascotDefinition, mood: MascotMood, size: CGFloat = 26, animated: Bool = false) {
        self.definition = definition
        self.mood = mood
        self.size = size
        self.animated = animated
    }

    public var body: some View {
        if animated {
            // The drift is a Core Animation loop (no per-frame SwiftUI work). The view has a little margin so the
            // drift and accessories such as ears are not clipped; negative padding gives that space back to layout.
            DriftingView(celebrating: mood == .done, scale: size / 26) { figure.padding(6) }
                .frame(width: size + 12, height: size + 12)
                .padding(-6)
        } else {
            figure
        }
    }

    private var figure: some View {
        ZStack {
            BlobBody().fill(definition.bodyColor)
            definition.accessory(mood)
            if let emotion = definition.emotion {
                EmotionFace(emotion: emotion, mood: mood)
            } else {
                BlobFace(mood: mood)
            }
        }
        .frame(width: 26, height: 26)
        .scaleEffect(size / 26)
        .frame(width: size, height: size)
    }
}

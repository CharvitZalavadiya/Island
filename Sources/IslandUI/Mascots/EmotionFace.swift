import SwiftUI
import IslandCore

/// The smiling faces of the emotion mascots. Every one of them smiles; what differs is the feeling behind the smile.
enum MascotEmotion: CaseIterable {
    case happy, laughing, winking, loving, cool, shy, silly, starry, dreamy, zen, proud, joyful
}

/// An emotion mascot's face, drawn in the same 26x26 design space as the classic blob face. The mood changes it a
/// little: while resting the open eyes relax into soft arcs, and when a session is done there is a bigger grin and
/// sparkles.
struct EmotionFace: View {
    let emotion: MascotEmotion
    let mood: MascotMood

    private let ink = Color(red: 0.07, green: 0.07, blue: 0.07)
    private let cheek = Color(red: 1, green: 0.42, blue: 0.5)
    private let tongue = Color(red: 1, green: 0.45, blue: 0.55)

    var body: some View {
        ZStack {
            eyes
            mouth
            if emotion == .shy { blush }
            if mood == .done { sparkles }
        }
    }

    // MARK: Eyes

    @ViewBuilder
    private var eyes: some View {
        // Resting: the faces with plain round eyes close them softly.
        let relaxed = mood == .rest && [.happy, .winking, .silly, .joyful].contains(emotion)
        if relaxed {
            ForEach([10.0, 16.0], id: \.self) { x in downArc(x, 12.4) }
        } else {
            switch emotion {
            case .happy:
                dot(10, 12); dot(16, 12)
            case .laughing:
                upArc(10, 12.6); upArc(16, 12.6)
            case .winking:
                dot(10, 12); upArc(16, 12.4)
            case .loving:
                heart(10, 12, 2.0); heart(16, 12, 2.0)
            case .cool:
                sunglasses
            case .shy:
                downArc(10, 12.2); downArc(16, 12.2)
            case .silly:
                dot(10, 12); dot(16, 12, radius: 1.9)
            case .starry:
                star(10, 12, 2.5); star(16, 12, 2.5)
            case .dreamy:
                halfClosed(10, 12.4); halfClosed(16, 12.4)
            case .zen:
                downArc(10, 12.2); downArc(16, 12.2)
            case .proud:
                upArc(10, 12.6); upArc(16, 12.6)
                stroke { $0.move(to: CGPoint(x: 8.2, y: 8.8)); $0.addLine(to: CGPoint(x: 11.8, y: 8.4)) }
                stroke { $0.move(to: CGPoint(x: 17.8, y: 8.8)); $0.addLine(to: CGPoint(x: 14.2, y: 8.4)) }
            case .joyful:
                bigEye(10, 12); bigEye(16, 12)
            }
        }
    }

    // MARK: Mouth

    @ViewBuilder
    private var mouth: some View {
        let grin = mood == .done
        switch emotion {
        case .happy, .zen:
            if grin { openMouth(width: 3.4, depth: 3.4) } else { smile(width: 3.2, depth: 2.6) }
        case .laughing, .joyful:
            openMouth(width: 3.4, depth: 3.6)
        case .winking, .proud:
            if grin { openMouth(width: 3.4, depth: 3.2) } else { smirk }
        case .loving, .starry:
            if grin { openMouth(width: 3.4, depth: 3.4) } else { smile(width: 3.4, depth: 2.9) }
        case .cool:
            smirk
        case .shy:
            smile(width: 2.2, depth: 1.8)
        case .silly:
            openMouth(width: 3.2, depth: 3.4, withTongue: true)
        case .dreamy:
            smile(width: 2.0, depth: 1.6)
        }
    }

    // MARK: Pieces

    private func dot(_ x: CGFloat, _ y: CGFloat, radius: CGFloat = 1.6) -> some View {
        Circle().fill(ink).frame(width: radius * 2, height: radius * 2).position(x: x, y: y)
    }

    /// A happy closed eye, an arch: ∩
    private func upArc(_ x: CGFloat, _ y: CGFloat) -> some View {
        stroke { path in
            path.move(to: CGPoint(x: x - 1.9, y: y + 0.7))
            path.addQuadCurve(to: CGPoint(x: x + 1.9, y: y + 0.7), control: CGPoint(x: x, y: y - 2.0))
        }
    }

    /// A relaxed closed eye, a bowl: ◡
    private func downArc(_ x: CGFloat, _ y: CGFloat) -> some View {
        stroke { path in
            path.move(to: CGPoint(x: x - 1.9, y: y - 0.5))
            path.addQuadCurve(to: CGPoint(x: x + 1.9, y: y - 0.5), control: CGPoint(x: x, y: y + 1.9))
        }
    }

    /// A sleepy eye: a flat lid with the lower half of the eye showing under it.
    private func halfClosed(_ x: CGFloat, _ y: CGFloat) -> some View {
        ZStack {
            Circle().fill(ink).frame(width: 3.8, height: 3.8).position(x: x, y: y + 0.6)
                // Only the part below the lid shows.
                .mask(Rectangle().frame(width: 26, height: 12).position(x: 13, y: y - 0.5 + 6))
            stroke { path in
                path.move(to: CGPoint(x: x - 2.1, y: y - 0.5))
                path.addLine(to: CGPoint(x: x + 2.1, y: y - 0.5))
            }
        }
    }

    /// A wide eye with a white highlight.
    private func bigEye(_ x: CGFloat, _ y: CGFloat) -> some View {
        ZStack {
            Circle().fill(ink).frame(width: 4.2, height: 4.2)
            Circle().fill(.white).frame(width: 1.5, height: 1.5).offset(x: 0.8, y: -0.9)
        }
        .position(x: x, y: y)
    }

    private func heart(_ cx: CGFloat, _ cy: CGFloat, _ size: CGFloat) -> some View {
        Path { path in
            let r = size * 0.55
            path.addEllipse(in: CGRect(x: cx - size * 0.5 - r, y: cy - size * 0.15 - r, width: 2 * r, height: 2 * r))
            path.addEllipse(in: CGRect(x: cx + size * 0.5 - r, y: cy - size * 0.15 - r, width: 2 * r, height: 2 * r))
            path.move(to: CGPoint(x: cx - size * 1.03, y: cy + size * 0.02))
            path.addLine(to: CGPoint(x: cx + size * 1.03, y: cy + size * 0.02))
            path.addLine(to: CGPoint(x: cx, y: cy + size * 1.0))
            path.closeSubpath()
        }
        .fill(Color(red: 0.86, green: 0.1, blue: 0.25))
    }

    private func star(_ cx: CGFloat, _ cy: CGFloat, _ radius: CGFloat) -> some View {
        Path { path in
            for index in 0..<10 {
                let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / 5
                let length = index % 2 == 0 ? radius : radius * 0.45
                let point = CGPoint(x: cx + cos(angle) * length, y: cy + sin(angle) * length)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
        .fill(Color(red: 1, green: 0.85, blue: 0.1))
    }

    private var sunglasses: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 1.4).fill(ink).frame(width: 5.2, height: 3.8).position(x: 9.8, y: 12)
            RoundedRectangle(cornerRadius: 1.4).fill(ink).frame(width: 5.2, height: 3.8).position(x: 16.2, y: 12)
            stroke { path in
                path.move(to: CGPoint(x: 12.4, y: 11.3))
                path.addLine(to: CGPoint(x: 13.6, y: 11.3))
            }
            Capsule().fill(.white.opacity(0.55)).frame(width: 1.6, height: 0.8).position(x: 8.6, y: 11)
            Capsule().fill(.white.opacity(0.55)).frame(width: 1.6, height: 0.8).position(x: 15.0, y: 11)
        }
    }

    private var blush: some View {
        ZStack {
            Ellipse().fill(cheek.opacity(0.6)).frame(width: 3.4, height: 2).position(x: 7.4, y: 15)
            Ellipse().fill(cheek.opacity(0.6)).frame(width: 3.4, height: 2).position(x: 18.6, y: 15)
        }
    }

    private func smile(width: CGFloat, depth: CGFloat) -> some View {
        stroke { path in
            path.move(to: CGPoint(x: 13 - width, y: 15.3))
            path.addQuadCurve(to: CGPoint(x: 13 + width, y: 15.3), control: CGPoint(x: 13, y: 15.3 + depth))
        }
    }

    /// A smile pulled up on one side.
    private var smirk: some View {
        stroke { path in
            path.move(to: CGPoint(x: 10.2, y: 15.8))
            path.addQuadCurve(to: CGPoint(x: 16.4, y: 14.8), control: CGPoint(x: 13.4, y: 18.2))
        }
    }

    private func openMouth(width: CGFloat, depth: CGFloat, withTongue: Bool = false) -> some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 13 - width, y: 14.8))
                path.addLine(to: CGPoint(x: 13 + width, y: 14.8))
                path.addCurve(
                    to: CGPoint(x: 13 - width, y: 14.8),
                    control1: CGPoint(x: 13 + width, y: 14.8 + depth * 1.25),
                    control2: CGPoint(x: 13 - width, y: 14.8 + depth * 1.25))
                path.closeSubpath()
            }
            .fill(ink)
            Ellipse().fill(tongue).frame(width: width * 1.1, height: depth * 0.5)
                .position(x: 13, y: 14.8 + depth * 0.85)
                .opacity(withTongue ? 1 : 0.85)
        }
    }

    /// Two little four-pointed sparkles, for a finished session.
    private var sparkles: some View {
        ZStack {
            sparkle(4.2, 5.4, 1.7)
            sparkle(21.6, 6.2, 1.4)
        }
    }

    private func sparkle(_ cx: CGFloat, _ cy: CGFloat, _ radius: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: cx, y: cy - radius))
            path.addQuadCurve(to: CGPoint(x: cx + radius, y: cy), control: CGPoint(x: cx, y: cy))
            path.addQuadCurve(to: CGPoint(x: cx, y: cy + radius), control: CGPoint(x: cx, y: cy))
            path.addQuadCurve(to: CGPoint(x: cx - radius, y: cy), control: CGPoint(x: cx, y: cy))
            path.addQuadCurve(to: CGPoint(x: cx, y: cy - radius), control: CGPoint(x: cx, y: cy))
        }
        .fill(Color(red: 1, green: 0.9, blue: 0.3))
    }

    private func stroke(_ build: @escaping (inout Path) -> Void) -> some View {
        Path { build(&$0) }
            .stroke(ink, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
    }
}

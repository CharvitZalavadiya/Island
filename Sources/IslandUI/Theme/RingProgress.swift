import SwiftUI

/// A round progress ring with `content` in the middle. `fraction` is how much is left (1 is a full ring, shrinking to
/// 0); nil draws no ring at all. There is deliberately no animation: the value changes once a second and a SwiftUI
/// animation would cost far more than it adds.
struct RingProgress<Content: View>: View {
    let fraction: Double?
    let tint: Color
    var lineWidth: CGFloat = 5
    /// Show the faint full track behind the ring.
    var showsTrack = true
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            if fraction != nil, showsTrack {
                Circle().strokeBorder(tint.opacity(0.18), lineWidth: lineWidth)
            }
            if let fraction {
                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: 0, to: min(max(fraction, 0), 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            content
        }
    }
}

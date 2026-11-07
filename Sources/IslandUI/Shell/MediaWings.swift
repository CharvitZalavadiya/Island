import SwiftUI
import IslandCore

/// The media activity on the left wing: the icon of the app that is playing, inside a ring that fills as the track plays.
struct MediaIconRing: View {
    let player: NowPlayingController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            // A track with no length (a live stream) has an empty ring: the circle is still there around the icon.
            RingProgress(fraction: player.track?.fraction(at: context.date) ?? 0, tint: IslandTheme.tools, lineWidth: 2.5) {
                if let icon = player.sourceIcon {
                    Image(nsImage: icon).resizable().frame(width: 13, height: 13)
                } else {
                    Image(systemName: "music.note").font(.system(size: 10, weight: .bold)).foregroundStyle(IslandTheme.tools)
                }
            }
        }
        .frame(width: 22, height: 22)
    }
}

/// The media activity on the right wing: a little equalizer. It is made up, not measured (Island cannot hear what other
/// apps play); each bar rises and falls at its own pace, so it looks like music is playing.
///
/// The bars are animated by Core Animation directly, which runs the motion in the system's render process. (A SwiftUI
/// animation that repeats forever redraws inside Island on every frame, which cost about 5 % of a CPU core for a few bars.)
struct SpectrumBars: NSViewRepresentable {
    static let barWidth: CGFloat = 2.5
    static let gap: CGFloat = 2
    static let height: CGFloat = 14

    /// One bar's motion: how long a rise and fall takes, how low and how high it goes (a fraction of the full height),
    /// and how long it waits before starting. Five bars with different values never move in step.
    struct Motion {
        let duration: Double
        let low: CGFloat
        let high: CGFloat
        let delay: Double
    }

    static let motions = [
        Motion(duration: 0.55, low: 0.30, high: 1.00, delay: 0.00),
        Motion(duration: 0.42, low: 0.45, high: 0.85, delay: 0.10),
        Motion(duration: 0.70, low: 0.25, high: 1.00, delay: 0.05),
        Motion(duration: 0.48, low: 0.40, high: 0.90, delay: 0.20),
        Motion(duration: 0.62, low: 0.30, high: 0.80, delay: 0.15),
    ]

    static var width: CGFloat { CGFloat(motions.count) * barWidth + CGFloat(motions.count - 1) * gap }

    func makeNSView(context: Context) -> BarsView {
        BarsView(color: NSColor(IslandTheme.tools).cgColor)
    }

    func updateNSView(_ view: BarsView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: BarsView, context: Context) -> CGSize? {
        CGSize(width: Self.width, height: Self.height)
    }

    final class BarsView: NSView {
        private var bars: [CALayer] = []

        init(color: CGColor) {
            super.init(frame: NSRect(x: 0, y: 0, width: SpectrumBars.width, height: SpectrumBars.height))
            wantsLayer = true
            for (index, motion) in SpectrumBars.motions.enumerated() {
                let bar = CALayer()
                bar.backgroundColor = color
                bar.cornerRadius = SpectrumBars.barWidth / 2
                bar.frame = CGRect(
                    x: CGFloat(index) * (SpectrumBars.barWidth + SpectrumBars.gap), y: 0,
                    width: SpectrumBars.barWidth, height: SpectrumBars.height)
                bar.transform = CATransform3DMakeScale(1, motion.low, 1)
                layer?.addSublayer(bar)
                bars.append(bar)
            }
        }

        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            animate()
        }

        private func animate() {
            let now = CACurrentMediaTime()
            for (bar, motion) in zip(bars, SpectrumBars.motions) {
                bar.removeAllAnimations()
                let rise = CABasicAnimation(keyPath: "transform.scale.y")
                rise.fromValue = motion.low
                rise.toValue = motion.high
                rise.duration = motion.duration
                rise.autoreverses = true
                rise.repeatCount = .infinity
                rise.beginTime = now + motion.delay
                rise.fillMode = .backwards
                rise.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                bar.add(rise, forKey: "rise")
            }
        }
    }
}

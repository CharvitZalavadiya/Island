import AppKit
import SwiftUI
import IslandCore

/// Drifts a view about with a Core Animation keyframe loop (see `MascotMotion`).
///
/// SwiftUI would redraw the mascot on every frame of such a motion, which cost about 3.5% of a CPU core for as long as
/// a timer ran, however slowly it was updated. Here the mascot is drawn once, and Core Animation moves its layer in the
/// render server, so the app itself stays idle.
struct DriftingView<Content: View>: NSViewRepresentable {
    let celebrating: Bool
    /// Points per drawing unit (the mascot's size divided by 26).
    let scale: CGFloat
    let content: Content

    init(celebrating: Bool, scale: CGFloat, @ViewBuilder content: () -> Content) {
        self.celebrating = celebrating
        self.scale = scale
        self.content = content()
    }

    func makeNSView(context: Context) -> DriftHostView<Content> {
        DriftHostView(content: content)
    }

    func updateNSView(_ view: DriftHostView<Content>, context: Context) {
        view.update(content: content, celebrating: celebrating, scale: scale)
    }
}

final class DriftHostView<Content: View>: NSView {
    private let hosting: NSHostingView<Content>
    private var celebrating = false
    private var scale: CGFloat = 1
    private var installed: (celebrating: Bool, scale: CGFloat)?
    /// How many times the loop has been (re)installed; the tests use it to check that updates do not restart it.
    private(set) var installCount = 0

    init(content: Content) {
        hosting = NSHostingView(rootView: content)
        super.init(frame: .zero)
        wantsLayer = true
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = bounds
        addSubview(hosting)
    }

    required init?(coder: NSCoder) {
        fatalError("DriftHostView is created in code")
    }

    func update(content: Content, celebrating: Bool, scale: CGFloat) {
        hosting.rootView = content
        self.celebrating = celebrating
        self.scale = scale
        // Restart the loop only when it has to change, so it does not jump on every unrelated update.
        if installed?.celebrating != celebrating || installed?.scale != scale { installMotion() }
    }

    // A layer's animations are dropped when it leaves the screen, so put the loop back when the view returns.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { installMotion() }
    }

    private func installMotion() {
        guard let layer else { return }
        layer.removeAnimation(forKey: "drift")
        let frames = MascotMotion.keyframes(celebrating: celebrating, count: celebrating ? 48 : 480)
        let animation = CAKeyframeAnimation(keyPath: "transform.translation")
        // MascotMotion uses screen coordinates (negative y is up); a layer's y axis points up, so flip it.
        animation.values = frames.map {
            NSValue(size: CGSize(width: $0.width * scale, height: -$0.height * scale))
        }
        animation.duration = MascotMotion.loopSeconds(celebrating: celebrating)
        animation.repeatCount = .infinity
        animation.calculationMode = .linear
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "drift")
        installed = (celebrating, scale)
        installCount += 1
    }
}

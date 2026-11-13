import AppKit
import SwiftUI

/// What the person sees while an edge gesture changes something: macOS shows its own indicator for the keyboard's keys but not
/// for a change made like this, so Island shows a small one just under the notch.
@MainActor
protocol TrackpadFeedback: AnyObject {
    func show(symbol: String, fraction: Double?, text: String)
}

@Observable
@MainActor
final class TrackpadHUDModel {
    var symbol = "speaker.wave.2.fill"
    var fraction: Double?
    var text = ""
}

struct TrackpadHUDView: View {
    let model: TrackpadHUDModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 20)
            if let fraction = model.fraction {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule().fill(Color.white).frame(width: geometry.size.width * min(max(fraction, 0), 1))
                    }
                }
                .frame(height: 5)
            }
            Text(model.text)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: 44, maxWidth: model.fraction == nil ? .infinity : nil, alignment: model.fraction == nil ? .leading : .trailing)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(width: 230, height: 40)
        .background(Capsule().fill(Color.black))
        .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1))
    }
}

/// The little window for it: it never takes the mouse or the keyboard, floats over everything, and goes away by itself.
@MainActor
final class TrackpadHUDController: TrackpadFeedback {
    private let model = TrackpadHUDModel()
    private var panel: NSPanel?
    private var hiding: Task<Void, Never>?

    func show(symbol: String, fraction: Double?, text: String) {
        model.symbol = symbol
        model.fraction = fraction
        model.text = text
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        if !panel.isVisible { panel.alphaValue = 1 }
        panel.orderFrontRegardless()
        hiding?.cancel()
        hiding = Task { @MainActor [weak panel] in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            guard !Task.isCancelled else { return }
            panel?.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 230, height: 40), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: TrackpadHUDView(model: model))
        return panel
    }

    /// Centred under the notch (or under the menu bar on a Mac without one).
    private func position(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let top = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - top - size.height - 14))
    }
}

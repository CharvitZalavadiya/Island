import AppKit

/// Where Island's windows sit above the others. The island is above the menu bar; a dialog Island opens (a file chooser, a
/// web page's alert) is above the island, so focus mode's big card and its backdrop can never hide one.
enum IslandWindowLevel {
    static let island = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
    static let dialog = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
}

/// What focus mode asks of the Mac's app switching, so it can be tried without really switching apps.
@MainActor
protocol AppActivating: AnyObject {
    /// The app the person is working in.
    var frontmostApplication: NSRunningApplication? { get }
    /// Makes Island the active app, so the keyboard (Escape) reaches it.
    func activateIsland()
    /// Gives the keyboard back to an app.
    func activate(_ app: NSRunningApplication)
}

@MainActor
final class SystemAppActivation: AppActivating {
    var frontmostApplication: NSRunningApplication? { NSWorkspace.shared.frontmostApplication }
    func activateIsland() { NSApp.activate() }
    func activate(_ app: NSRunningApplication) { _ = app.activate(from: NSRunningApplication.current, options: []) }
}

/// The blurred, dimmed layer over the whole screen behind the focus card: everything else on the screen is out of focus. A click
/// anywhere on it (it covers the whole screen but the card) is how the person leaves.
final class BackdropView: NSVisualEffectView {
    var onClick: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { onClick?() }
    override func otherMouseDown(with event: NSEvent) { onClick?() }
}

@MainActor
final class FocusBackdrop {
    private let window: NSPanel
    let view = BackdropView(frame: .zero)
    private let opacity: CGFloat
    private let animates: Bool
    /// Tells a `hide` that a later `show` has already brought the window back, so it must not remove it.
    private var generation = 0

    var onClick: (() -> Void)? {
        get { view.onClick }
        set { view.onClick = newValue }
    }
    var windowNumber: Int { window.windowNumber }
    var frame: CGRect { window.frame }
    var isShown: Bool { window.isVisible }
    var level: NSWindow.Level { window.level }

    /// `dimming` darkens the blur; `opacity` is how strongly the whole layer shows (1 for real; tests use 0 to stay invisible).
    init(dimming: CGFloat = 0.34, opacity: CGFloat = 1, animates: Bool = true) {
        self.opacity = opacity
        self.animates = animates
        window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // `isFloatingPanel` resets the level, so the level comes after it.
        window.isFloatingPanel = true
        window.level = IslandWindowLevel.island
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.isMovable = false
        window.becomesKeyOnlyIfNeeded = true

        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        let dim = NSView(frame: .zero)
        dim.wantsLayer = true
        dim.layer?.backgroundColor = NSColor.black.withAlphaComponent(dimming).cgColor
        dim.frame = view.bounds
        dim.autoresizingMask = [.width, .height]
        view.addSubview(dim)
        window.contentView = view
    }

    func show(over frame: CGRect) {
        generation += 1
        window.setFrame(frame, display: false)
        window.alphaValue = animates ? 0 : opacity
        window.orderFrontRegardless()
        guard animates else { return }
        let target = opacity
        let window = self.window
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window.animator().alphaValue = target
        }
    }

    func move(to frame: CGRect) {
        if window.frame != frame { window.setFrame(frame, display: true) }
    }

    func hide() {
        generation += 1
        let mine = generation
        let window = self.window
        guard animates, window.isVisible else {
            window.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { if self?.generation == mine { window.orderOut(nil) } }
        })
    }
}

/// Focus mode's stage: while it shows, everything else on the screen is blurred and dimmed, and the island is a big card in
/// the middle, with the keyboard. It ends when the person presses Escape, clicks anywhere outside the card, or leaves for
/// another app, and then the keyboard goes back to the app they were working in. (What the island looked like before — closed,
/// open, pinned, big — is not touched while this shows, so it is there again when this ends.)
@MainActor
final class FocusStage {
    private(set) var isShowing = false
    /// Whether it is still watching the keyboard and the active app: only while it shows, so nothing is left behind afterwards.
    var isListening: Bool { keyMonitor != nil || resignObserver != nil }
    /// The stage ended by itself (Escape, a click outside, leaving for another app): the owner must clear its focus-mode flag.
    var onExit: (() -> Void)?

    let backdrop: FocusBackdrop
    private let activation: AppActivating
    /// Island may lose the keyboard for a moment just as focus mode starts; that must not end it at once.
    private let grace: TimeInterval
    private let now: () -> Date
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var previousApp: NSRunningApplication?
    private var enteredAt = Date.distantPast
    private weak var panel: NSPanel?

    init(
        activation: AppActivating? = nil, backdrop: FocusBackdrop? = nil,
        grace: TimeInterval = 0.6, now: @escaping () -> Date = { Date() }
    ) {
        self.activation = activation ?? SystemAppActivation()
        self.backdrop = backdrop ?? FocusBackdrop()
        self.grace = grace
        self.now = now
    }

    /// Starts: blurs the screen, puts `panel` (the island) in front of the blur, and takes the keyboard.
    func show(panel: NSPanel, over screenFrame: CGRect) {
        guard !isShowing else {
            backdrop.move(to: screenFrame)
            return
        }
        isShowing = true
        self.panel = panel
        let front = activation.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        enteredAt = now()
        backdrop.onClick = { [weak self] in self?.leave(restoreFocus: true) }
        backdrop.show(over: screenFrame)
        panel.order(.above, relativeTo: backdrop.windowNumber)
        activation.activateIsland()
        panel.makeKey()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
            return consumed ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.appResignedActive() }
        }
    }

    /// The screen changed (a display was plugged in or out): the blur follows it.
    func move(to screenFrame: CGRect) {
        guard isShowing else { return }
        backdrop.move(to: screenFrame)
    }

    /// Ends the stage when the owner asked for it (a button), handing the keyboard back to the app the person was in.
    func hide(restoreFocus: Bool) {
        guard isShowing else { return }
        isShowing = false
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        backdrop.hide()
        if restoreFocus, let app = previousApp { activation.activate(app) }
        previousApp = nil
        panel = nil
    }

    /// Escape ends it. Only a plain Escape in the island itself: not one meant for a dialog that is open, and not Escape with a
    /// modifier key held. Returns whether it took the key; anything else goes on to whatever it was meant for.
    func handleKey(_ event: NSEvent) -> Bool {
        guard isShowing, event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
            NSApp.modalWindow == nil, let panel, event.window === panel
        else { return false }
        leave(restoreFocus: true)
        return true
    }

    /// Cmd-Tab or a click on the Dock moved the keyboard to another app on purpose: leave, without taking it back.
    private func appResignedActive() {
        guard isShowing, now().timeIntervalSince(enteredAt) >= grace else { return }
        leave(restoreFocus: false)
    }

    private func leave(restoreFocus: Bool) {
        guard isShowing else { return }
        hide(restoreFocus: restoreFocus)
        onExit?()
    }
}

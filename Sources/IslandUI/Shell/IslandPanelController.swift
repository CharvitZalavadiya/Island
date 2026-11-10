import AppKit
import SwiftUI
import IslandCore

/// A borderless panel that floats just above the menu bar without taking focus from other apps.
final class IslandPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        // So that mouse movements over the island reach the app's own event monitor (hover detection, see
        // `IslandPanelController.startPointerMonitoring`); movements over other apps' windows reach the global one.
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosts the SwiftUI content and reports pointer movement and clicks.
final class PanelContentView: NSView {
    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?
    var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    var onContextMenu: ((NSEvent) -> Void)?
    var onDragEntered: (() -> Void)?
    var onDragExited: (() -> Void)?
    var onDropFiles: (([URL]) -> Void)?
    /// While true (island collapsed) this view takes the mouse itself, so a click always reaches `onClick`.
    var interceptsMouse = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("PanelContentView is created in code")
    }

    // Files dropped on the island go to the shelf. Reporting `.copy` tells the sender the originals stay where they are.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEntered?()
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExited?()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = (sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { return false }
        onDropFiles?(urls)
        return true
    }

    /// Reports the pointer arriving and leaving. `.activeAlways` is what makes this work while Island is in the
    /// background, which is nearly always: a window only gets mouse-moved events while its app is active.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onPointerEntered?() }
    override func mouseExited(with event: NSEvent) { onPointerExited?() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        interceptsMouse ? (frame.contains(point) ? self : nil) : super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) { onClick?(); super.mouseDown(with: event) }
    override func rightMouseDown(with event: NSEvent) { onContextMenu?(event) }
}

@MainActor
public final class IslandPanelController: NSObject {
    private let model: IslandModel
    private let services: IslandServices
    private var machine: ExpansionStateMachine
    private let panel = IslandPanel()
    private let content = PanelContentView(frame: .zero)
    private var collapseTimer: Timer?
    /// Runs only while the island is open or pinned, to notice Mission Control appearing over it (or going away).
    private var suspensionTimer: Timer?
    private var scrollMonitor: Any?
    private var pointerMonitors: [Any] = []
    private var pointerIsOverIsland = false
    // Dragging files toward the notch (see `startFileDragMonitoring`).
    private var fileDrag = FileDragDetector()
    private var dragWatchTimer: Timer?
    /// How far from the closed island (sideways, and downwards from the top of the screen) a dragged file opens the Shelf.
    private static let fileDragReach = CGSize(width: 170, height: 90)
    private var scrollAccumulator: CGFloat = 0
    private var scrollDidSwitch = false

    public init(model: IslandModel, services: IslandServices) {
        self.model = model
        self.services = services
        let settings = model.settings.settings
        machine = ExpansionStateMachine(hoverOpens: settings.hoverOpens, collapseDelay: settings.collapseDelay)
        super.init()

        let hosting = NSHostingView(rootView: RootView(model: model, services: services))
        hosting.sizingOptions = []
        hosting.frame = content.bounds
        hosting.autoresizingMask = [.width, .height]
        content.addSubview(hosting)
        panel.contentView = content

        // Hovering comes from two sources that share one state: the tracking area (works while Island is in the
        // background) and the mouse monitors (see `startPointerMonitoring`), which repair a state that has gone stale.
        // Before the island decides to open it checks whether Mission Control is on screen, because it must stay
        // closed there (the wings with the mascot and time may stay: they follow what is live, not the mode).
        // The pointer over the island holds an event banner's countdown; a click on the closed island's banner
        // dismisses it instead of opening the island.
        content.onPointerEntered = { [weak self] in self?.setPointerOverIsland(true) }
        content.onPointerExited = { [weak self] in
            guard let self else { return }
            // A tracking region can report an exit while the pointer is still inside (the panel keeps changing size),
            // so where the pointer really is decides.
            if self.pointerIsReallyOverIsland() { return }
            self.setPointerOverIsland(false)
        }
        content.onClick = { [weak self] in
            guard let self else { return }
            self.refreshSuspension()
            if self.model.alert != nil, self.model.mode == .collapsed {
                self.services.alerts.dismissNow()
                return
            }
            self.send(.clicked)
        }
        content.onContextMenu = { [weak self] event in self?.showContextMenu(for: event) }
        // Dragging files toward the notch opens the island on the Shelf tab (whatever tab it was on, even if it is
        // already open or pinned), and dropping them stashes them.
        content.onDragEntered = { [weak self] in
            guard let self else { return }
            self.refreshSuspension()
            self.model.fileDragEntered()
            self.send(.clicked)
        }
        content.onDragExited = { [weak self] in self?.send(.pointerExited) }
        content.onDropFiles = { [weak self] urls in
            self?.services.shelf.add(urls: urls)
        }
    }

    public func show() {
        updateFrame()
        panel.orderFrontRegardless()
        observeModel()
        startPointerMonitoring()
        startFileDragMonitoring()
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.handleScroll(event) }
            return event
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFrame() }
        }
    }

    // MARK: Hovering

    /// Watches mouse movements, in this app and in others, and keeps the pointer state right if the tracking area missed
    /// or mis-reported something (for example while another window of Island, like Settings, is the key window). It
    /// cannot replace the tracking area: movements over Island's own panel are only delivered to it while Island is the
    /// active app, which it almost never is.
    private func startPointerMonitoring() {
        guard pointerMonitors.isEmpty else { return }
        let moved: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: moved) {
            pointerMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { event in
            moved(event)
            return event
        }) {
            pointerMonitors.append(local)
        }
    }

    private func pointerIsReallyOverIsland() -> Bool {
        // A pointer pushed against the top edge of the screen sits exactly on the panel's top edge, which a plain
        // `contains` would count as outside, so the test is a point wider on every side.
        panel.frame.insetBy(dx: -1, dy: -1).contains(NSEvent.mouseLocation)
    }

    /// A mouse movement was seen (by the monitors, which only get events while Island is the active app or the pointer is
    /// over another app): repair the state if it no longer matches where the pointer is.
    private func pointerMoved() {
        setPointerOverIsland(pointerIsReallyOverIsland())
    }

    /// The single place the pointer state changes, whether the news came from the tracking area or the monitors.
    private func setPointerOverIsland(_ inside: Bool) {
        guard inside != pointerIsOverIsland else { return }
        pointerIsOverIsland = inside
        if inside {
            refreshSuspension()
            services.alerts.holdDismiss(true)
            send(.pointerEntered)
        } else {
            services.alerts.holdDismiss(false)
            send(.pointerExited)
        }
    }

    // MARK: Dragging files toward the notch

    /// While files are dragged from another app (Finder, say), the island opens on the Shelf as soon as the pointer comes
    /// near the notch, whatever tab was open last and whatever the hover setting says, so the files can be dropped
    /// straight onto it. Without this the pointer has to reach the small closed island itself, and dragging to the top of
    /// the screen can bring up Mission Control first.
    ///
    /// A drag is recognised the way other drop-zone apps do it: the drag pasteboard changes after the mouse button went
    /// down and holds file URLs. (The pasteboard also keeps the files of an older drag, so it cannot be looked at alone.)
    private func startFileDragMonitoring() {
        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseButtonWentDown() }
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseButtonWentUp() }
        }
        pointerMonitors.append(contentsOf: [down, up].compactMap { $0 })
    }

    /// The button went down somewhere. While it stays down, a light timer watches for a drag of files: while a drag
    /// session is running the system does not reliably hand drag events to global monitors, so the pointer position and
    /// the drag pasteboard are looked at directly. The timer only exists while a button is held.
    private func mouseButtonWentDown() {
        fileDrag.buttonWentDown(pasteboardChangeCount: NSPasteboard(name: .drag).changeCount)
        guard dragWatchTimer == nil else { return }
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watchDrag() }
        }
        RunLoop.main.add(timer, forMode: .common)
        dragWatchTimer = timer
    }

    private func mouseButtonWentUp() {
        if NSEvent.pressedMouseButtons & 1 == 0 { watchDrag() }
    }

    private func watchDrag() {
        let held = NSEvent.pressedMouseButtons & 1 != 0
        let board = NSPasteboard(name: .drag)
        let reach = Self.fileDragReach
        let result = fileDrag.poll(
            buttonHeld: held, pasteboardChangeCount: board.changeCount,
            pasteboardHasFiles: { board.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) },
            pointer: NSEvent.mouseLocation, zone: panel.frame.insetBy(dx: -reach.width, dy: -reach.height))
        if !held {
            dragWatchTimer?.invalidate()
            dragWatchTimer = nil
        }
        switch result {
        case .nothing:
            break
        case .nearNotch:
            guard model.mode == .collapsed else { return }
            refreshSuspension()
            guard !machine.isSuspended else { return }
            model.fileDragEntered()
            send(.clicked)
        case .ended:
            // The files were not dropped on the island, so it closes again (a drop on it keeps it open until the
            // pointer leaves).
            guard model.mode == .expanded, !panel.frame.insetBy(dx: -1, dy: -1).contains(NSEvent.mouseLocation) else { return }
            pointerIsOverIsland = false
            send(.pointerExited)
        }
    }

    // MARK: Expansion

    private func send(_ event: ExpansionEvent) {
        apply(machine.handle(event))
    }

    /// Runs what the state machine asked for (a collapse timer), and shows the mode it settled on.
    private func apply(_ effect: ExpansionEffect) {
        switch effect {
        case .none:
            break
        case .cancelCollapse:
            collapseTimer?.invalidate()
            collapseTimer = nil
        case .scheduleCollapse(let delay):
            collapseTimer?.invalidate()
            collapseTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.send(.collapseDelayElapsed) }
            }
        }
        if model.mode != machine.mode {
            model.mode = machine.mode
            // Opening the island is a good moment to re-read whether the Mac is being kept awake.
            if machine.mode == .expanded { services.keepAwake.refresh() }
        }
        updateSuspensionWatch()
    }

    // MARK: Mission Control

    /// Asks macOS whether Mission Control is showing and tells the state machine, which closes the island if so.
    private func refreshSuspension() {
        apply(machine.setSuspended(MissionControl.isActive()))
    }

    /// A pinned island that Mission Control closed must come back when it ends, so the check keeps running while the
    /// island is pinned even though it is closed; otherwise it runs only while the island is open. An idle,
    /// closed island checks nothing at all.
    private func updateSuspensionWatch() {
        let needed = machine.mode == .expanded || machine.isPinned
        if needed, suspensionTimer == nil {
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshSuspension() }
            }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            suspensionTimer = timer
        } else if !needed {
            suspensionTimer?.invalidate()
            suspensionTimer = nil
        }
    }

    // MARK: Frame

    /// Resizes the panel with the standard window animation.
    private func setPanelFrame(_ frame: CGRect) {
        // The standard window resize animation: it keeps the pointer-tracking region in step with the window. (An
        // `animator()`-driven resize with custom timing looked smoother on paper but lost the pointer after a few
        // open/close cycles, so hovering stopped opening the island.)
        panel.setFrame(frame, display: true, animate: panel.isVisible)
    }

    /// The screen with a notch if there is one, otherwise the main screen.
    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func updateFrame() {
        guard let screen = targetScreen() else { return }
        let notch = NotchGeometry.notchRect(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxLeftWidth: screen.auxiliaryTopLeftArea?.width ?? 0,
            auxRightWidth: screen.auxiliaryTopRightArea?.width ?? 0)
        model.topInset = notch?.height ?? 8

        let frame: CGRect
        switch model.mode {
        case .collapsed:
            if model.alert != nil {
                frame = NotchGeometry.alertFrame(notch: notch, screenFrame: screen.frame, size: NotchGeometry.alertSize)
            } else {
                let wings = WingLayout.widths(for: model.activities)
                frame = NotchGeometry.collapsedFrame(
                    notch: notch, screenFrame: screen.frame, leftWing: wings.left, rightWing: wings.right)
            }
        case .expanded:
            // Max mode is most of the screen; the content is laid out at that size too (RootView reads it from the model).
            let size = model.isMax
                ? NotchGeometry.maxSize(screenFrame: screen.frame, minimum: IslandMetrics.expandedSize)
                : IslandMetrics.expandedSize
            if model.contentSize != size { model.contentSize = size }
            frame = NotchGeometry.expandedFrame(notch: notch, screenFrame: screen.frame, size: size)
        }
        content.interceptsMouse = model.mode == .collapsed
        if panel.frame != frame {
            setPanelFrame(frame)
        }
    }

    /// Re-runs `modelDidChange` whenever the mode, the live activities or the settings change.
    private func observeModel() {
        withObservationTracking {
            _ = model.activities
            _ = model.alert
            _ = model.mode
            _ = model.settings.settings
            _ = model.isPinned
            _ = model.isMax
        } onChange: { [weak self] in
            // `onChange` fires before the new value lands, so hop to the next main-actor turn.
            Task { @MainActor [weak self] in
                self?.modelDidChange()
                self?.observeModel()
            }
        }
    }

    private func modelDidChange() {
        let settings = model.settings.settings
        machine.hoverOpens = settings.hoverOpens
        machine.collapseDelay = settings.collapseDelay
        // Max mode keeps the island open exactly as a pin does (the pin icon itself is the person's own choice).
        let keepOpen = model.isPinned || model.isMax
        if keepOpen != machine.isPinned { apply(machine.setPinned(keepOpen)) }
        updateFrame()
    }

    // MARK: Swipe between tabs

    private func handleScroll(_ event: NSEvent) {
        // Sideways scrolling belongs to the page while the Browser tab is open.
        guard event.window === panel, model.mode == .expanded, model.selectedTab != .browser else { return }
        if event.phase == .began {
            scrollAccumulator = 0
            scrollDidSwitch = false
        }
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return }
        scrollAccumulator += event.scrollingDeltaX
        if !scrollDidSwitch, abs(scrollAccumulator) > 60 {
            model.selectAdjacentTab(scrollAccumulator < 0 ? 1 : -1)
            scrollDidSwitch = true
        }
        if event.phase == .ended || event.phase == .cancelled {
            scrollAccumulator = 0
            scrollDidSwitch = false
        }
    }

    // MARK: Right-click menu

    private func showContextMenu(for event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Island", action: #selector(quit), keyEquivalent: "").target = self
        NSMenu.popUpContextMenu(menu, with: event, for: content)
    }

    @objc private func openSettings() {
        services.showSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

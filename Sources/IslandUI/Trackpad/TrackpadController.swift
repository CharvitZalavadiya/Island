import AppKit
import CoreGraphics
import Foundation
import IslandCore
import Observation

/// Something that can be moved through (the song or video that is playing).
@MainActor
protocol TrackSeeking: AnyObject {
    /// Starts or stops listening to what is playing. Island only listens while something wants to.
    func listen(_ on: Bool)
    /// Where it is now and how long it is, or nil when nothing is playing that can be moved through.
    var seekState: (elapsed: TimeInterval, duration: TimeInterval?)? { get }
    func seek(to seconds: TimeInterval)
}

extension NowPlayingController: TrackSeeking {
    func listen(_ on: Bool) {
        if on { start(for: .trackpad) } else { stop(for: .trackpad) }
    }

    var seekState: (elapsed: TimeInterval, duration: TimeInterval?)? {
        guard let track, track.isSeekable else { return nil }
        return (track.elapsed(at: Date()), track.duration)
    }
}

/// Edge gestures on the trackpad: slide one finger along an edge to change the volume or the brightness, or to move through
/// what is playing. What each edge does is set in the Trackpad tab. See `TrackpadGestureEngine` for what counts as a gesture.
@Observable
@MainActor
final class TrackpadController {
    enum Status: Equatable {
        case off
        case running
        case noTrackpad
        case unavailable(String)
    }

    private(set) var status = Status.off
    private(set) var device: TrackpadDevice?
    /// The fingers on the pad, for the picture in the Trackpad tab (only kept up to date while that tab is on screen).
    private(set) var touches: [TrackpadTouch] = []
    private(set) var framesSeen = 0
    /// The edge a gesture is going on at now.
    private(set) var edgeInUse: TrackpadEdge?
    /// The tap that was seen last, so the popup can show it was noticed (`id` changes with every tap, even of the same kind).
    struct SeenTap: Equatable {
        var trigger: TrackpadTapTrigger
        var id: Int
    }
    private(set) var lastTap: SeenTap?
    /// The person's own Shortcuts, for choosing one (filled in by `loadShortcuts`).
    private(set) var shortcutNames: [String] = []

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let source: TouchSource
    @ObservationIgnored private let freeze: PointerFreezing
    @ObservationIgnored private let system: AudioSystem
    @ObservationIgnored private let brightness: BrightnessControlling
    @ObservationIgnored private let seeker: TrackSeeking
    @ObservationIgnored private let feedback: TrackpadFeedback
    @ObservationIgnored private let runner: TrackpadActionPerforming
    @ObservationIgnored private let shortcutLister: () async -> [String]
    @ObservationIgnored private var tapCount = 0
    @ObservationIgnored private let now: () -> TimeInterval
    @ObservationIgnored let pipeline: TrackpadPipeline

    /// A popup is open that shows the fingers (Slide gestures), or one that shows every tap (Tap gestures).
    @ObservationIgnored private var previewingTouches = false
    @ObservationIgnored private var previewingTaps = false
    private var previewing: Bool { previewingTouches || previewingTaps }
    @ObservationIgnored private var sourceRunning = false
    @ObservationIgnored private var preview: Timer?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    /// What the gesture that is going on started from, and how far it has gone.
    private struct Gesture {
        var edge: TrackpadEdge
        var action: TrackpadAction
        var base: Double
        var duration: TimeInterval?
        var travelled = 0.0
        var pending = 0.0
        var lastApplied = TimeInterval.zero
        var lastSeek = TimeInterval.zero
    }
    @ObservationIgnored private var gesture: Gesture?
    @ObservationIgnored private var toldAbout: Set<TrackpadAction> = []

    /// How often a change is passed on to the volume, the screen or the player at most (the pad reports far more often).
    private static let applyEvery = 0.016
    private static let seekEvery = 0.25

    init(
        settings: SettingsStore, seeker: TrackSeeking, source: TouchSource = MultitouchSource(),
        freeze: PointerFreezing = PointerFreeze(), system: AudioSystem = CoreAudioSystem(),
        brightness: BrightnessControlling = DisplayServicesBrightness(), feedback: TrackpadFeedback? = nil,
        runner: TrackpadActionPerforming? = nil, shortcutLister: @escaping () async -> [String] = { await ShortcutsList.load() },
        pipeline: TrackpadPipeline? = nil, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.settings = settings
        self.seeker = seeker
        self.source = source
        self.freeze = freeze
        self.system = system
        self.brightness = brightness
        self.feedback = feedback ?? TrackpadHUDController()
        self.runner = runner ?? SystemActionRunner()
        self.shortcutLister = shortcutLister
        self.now = now
        self.pipeline = pipeline ?? TrackpadPipeline(config: Self.config(settings.settings, previewing: false), freeze: freeze)
        self.pipeline.onEvent = { [weak self] event in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.apply(event) } }
        }
        self.pipeline.onTap = { [weak self] trigger in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.apply(tap: trigger) } }
        }
    }

    // MARK: What is set

    var isEnabled: Bool { settings.settings.trackpadEnabled }

    func action(for edge: TrackpadEdge) -> TrackpadAction { settings.settings.trackpadAction(for: edge) }
    func isReversed(_ edge: TrackpadEdge) -> Bool { settings.settings.trackpadIsReversed(edge) }

    func setEnabled(_ on: Bool) {
        settings.update { $0.trackpadEnabled = on }
        refresh()
    }

    func setAction(_ action: TrackpadAction, for edge: TrackpadEdge) {
        settings.update { $0.trackpadActions[edge.rawValue] = action.rawValue }
        refresh()
    }

    func setReversed(_ reversed: Bool, for edge: TrackpadEdge) {
        settings.update {
            $0.trackpadReversedEdges.removeAll { $0 == edge.rawValue }
            if reversed { $0.trackpadReversedEdges.append(edge.rawValue) }
        }
    }

    func setEdgeMM(_ value: Double) {
        settings.update { $0.trackpadEdgeMM = min(max(value, TrackpadDefaults.edgeMMRange.lowerBound), TrackpadDefaults.edgeMMRange.upperBound) }
        refresh()
    }

    func setSensitivity(_ value: Double) {
        settings.update {
            $0.trackpadSensitivity = min(max(value, TrackpadDefaults.sensitivityRange.lowerBound), TrackpadDefaults.sensitivityRange.upperBound)
        }
    }

    // MARK: What is set for taps

    var isTapsEnabled: Bool { settings.settings.trackpadTapsEnabled }
    func tapAction(for trigger: TrackpadTapTrigger) -> TrackpadTapAction { settings.settings.trackpadTapAction(for: trigger) }
    func tapApp(for trigger: TrackpadTapTrigger) -> String? { settings.settings.trackpadTapApp(for: trigger) }
    func tapShortcut(for trigger: TrackpadTapTrigger) -> String? { settings.settings.trackpadTapShortcut(for: trigger) }

    func setTapsEnabled(_ on: Bool) {
        settings.update { $0.trackpadTapsEnabled = on }
        refresh()
    }

    func setTapAction(_ action: TrackpadTapAction, for trigger: TrackpadTapTrigger) {
        settings.update { $0.trackpadTapActions[trigger.id] = action.rawValue }
        refresh()
    }

    func setTapApp(_ path: String?, for trigger: TrackpadTapTrigger) {
        settings.update { $0.trackpadTapApps[trigger.id] = path ?? "" }
    }

    func setTapShortcut(_ name: String?, for trigger: TrackpadTapTrigger) {
        settings.update { $0.trackpadTapShortcuts[trigger.id] = name ?? "" }
    }

    /// Looks up the person's Shortcuts, for the list to choose from.
    func loadShortcuts() async { shortcutNames = await shortcutLister() }

    var hasAccessibility: Bool { runner.hasAccessibility }
    func requestAccessibility() { runner.requestAccessibility() }

    /// macOS itself can do something when three fingers tap (look a word up); then it would happen along with the person's choice.
    var systemThreeFingerTapIsOn: Bool {
        ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"].contains {
            (UserDefaults(suiteName: $0)?.integer(forKey: "TrackpadThreeFingerTapGesture") ?? 0) != 0
        }
    }

    /// While the Tap gestures popup is open every tap is followed, so it can show it was noticed; only the ones that do something act.
    private static func config(_ settings: IslandCore.Settings, previewing: Bool) -> TrackpadPipeline.Config {
        TrackpadPipeline.Config(
            activeEdges: settings.trackpadActiveEdges, edgeMM: settings.trackpadEdgeMM,
            wantedTaps: previewing ? Set(TrackpadTapTrigger.all) : settings.trackpadWantedTaps)
    }

    // MARK: Starting and stopping

    /// Called once at launch.
    func start() {
        // If Island was stopped in the middle of a gesture, the pointer may still be held: give it back first of all.
        freeze.release()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartAfterWake() }
        }
        refresh()
    }

    /// The Slide gestures popup is open: follow the fingers so they can be shown, even with the gestures switched off.
    func setPreviewing(_ on: Bool) {
        previewingTouches = on
        refresh()
    }

    /// The Tap gestures popup is open: follow every tap (not only the ones that do something) so each can be shown as it is noticed.
    func setTapPreviewing(_ on: Bool) {
        previewingTaps = on
        refresh()
    }

    /// Called when Island quits.
    func shutdown() {
        stopSource()
        freeze.release()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }

    private func refresh() {
        let current = settings.settings
        pipeline.update(Self.config(current, previewing: previewingTaps), gesturesOn: current.trackpadEnabled)
        seeker.listen(current.trackpadEnabled && current.trackpadActiveEdges.contains { current.trackpadAction(for: $0) == .seek })
        if current.trackpadEnabled || !current.trackpadWantedTaps.isEmpty || previewing {
            startSourceIfNeeded()
        } else {
            stopSource()
        }
        updatePreviewTimer()
    }

    private func startSourceIfNeeded() {
        guard !sourceRunning else { return }
        switch source.start({ [pipeline] frame in pipeline.process(frame) }) {
        case .success(let found):
            device = found
            status = .running
            sourceRunning = true
        case .failure(.noTrackpad):
            device = nil
            status = .noTrackpad
        case .failure(.unavailable(let message)):
            device = nil
            status = .unavailable(message)
        }
    }

    private func stopSource() {
        if sourceRunning { source.stop() }
        sourceRunning = false
        pipeline.reset()
        gesture = nil
        edgeInUse = nil
        touches = []
        status = .off
        preview?.invalidate()
        preview = nil
    }

    /// After the Mac wakes the trackpad has to be asked for again.
    private func restartAfterWake() {
        guard sourceRunning else { return }
        source.stop()
        sourceRunning = false
        pipeline.reset()
        startSourceIfNeeded()
    }

    private func updatePreviewTimer() {
        guard previewing, sourceRunning else {
            preview?.invalidate()
            preview = nil
            if !touches.isEmpty { touches = [] }
            return
        }
        guard preview == nil else { return }
        preview = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let snapshot = self.pipeline.snapshot()
                if snapshot.touches != self.touches { self.touches = snapshot.touches }
                if snapshot.frames != self.framesSeen { self.framesSeen = snapshot.frames }
            }
        }
    }

    // MARK: Gestures

    /// Does what an event asks for. Public to the module so it can be tried without a trackpad.
    func apply(_ event: TrackpadGestureEvent) {
        guard isEnabled else { return }
        switch event {
        case .candidateStarted:
            break
        case .began(let edge):
            edgeInUse = edge
            begin(edge)
        case .moved(let edge, let delta):
            guard var gesture, gesture.edge == edge else { return }
            let signed = delta * (isReversed(edge) ? -1 : 1) * settings.settings.trackpadSensitivity
            gesture.pending += signed
            self.gesture = gesture
            if now() - gesture.lastApplied >= Self.applyEvery { flush() }
        case .ended(let edge), .cancelled(let edge):
            flush(final: true)
            if edgeInUse == edge { edgeInUse = nil }
            gesture = nil
        }
    }

    /// Does what this tap was set to do. Every tap is noted for the popup; it acts only if tapping is on and the tap has an action.
    func apply(tap trigger: TrackpadTapTrigger) {
        tapCount += 1
        lastTap = SeenTap(trigger: trigger, id: tapCount)
        let current = settings.settings
        guard current.trackpadTapsEnabled else { return }
        let action = current.trackpadTapAction(for: trigger)
        guard action != .none else { return }
        switch runner.perform(action, app: current.trackpadTapApp(for: trigger), shortcut: current.trackpadTapShortcut(for: trigger)) {
        case .done:
            feedback.show(symbol: action.symbol, fraction: nil, text: action.shortTitle)
        case .needsAccessibility:
            feedback.show(symbol: "lock.shield", fraction: nil, text: "Allow Island in Accessibility first")
        case .unavailable(let reason):
            feedback.show(symbol: "exclamationmark.triangle.fill", fraction: nil, text: reason)
        }
    }

    private func begin(_ edge: TrackpadEdge) {
        let action = self.action(for: edge)
        switch action {
        case .off:
            gesture = nil
        case .volume:
            guard let level = system.outputVolume() else { return cannot(action, "This sound output has no volume control") }
            gesture = Gesture(edge: edge, action: action, base: Double(level))
        case .brightness:
            guard let level = brightness.current() else { return cannot(action, "The brightness of this screen can't be changed") }
            gesture = Gesture(edge: edge, action: action, base: Double(level))
        case .seek:
            guard let state = seeker.seekState else { return cannot(action, "Nothing playing that can be skipped through") }
            gesture = Gesture(edge: edge, action: action, base: state.elapsed, duration: state.duration)
        }
    }

    /// Tells the person why an edge does nothing, once.
    private func cannot(_ action: TrackpadAction, _ reason: String) {
        gesture = nil
        guard toldAbout.insert(action).inserted else { return }
        feedback.show(symbol: action.symbol, fraction: nil, text: reason)
    }

    /// Passes what has been gathered on to the volume, the screen or the player.
    private func flush(final: Bool = false) {
        guard var gesture else { return }
        let time = now()
        gesture.lastApplied = time
        defer { self.gesture = gesture }
        if gesture.pending == 0, !final { return }
        gesture.travelled += gesture.pending
        gesture.pending = 0

        switch gesture.action {
        case .off:
            break
        case .volume:
            let level = min(max(gesture.base + gesture.travelled, 0), 1)
            system.setOutputVolume(Float(level))
            feedback.show(symbol: level == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", fraction: level, text: Self.percent(level))
        case .brightness:
            let level = min(max(gesture.base + gesture.travelled, 0), 1)
            brightness.set(Float(level))
            feedback.show(symbol: "sun.max.fill", fraction: level, text: Self.percent(level))
        case .seek:
            let seconds = gesture.travelled * TrackpadDefaults.seekSecondsPerEdge
            let target = min(max(gesture.base + seconds, 0), gesture.duration ?? .greatestFiniteMagnitude)
            if final || time - gesture.lastSeek >= Self.seekEvery {
                seeker.seek(to: target)
                gesture.lastSeek = time
            }
            feedback.show(
                symbol: seconds < 0 ? "backward.fill" : "forward.fill", fraction: gesture.duration.map { target / max($0, 1) },
                text: Self.clock(target))
        }
    }

    private static func percent(_ level: Double) -> String { "\(Int((level * 100).rounded()))%" }

    private static func clock(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded())
        return whole >= 3600
            ? String(format: "%d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60)
            : String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

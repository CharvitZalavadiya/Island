import CoreGraphics
import Foundation
import IslandCore

/// Takes each frame from the trackpad, asks the engines what it means (an edge gesture, or taps), holds the pointer still while an
/// edge gesture is going on, and passes the events on. It runs on whatever thread the trackpad calls from (holding the pointer has to be quick), so it
/// guards its state with a lock and does nothing else.
final class TrackpadPipeline: @unchecked Sendable {
    struct Config: Equatable {
        var activeEdges: Set<TrackpadEdge>
        var edgeMM: Double
        /// The taps that are followed (the ones that do something).
        var wantedTaps: Set<TrackpadTapTrigger> = []
    }

    private let lock = NSLock()
    private var engine = TrackpadGestureEngine()
    private var taps = TrackpadTapEngine()
    private var expiryScheduled = false
    private var config: Config
    private var gesturesOn = false
    private var touches: [TrackpadTouch] = []
    private var frames = 0
    private var cursorAtTouchDown: CGPoint?

    private let freeze: PointerFreezing
    private let readCursor: @Sendable () -> CGPoint?
    private let clock: @Sendable () -> TimeInterval
    private let after: @Sendable (TimeInterval, @escaping @Sendable () -> Void) -> Void

    /// Called, on the calling thread, for every edge gesture event.
    var onEvent: (@Sendable (TrackpadGestureEvent) -> Void)?
    /// Called for every tap that is wanted (on whatever thread it is noticed on).
    var onTap: (@Sendable (TrackpadTapTrigger) -> Void)?

    init(
        config: Config, freeze: PointerFreezing,
        readCursor: @escaping @Sendable () -> CGPoint? = { CGEvent(source: nil)?.location },
        clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        after: @escaping @Sendable (TimeInterval, @escaping @Sendable () -> Void) -> Void = { delay, work in
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: work)
        }
    ) {
        self.config = config
        self.freeze = freeze
        self.readCursor = readCursor
        self.clock = clock
        self.after = after
    }

    /// Changes what is watched for. With `gesturesOn` false the fingers are still followed (for the picture in the Trackpad
    /// tab) but nothing happens.
    func update(_ config: Config, gesturesOn: Bool) {
        lock.lock()
        let wasOn = self.gesturesOn
        if config.wantedTaps != self.config.wantedTaps { taps = TrackpadTapEngine() }
        self.config = config
        self.gesturesOn = gesturesOn
        let stop = wasOn && !gesturesOn
        lock.unlock()
        if stop { reset() }
    }

    func process(_ frame: TrackpadFrame) {
        lock.lock()
        frames += 1
        touches = frame.touches.filter(\.isDown)
        var events: [TrackpadGestureEvent] = []
        if gesturesOn {
            events = engine.process(frame, activeEdges: config.activeEdges, edgeMM: config.edgeMM, at: clock())
            for event in events {
                switch event {
                case .candidateStarted: cursorAtTouchDown = readCursor()
                case .began: freeze.engage(at: cursorAtTouchDown)
                case .ended, .cancelled: freeze.release()
                case .moved: break
                }
            }
        }
        var tapped: [TrackpadTapTrigger] = []
        if !config.wantedTaps.isEmpty {
            for case .tapped(let trigger) in taps.process(frame, wanted: config.wantedTaps, at: clock()) { tapped.append(trigger) }
            scheduleExpiry()
        }
        lock.unlock()
        for event in events { onEvent?(event) }
        for trigger in tapped { onTap?(trigger) }
    }

    /// While a run of taps may still grow, comes back when the wait is over to report what was tapped. (Called with the lock held.)
    private func scheduleExpiry() {
        guard !expiryScheduled, let deadline = taps.deadline else { return }
        expiryScheduled = true
        after(max(deadline - clock(), 0) + 0.01) { [weak self] in self?.expire() }
    }

    private func expire() {
        lock.lock()
        expiryScheduled = false
        var tapped: [TrackpadTapTrigger] = []
        for case .tapped(let trigger) in taps.expire(wanted: config.wantedTaps, at: clock()) { tapped.append(trigger) }
        scheduleExpiry()
        lock.unlock()
        for trigger in tapped { onTap?(trigger) }
    }

    /// The fingers on the pad now, and how many frames have come in.
    func snapshot() -> (touches: [TrackpadTouch], frames: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (touches, frames)
    }

    /// Forgets any gesture in progress and gives the pointer back.
    func reset() {
        lock.lock()
        let was = engine.edgeInUse
        engine = TrackpadGestureEngine()
        taps = TrackpadTapEngine()
        touches = []
        lock.unlock()
        freeze.release()
        if let was { onEvent?(.cancelled(was)) }
    }
}

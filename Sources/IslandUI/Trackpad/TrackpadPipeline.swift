import CoreGraphics
import Foundation
import IslandCore

/// Takes each frame from the trackpad, asks the engine what it means, holds the pointer still while a gesture is going on, and
/// passes the events on. It runs on whatever thread the trackpad calls from (holding the pointer has to be quick), so it
/// guards its state with a lock and does nothing else.
final class TrackpadPipeline: @unchecked Sendable {
    struct Config: Equatable {
        var activeEdges: Set<TrackpadEdge>
        var edgeMM: Double
    }

    private let lock = NSLock()
    private var engine = TrackpadGestureEngine()
    private var config: Config
    private var gesturesOn = false
    private var touches: [TrackpadTouch] = []
    private var frames = 0
    private var cursorAtTouchDown: CGPoint?

    private let freeze: PointerFreezing
    private let readCursor: @Sendable () -> CGPoint?
    private let clock: @Sendable () -> TimeInterval

    /// Called, on the calling thread, for every event.
    var onEvent: (@Sendable (TrackpadGestureEvent) -> Void)?

    init(
        config: Config, freeze: PointerFreezing,
        readCursor: @escaping @Sendable () -> CGPoint? = { CGEvent(source: nil)?.location },
        clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.config = config
        self.freeze = freeze
        self.readCursor = readCursor
        self.clock = clock
    }

    /// Changes what is watched for. With `gesturesOn` false the fingers are still followed (for the picture in the Trackpad
    /// tab) but nothing happens.
    func update(_ config: Config, gesturesOn: Bool) {
        lock.lock()
        let wasOn = self.gesturesOn
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
        lock.unlock()
        for event in events { onEvent?(event) }
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
        touches = []
        lock.unlock()
        freeze.release()
        if let was { onEvent?(.cancelled(was)) }
    }
}

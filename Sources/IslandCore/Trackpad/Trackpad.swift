import Foundation

// Edge gestures on the trackpad: sliding one finger along an edge changes the volume, the brightness, or moves through what is
// playing. This file is only the thinking (where a finger is, whether it is a gesture, how far it went); reading the trackpad and
// changing the volume are done elsewhere (Sources/IslandUI/Trackpad), so all of this can be tried with made-up touches.

/// One of the four edges of the trackpad.
public enum TrackpadEdge: String, CaseIterable, Codable, Sendable {
    case left, right, top, bottom

    /// The left and right edges run up and down the pad; the top and bottom ones run across it.
    public var runsUpAndDown: Bool { self == .left || self == .right }

    public var title: String {
        switch self {
        case .left: "Left edge"
        case .right: "Right edge"
        case .top: "Top edge"
        case .bottom: "Bottom edge"
        }
    }
}

/// What sliding along an edge does.
public enum TrackpadAction: String, CaseIterable, Codable, Sendable {
    case off, volume, brightness, seek

    public var title: String {
        switch self {
        case .off: "Off"
        case .volume: "Volume"
        case .brightness: "Brightness"
        case .seek: "Skip"
        }
    }

    public var symbol: String {
        switch self {
        case .off: "slash.circle"
        case .volume: "speaker.wave.2.fill"
        case .brightness: "sun.max.fill"
        case .seek: "forward.fill"
        }
    }
}

public enum TrackpadDefaults {
    /// Right edge: volume. Left edge: brightness. Top edge: move through what is playing. The bottom edge is where a thumb
    /// rests and where the pad is pressed to click, so it starts switched off.
    public static let actions: [TrackpadEdge: TrackpadAction] = [.right: .volume, .left: .brightness, .top: .seek, .bottom: .off]
    public static let edgeMM = 9.0
    public static let edgeMMRange = 4.0...20.0
    public static let sensitivity = 1.0
    public static let sensitivityRange = 0.4...2.5
    /// Sliding along a whole edge moves what is playing by this many seconds (at sensitivity 1).
    public static let seekSecondsPerEdge = 120.0
}

/// One finger on the pad. `x` and `y` run from 0 to 1 across the pad: `x` from the left, `y` from the bottom.
public struct TrackpadTouch: Equatable, Sendable {
    public var id: Int
    public var x: Double
    public var y: Double
    /// Touching the pad (not hovering just above it, or lifting off).
    public var isDown: Bool

    public init(id: Int, x: Double, y: Double, isDown: Bool = true) {
        self.id = id
        self.x = x
        self.y = y
        self.isDown = isDown
    }
}

/// Everything the pad reported at one moment, and how big the pad is (the same normalized distance is a different real
/// distance on a different pad).
public struct TrackpadFrame: Equatable, Sendable {
    public var touches: [TrackpadTouch]
    public var widthMM: Double
    public var heightMM: Double

    public init(touches: [TrackpadTouch], widthMM: Double, heightMM: Double) {
        self.touches = touches
        self.widthMM = widthMM
        self.heightMM = heightMM
    }
}

public enum TrackpadGestureEvent: Equatable, Sendable {
    /// One finger touched down in the strip along this edge. It may turn out to be a gesture, or just the pointer being moved.
    case candidateStarted(TrackpadEdge)
    /// The finger has slid along the edge: this is a gesture now.
    case began(TrackpadEdge)
    /// The finger moved along the edge by this fraction of the edge's length (positive: up, or to the right).
    case moved(TrackpadEdge, delta: Double)
    case ended(TrackpadEdge)
    /// Another finger came down: the gesture is over without having been finished.
    case cancelled(TrackpadEdge)
}

/// Decides, frame by frame, whether the finger on the pad is making an edge gesture.
///
/// It is careful, because one finger on a pad normally moves the pointer:
///  - the touch has to start inside an edge strip, away from the corners, as the only finger on the pad;
///  - it becomes a gesture only when it slides along the edge (not into the pad) by a few millimetres;
///  - a finger that sits still, moves into the pad, or is joined by another one never becomes one (until all fingers lift).
public struct TrackpadGestureEngine {
    /// How far a finger has to slide along an edge before it counts, in millimetres.
    public static let claimMM = 2.5
    /// A finger that has moved this far into the pad (more than along the edge) is moving the pointer, not making a gesture.
    public static let crossLimitMM = 4.0
    /// The slide must be at least this much along the edge for each bit it strays into the pad.
    public static let straightness = 0.7
    /// A finger that rests on the edge this long without sliding is just resting.
    public static let restSeconds = 0.8

    private struct Start {
        var edge: TrackpadEdge
        var id: Int
        var x: Double
        var y: Double
        var time: TimeInterval
    }

    private enum Phase {
        case idle
        /// Fingers are on the pad but this touch cannot become a gesture; wait until all have lifted.
        case waitingForLift
        case candidate(Start)
        case claimed(Start, lastAlong: Double)
    }

    private var phase = Phase.idle
    private var previousDownCount = 0

    public init() {}

    /// Whether a gesture is going on (the finger has slid along the edge and is still down).
    public var edgeInUse: TrackpadEdge? {
        if case .claimed(let start, _) = phase { return start.edge }
        return nil
    }

    /// Takes the next frame and says what happened. `activeEdges` are the edges that do something; `edgeMM` is how wide the
    /// strip along an edge is.
    public mutating func process(
        _ frame: TrackpadFrame, activeEdges: Set<TrackpadEdge>, edgeMM: Double, at time: TimeInterval
    ) -> [TrackpadGestureEvent] {
        let down = frame.touches.filter(\.isDown)
        defer { previousDownCount = down.count }
        var events: [TrackpadGestureEvent] = []

        switch phase {
        case .idle:
            if down.isEmpty { break }
            if down.count == 1, previousDownCount == 0, let touch = down.first,
                let edge = Self.edge(of: touch, in: frame, edgeMM: edgeMM, activeEdges: activeEdges)
            {
                phase = .candidate(
                    Start(edge: edge, id: touch.id, x: touch.x * frame.widthMM, y: touch.y * frame.heightMM, time: time))
                events.append(.candidateStarted(edge))
            } else {
                phase = .waitingForLift
            }

        case .waitingForLift:
            if down.isEmpty { phase = .idle }

        case .candidate(let start):
            guard let touch = down.first, down.count == 1, touch.id == start.id else {
                phase = down.isEmpty ? .idle : .waitingForLift
                break
            }
            let (along, across) = Self.movement(of: touch, from: start, in: frame)
            if time - start.time > Self.restSeconds && abs(along) < Self.claimMM {
                phase = .waitingForLift
            } else if abs(across) > Self.crossLimitMM && abs(across) >= abs(along) {
                phase = .waitingForLift
            } else if abs(along) >= Self.claimMM && abs(across) <= Self.straightness * abs(along) {
                phase = .claimed(start, lastAlong: along)
                events.append(.began(start.edge))
            }

        case .claimed(let start, let lastAlong):
            guard let touch = down.first, down.count == 1, touch.id == start.id else {
                phase = down.isEmpty ? .idle : .waitingForLift
                events.append(down.isEmpty ? .ended(start.edge) : .cancelled(start.edge))
                break
            }
            let (along, _) = Self.movement(of: touch, from: start, in: frame)
            let length = start.edge.runsUpAndDown ? frame.heightMM : frame.widthMM
            if along != lastAlong, length > 0 {
                events.append(.moved(start.edge, delta: (along - lastAlong) / length))
                phase = .claimed(start, lastAlong: along)
            }
        }
        return events
    }

    /// How far the touch has gone from where it started, along the edge (up or to the right is positive) and across it
    /// (into the pad), in millimetres.
    private static func movement(of touch: TrackpadTouch, from start: Start, in frame: TrackpadFrame) -> (along: Double, across: Double) {
        let dx = touch.x * frame.widthMM - start.x
        let dy = touch.y * frame.heightMM - start.y
        return start.edge.runsUpAndDown ? (dy, dx) : (dx, dy)
    }

    /// The edge whose strip this touch is in, if that edge does something. The strips stop short of the corners, so a touch
    /// in a corner (where a palm or a thumb rests) never starts a gesture.
    public static func edge(of touch: TrackpadTouch, in frame: TrackpadFrame, edgeMM: Double, activeEdges: Set<TrackpadEdge>) -> TrackpadEdge? {
        let x = touch.x * frame.widthMM
        let y = touch.y * frame.heightMM
        let width = frame.widthMM, height = frame.heightMM
        let insideAcross = x >= edgeMM && x <= width - edgeMM
        let insideAlong = y >= edgeMM && y <= height - edgeMM
        if activeEdges.contains(.left), x <= edgeMM, insideAlong { return .left }
        if activeEdges.contains(.right), x >= width - edgeMM, insideAlong { return .right }
        if activeEdges.contains(.top), y >= height - edgeMM, insideAcross { return .top }
        if activeEdges.contains(.bottom), y <= edgeMM, insideAcross { return .bottom }
        return nil
    }
}

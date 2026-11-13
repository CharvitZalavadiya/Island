import Foundation

// Tapping the trackpad with three or four fingers, twice or three times, or putting them down and holding them still, does
// something the person chose: copy, paste, take a screenshot, open an app, and so on. This file is the thinking (is this a tap or
// a hold, how many fingers, how many taps in a row);
// doing the thing is in Sources/IslandUI/Trackpad.

/// One way of tapping: how many fingers, and how many taps in a row, or (`taps` is 0) fingers put down together and held still.
public struct TrackpadTapTrigger: Hashable, Codable, Sendable {
    public var fingers: Int
    public var taps: Int

    public init(fingers: Int, taps: Int) {
        self.fingers = fingers
        self.taps = taps
    }

    /// Touch down with this many fingers together and keep them still.
    public static func hold(fingers: Int) -> TrackpadTapTrigger { TrackpadTapTrigger(fingers: fingers, taps: 0) }

    /// The six that can be set: three or four fingers, tapped twice, tapped three times, or held still.
    public static let all: [TrackpadTapTrigger] = [
        TrackpadTapTrigger(fingers: 3, taps: 2), TrackpadTapTrigger(fingers: 3, taps: 3), .hold(fingers: 3),
        TrackpadTapTrigger(fingers: 4, taps: 2), TrackpadTapTrigger(fingers: 4, taps: 3), .hold(fingers: 4),
    ]

    public var isHold: Bool { taps == 0 }

    /// The name it is saved under ("3-2" is three fingers, two taps; "3-hold" is three fingers held).
    public var id: String { isHold ? "\(fingers)-hold" : "\(fingers)-\(taps)" }

    public var tapsTitle: String { isHold ? "Tap and hold" : taps == 2 ? "Double tap" : "Triple tap" }
    public var fingersTitle: String { fingers == 3 ? "Three fingers" : "Four fingers" }
    public var title: String { "\(fingersTitle), \(isHold ? "tap and hold" : taps == 2 ? "double tap" : "triple tap")" }
}

/// What a tap can do.
public enum TrackpadTapAction: String, CaseIterable, Codable, Sendable {
    case none, copy, paste, screenshot, missionControl, openApp, shortcut, lockScreen, screenSaver, displaySleep, mute, playPause

    public var title: String {
        switch self {
        case .none: "Nothing"
        case .copy: "Copy"
        case .paste: "Paste"
        case .screenshot: "Take a screenshot"
        case .missionControl: "Mission Control"
        case .openApp: "Open an app"
        case .shortcut: "Run a Shortcut"
        case .lockScreen: "Lock the screen"
        case .screenSaver: "Start the screen saver"
        case .displaySleep: "Turn off the display"
        case .mute: "Mute or unmute"
        case .playPause: "Play or pause"
        }
    }

    /// A shorter name for the small cards.
    public var shortTitle: String {
        switch self {
        case .none: "Not set"
        case .screenshot: "Screenshot"
        case .missionControl: "Mission Ctrl"
        case .openApp: "Open app"
        case .shortcut: "Shortcut"
        case .lockScreen: "Lock screen"
        case .screenSaver: "Screen saver"
        case .displaySleep: "Display off"
        case .mute: "Mute"
        case .playPause: "Play/pause"
        default: title
        }
    }

    public var symbol: String {
        switch self {
        case .none: "slash.circle"
        case .copy: "doc.on.doc"
        case .paste: "doc.on.clipboard"
        case .screenshot: "camera.viewfinder"
        case .missionControl: "rectangle.3.group"
        case .openApp: "macwindow"
        case .shortcut: "bolt.fill"
        case .lockScreen: "lock.fill"
        case .screenSaver: "display"
        case .displaySleep: "moon.zzz.fill"
        case .mute: "speaker.slash.fill"
        case .playPause: "playpause.fill"
        }
    }

    /// Copy and paste work by pressing the keys, which macOS only lets an app do once it has been allowed in Accessibility.
    public var needsAccessibility: Bool { self == .copy || self == .paste }
}

public enum TrackpadTapEvent: Equatable, Sendable {
    case tapped(TrackpadTapTrigger)
}

/// Decides, frame by frame, whether the fingers on the pad are tapping it: three or four of them landing together, staying put and
/// lifting at once, twice or three times running; or landing together and staying put for a second and a half (a hold).
///
/// It is careful about what it is not: one or two fingers, five fingers (a palm), fingers that slide (a swipe), and fingers that
/// land one after another all leave it alone, so the system's own gestures work as they do.
public struct TrackpadTapEngine {
    /// All the fingers of a tap land within this long of the first.
    public static let gatherSeconds = 0.15
    /// From the first landing to the last lift.
    public static let tapSeconds = 0.30
    /// The next tap of a double or triple tap starts within this long of the last one lifting.
    public static let gapSeconds = 0.35
    /// How far a finger may wander during a tap or a hold, in millimetres.
    public static let moveMM = 3.5
    /// Fingers that land together and stay put this long, from the first landing, are a hold.
    public static let holdSeconds = 1.5

    private struct Contact {
        var start: TimeInterval
        var origins: [Int: (x: Double, y: Double)] = [:]
        var peak = 0
        /// How many fingers are down now.
        var fingersDown = 0
        /// False once a finger has wandered, one has landed late, or there are more fingers than a tap or a hold can have.
        var steady = true
        /// A tap as well: steady, and over within the time a tap lasts.
        var valid = true
        /// The hold has already been reported for this touch.
        var held = false
    }

    private struct Run {
        var fingers: Int
        var count: Int
        var lastEnd: TimeInterval
    }

    private var contact: Contact?
    private var run: Run?
    private var previousDown = 0
    private var lastWanted: Set<TrackpadTapTrigger> = []

    public init() {}

    /// When `expire` has to be called, if nothing else happens first: the engine is waiting to see whether another tap follows, or
    /// whether the fingers that are down will still be there after the hold time.
    public var deadline: TimeInterval? {
        var due: [TimeInterval] = []
        if let run { due.append(run.lastEnd + Self.gapSeconds) }
        if let contact, !contact.held, contact.steady, lastWanted.contains(where: \.isHold) { due.append(contact.start + Self.holdSeconds) }
        return due.min()
    }

    /// Takes the next frame. `wanted` are the taps that do something; the others are followed but never reported.
    public mutating func process(_ frame: TrackpadFrame, wanted: Set<TrackpadTapTrigger>, at time: TimeInterval) -> [TrackpadTapEvent] {
        var events: [TrackpadTapEvent] = []
        let down = frame.touches.filter(\.isDown)
        defer { previousDown = down.count }
        lastWanted = wanted

        // A run that has waited long enough is over, even if nobody asked.
        if previousDown == 0, !down.isEmpty, let run, time - run.lastEnd > Self.gapSeconds {
            events += finishRun(wanted)
        }

        if down.isEmpty {
            if let contact {
                self.contact = nil
                events += end(of: contact, at: time, wanted: wanted)
            }
            return events
        }

        if contact == nil {
            guard previousDown == 0 else { return events }       // fingers that were already down when this began: not a tap
            contact = Contact(start: time)
        }
        var current = contact!
        for touch in down {
            let x = touch.x * frame.widthMM, y = touch.y * frame.heightMM
            if let origin = current.origins[touch.id] {
                if hypot(x - origin.x, y - origin.y) > Self.moveMM { current.steady = false }
            } else {
                if !current.origins.isEmpty, time - current.start > Self.gatherSeconds { current.steady = false }
                current.origins[touch.id] = (x, y)
            }
        }
        current.peak = max(current.peak, down.count)
        current.fingersDown = down.count
        if current.origins.count != current.peak || current.origins.count > 4 { current.steady = false }
        current.valid = current.steady && time - current.start <= Self.tapSeconds
        contact = current
        // Something other than a tap is going on: whatever tapping came before is complete.
        if !current.valid { events += finishRun(wanted) }
        return events + holdIfDue(wanted, at: time)
    }

    /// Reports the hold, once, when fingers that landed together have stayed put with none lifted for the hold time.
    private mutating func holdIfDue(_ wanted: Set<TrackpadTapTrigger>, at time: TimeInterval) -> [TrackpadTapEvent] {
        guard var current = contact, !current.held, current.steady, (3...4).contains(current.peak),
            current.fingersDown == current.peak, time - current.start >= Self.holdSeconds
        else { return [] }
        let trigger = TrackpadTapTrigger.hold(fingers: current.peak)
        guard wanted.contains(trigger) else { return [] }
        current.held = true
        contact = current
        return [.tapped(trigger)]
    }

    /// Call at `deadline`: if no further tap came, the taps so far are what was meant.
    public mutating func expire(wanted: Set<TrackpadTapTrigger>, at time: TimeInterval) -> [TrackpadTapEvent] {
        lastWanted = wanted
        let events = holdIfDue(wanted, at: time)
        guard let run, time >= run.lastEnd + Self.gapSeconds else { return events }
        // A touch that began in time may still be the next tap; it decides when it ends.
        if let contact, contact.valid, time - contact.start <= Self.tapSeconds { return events }
        return events + finishRun(wanted)
    }

    private mutating func end(of contact: Contact, at time: TimeInterval, wanted: Set<TrackpadTapTrigger>) -> [TrackpadTapEvent] {
        guard contact.valid, (3...4).contains(contact.peak), time - contact.start <= Self.tapSeconds else {
            return finishRun(wanted)
        }
        var events: [TrackpadTapEvent] = []
        if let run, run.fingers == contact.peak, contact.start - run.lastEnd <= Self.gapSeconds {
            self.run = Run(fingers: run.fingers, count: run.count + 1, lastEnd: time)
        } else {
            events += finishRun(wanted)
            run = Run(fingers: contact.peak, count: 1, lastEnd: time)
        }
        return events + settle(wanted)
    }

    /// Reports the run now if no longer run of the same fingers could be wanted; otherwise waits to see.
    private mutating func settle(_ wanted: Set<TrackpadTapTrigger>) -> [TrackpadTapEvent] {
        guard let run else { return [] }
        if wanted.contains(where: { $0.fingers == run.fingers && $0.taps > run.count }) { return [] }
        return finishRun(wanted)
    }

    private mutating func finishRun(_ wanted: Set<TrackpadTapTrigger>) -> [TrackpadTapEvent] {
        guard let finished = run else { return [] }
        run = nil
        let trigger = TrackpadTapTrigger(fingers: finished.fingers, taps: finished.count)
        return wanted.contains(trigger) ? [.tapped(trigger)] : []
    }
}

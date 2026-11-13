import CoreGraphics
import Foundation

/// Holds the pointer still while an edge gesture is going on. One finger on the pad normally moves the pointer, so without this
/// the pointer would run up and down the screen while the volume is changed.
protocol PointerFreezing: AnyObject, Sendable {
    /// Stops the pointer following the pad, and puts it back at `point` (where it was when the finger touched down).
    func engage(at point: CGPoint?)
    /// Lets the pointer follow the pad again. Always safe to call.
    func release()
}

/// The real thing, with the macOS call that does exactly this (`CGAssociateMouseAndMouseCursorPosition`; it needs no permission).
/// The pointer is the one thing that must never stay stuck, so it is given back in every way there is: when the finger lifts or
/// another comes down, when the feature is switched off, when Island starts (in case it was stopped in the middle of a
/// gesture) and quits, and, last of all, by a timer if none of those happens within a few seconds.
final class PointerFreeze: PointerFreezing, @unchecked Sendable {
    /// The longest the pointer is ever held, however long the finger stays down.
    static let longest: TimeInterval = 12

    private let lock = NSLock()
    private var watchdog: DispatchSourceTimer?

    func engage(at point: CGPoint?) {
        lock.lock()
        defer { lock.unlock() }
        if watchdog == nil {
            CGAssociateMouseAndMouseCursorPosition(0)
            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + Self.longest)
            timer.setEventHandler { [weak self] in self?.release() }
            timer.resume()
            watchdog = timer
        }
        if let point { CGWarpMouseCursorPosition(point) }
    }

    func release() {
        lock.lock()
        defer { lock.unlock() }
        watchdog?.cancel()
        watchdog = nil
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}

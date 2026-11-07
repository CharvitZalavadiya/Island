import CoreGraphics
import Foundation
import IslandCore

/// Something that can lock the keyboard for a while. The real one is `KeyboardLock`; tests use a fake.
protocol KeyboardLocking: AnyObject {
    func start(duration: TimeInterval, onEnd: @escaping @Sendable () -> Void) -> KeyboardLock.StartResult
    func stop()
}

/// Blocks the keyboard (and only the keyboard) so it can be wiped clean. The trackpad and mouse are never touched, and
/// the lock cannot outlast its time, whatever else goes wrong:
///
/// - a timer on the event tap's own thread ends it at the deadline;
/// - a second timer on another queue ends it too, so a stuck tap thread cannot hold it;
/// - the controller has a third one on the main thread;
/// - pressing Escape three times quickly, or clicking the keyboard tile, ends it at once;
/// - if the system finds the tap unresponsive it switches the tap off by itself (the callback then ends the lock);
/// - if Island quits or crashes, the system removes the tap.
///
/// Blocking keys needs Accessibility permission; without it `start` says so and nothing is blocked.
final class KeyboardLock: @unchecked Sendable {
    enum StartResult { case started, needsPermission }

    static let duration: TimeInterval = 30

    private let lock = NSLock()
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var active = false
    private var escapes = PressCounter(count: 3, window: 1.5)
    private var onEnd: (@Sendable () -> Void)?
    private var guardTimer: DispatchSourceTimer?

    var isActive: Bool { lock.withLock { active } }

    func start(duration: TimeInterval = KeyboardLock.duration, onEnd: @escaping @Sendable () -> Void) -> StartResult {
        lock.lock()
        defer { lock.unlock() }
        guard !active else { return .started }

        // Key presses, key releases, modifier keys and the media/volume/brightness keys (system-defined, type 14).
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue) | (1 << 14)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: keyboardLockCallback, userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return .needsPermission }

        self.tap = tap
        self.onEnd = onEnd
        escapes = PressCounter(count: 3, window: 1.5)
        active = true

        let thread = Thread { [self] in
            let loop = CFRunLoopGetCurrent()
            lock.lock()
            let stillActive = active
            runLoop = loop
            lock.unlock()
            guard stillActive else { return }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(loop, source, .commonModes)
            // The first guard: this thread's own timer. It also stops the loop, so the thread always finishes.
            let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + duration, 0, 0, 0) { [weak self] _ in
                self?.end()
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
            CFRunLoopAddTimer(loop, timer, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "dev.island.keyboard-lock"
        thread.qualityOfService = .userInteractive
        thread.start()

        // The second guard: a timer on a queue that has nothing to do with the tap's thread or the main thread.
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        timer.schedule(deadline: .now() + duration)
        timer.setEventHandler { [weak self] in self?.end() }
        timer.resume()
        guardTimer = timer
        return .started
    }

    func stop() {
        end()
    }

    /// Switches the lock off (safe to call from any thread, any number of times) and tells the app on the main thread.
    func end() {
        var finished: (@Sendable () -> Void)?
        lock.lock()
        guard active else {
            lock.unlock()
            return
        }
        active = false
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop { CFRunLoopStop(runLoop) }
        guardTimer?.cancel()
        guardTimer = nil
        tap = nil
        runLoop = nil
        finished = onEnd
        onEnd = nil
        lock.unlock()
        if let finished { DispatchQueue.main.async(execute: finished) }
    }

    /// Called for every keyboard event while the tap exists. True means "swallow it".
    fileprivate func shouldSwallow(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // The system switched the tap off because it was unresponsive: keys flow again, so the lock is over.
            end()
            return false
        }
        guard isActive else { return false }
        if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 53 {
            let letOut = lock.withLock { escapes.press(at: ProcessInfo.processInfo.systemUptime) }
            if letOut { end() }
        }
        return true
    }
}

private func keyboardLockCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let keyboardLock = Unmanaged<KeyboardLock>.fromOpaque(userInfo).takeUnretainedValue()
    return keyboardLock.shouldSwallow(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
}

extension KeyboardLock: KeyboardLocking {}

import AppKit
import ApplicationServices
import Observation
import IslandCore

/// The Tools tab: the colour picker and the keyboard lock for cleaning.
@Observable
@MainActor
final class ToolsController {
    struct PickedColor: Equatable {
        var hex: String
        var rgb: String
        var red: Double
        var green: Double
        var blue: Double
    }

    enum KeyboardState: Equatable {
        case idle
        case locked
        /// Island needs Accessibility permission before it can block keys.
        case needsPermission
    }

    private(set) var pickedColor: PickedColor?
    private(set) var keyboard: KeyboardState = .idle
    private(set) var lockRemaining: TimeInterval = 0
    let lockDuration: TimeInterval

    /// How much of the lock time is left, 1 down to 0, for the ring; nil when the keyboard is not locked.
    var lockProgress: Double? {
        keyboard == .locked ? min(max(lockRemaining / lockDuration, 0), 1) : nil
    }

    @ObservationIgnored private let keyboardLock: KeyboardLocking
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let writeToClipboard: (String) -> Void
    @ObservationIgnored private var sampler: NSColorSampler?
    @ObservationIgnored private var lockEndsAt = Date.distantPast
    @ObservationIgnored private var tickTimer: Timer?
    @ObservationIgnored private var safetyTimer: Timer?
    @ObservationIgnored private var sleepObservers: [NSObjectProtocol] = []

    init(
        keyboardLock: KeyboardLocking = KeyboardLock(), lockDuration: TimeInterval = KeyboardLock.duration,
        now: @escaping () -> Date = Date.init,
        writeToClipboard: @escaping (String) -> Void = { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    ) {
        self.keyboardLock = keyboardLock
        self.lockDuration = lockDuration
        self.now = now
        self.writeToClipboard = writeToClipboard
    }

    // MARK: Colour

    /// Shows the system eyedropper. The colour picked is shown and its hex code is copied.
    func pickColor() {
        let sampler = NSColorSampler()
        self.sampler = sampler   // it must be kept alive until it has answered
        sampler.show { [weak self] color in
            MainActor.assumeIsolated { self?.finishPicking(color) }
        }
    }

    func finishPicking(_ color: NSColor?) {
        sampler = nil
        guard let srgb = color?.usingColorSpace(.sRGB) else { return }
        let red = Double(srgb.redComponent), green = Double(srgb.greenComponent), blue = Double(srgb.blueComponent)
        let picked = PickedColor(
            hex: ColorFormat.hex(red: red, green: green, blue: blue),
            rgb: ColorFormat.rgb(red: red, green: green, blue: blue), red: red, green: green, blue: blue)
        pickedColor = picked
        copy(picked.hex)
    }

    func copy(_ text: String) {
        writeToClipboard(text)
    }

    func dismissColor() { pickedColor = nil }

    // MARK: Keyboard lock

    func toggleKeyboardLock() {
        if keyboard == .locked {
            keyboardLock.stop()
            lockEnded()
            return
        }
        let result = keyboardLock.start(duration: lockDuration) { [weak self] in
            Task { @MainActor in self?.lockEnded() }
        }
        switch result {
        case .started:
            keyboard = .locked
            lockEndsAt = now().addingTimeInterval(lockDuration)
            lockRemaining = lockDuration
            startTimers()
            watchForSleep()
        case .needsPermission:
            keyboard = .needsPermission
            // Shows the system's own "Island would like to control this computer" request.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func dismissPermissionNotice() {
        if keyboard == .needsPermission { keyboard = .idle }
    }

    // MARK: Internals

    private func lockEnded() {
        tickTimer?.invalidate()
        tickTimer = nil
        safetyTimer?.invalidate()
        safetyTimer = nil
        for observer in sleepObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        sleepObservers = []
        lockRemaining = 0
        if keyboard == .locked { keyboard = .idle }
    }

    private func startTimers() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.lockRemaining = max(0, self.lockEndsAt.timeIntervalSince(self.now()))
                if self.lockRemaining <= 0 {
                    self.keyboardLock.stop()
                    self.lockEnded()
                }
            }
        }
        // The third guard, on the main thread: if the others somehow did not end it, this does.
        safetyTimer = Timer.scheduledTimer(withTimeInterval: lockDuration + 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.keyboardLock.stop()
                self?.lockEnded()
            }
        }
    }

    /// Going to sleep or switching the display off ends the lock, so the keyboard is free when the Mac wakes.
    private func watchForSleep() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            sleepObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.keyboardLock.stop()
                    self?.lockEnded()
                }
            })
        }
    }
}

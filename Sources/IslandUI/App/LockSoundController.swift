import AppKit
import IslandCore

/// Plays a short sound when the Mac locks (or the screen saver starts) and another when it unlocks. The system announces
/// these through distributed notifications; they arrive in pairs (a screen saver that then asks for a password
/// announces both), so a small locked/unlocked state makes sure each change is heard once.
@MainActor
final class LockSoundController {
    enum Event { case locked, unlocked }

    private let settings: SettingsStore
    /// Where the sound goes; tests pass their own, the app uses the system speaker.
    private let output: ((Data) -> Void)?
    private let center: DistributedNotificationCenter
    private var observers: [NSObjectProtocol] = []
    private var isLocked = false
    private var current: NSSound?

    init(settings: SettingsStore, center: DistributedNotificationCenter = .default(), output: ((Data) -> Void)? = nil) {
        self.settings = settings
        self.center = center
        self.output = output
    }

    static let lockNames = ["com.apple.screenIsLocked", "com.apple.screensaver.didstart"]
    static let unlockNames = ["com.apple.screenIsUnlocked", "com.apple.screensaver.didstop"]

    func start() {
        guard observers.isEmpty else { return }
        for (names, event) in [(Self.lockNames, Event.locked), (Self.unlockNames, Event.unlocked)] {
            for name in names {
                observers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.handle(event) }
                })
            }
        }
    }

    func stop() {
        for observer in observers { center.removeObserver(observer) }
        observers = []
    }

    /// One lock or unlock has been announced (possibly the second announcement of the same change).
    func handle(_ event: Event) {
        switch event {
        case .locked:
            guard !isLocked else { return }
            isLocked = true
            if settings.settings.lockSounds { emit(SoundSynth.lockChime()) }
        case .unlocked:
            guard isLocked else { return }
            isLocked = false
            if settings.settings.lockSounds { emit(SoundSynth.unlockChime()) }
        }
    }

    private func emit(_ data: Data) {
        if let output {
            output(data)
            return
        }
        let sound = NSSound(data: data)
        sound?.volume = 0.7
        current = sound   // keep it alive until it has finished playing
        sound?.play()
    }
}

import Testing
import Foundation
import IslandCore
@testable import IslandUI

@MainActor
private func makeController(lockSounds: Bool = true) -> (LockSoundController, () -> [Data]) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("island-ui-tests-\(UUID().uuidString)/settings.json")
    let settings = SettingsStore(store: FileStore(url: url, defaultValue: Settings()))
    settings.update { $0.lockSounds = lockSounds }
    var played: [Data] = []
    let controller = LockSoundController(settings: settings, output: { played.append($0) })
    return (controller, { played })
}

@Test @MainActor func lockingPlaysTheLockSoundAndUnlockingPlaysTheUnlockSound() {
    let (controller, played) = makeController()
    controller.handle(.locked)
    controller.handle(.unlocked)
    #expect(played() == [SoundSynth.lockChime(), SoundSynth.unlockChime()])
}

@Test @MainActor func theSecondAnnouncementOfTheSameChangeIsNotHeardAgain() {
    // A screen saver that then asks for a password announces both: still one lock sound and one unlock sound.
    let (controller, played) = makeController()
    controller.handle(.locked)
    controller.handle(.locked)
    controller.handle(.unlocked)
    controller.handle(.unlocked)
    #expect(played().count == 2)
}

@Test @MainActor func anUnlockWithoutALockMakesNoSound() {
    let (controller, played) = makeController()
    controller.handle(.unlocked)
    #expect(played().isEmpty)
}

@Test @MainActor func withTheSwitchOffNothingIsPlayed() {
    let (controller, played) = makeController(lockSounds: false)
    controller.handle(.locked)
    controller.handle(.unlocked)
    #expect(played().isEmpty)
}

@Test @MainActor func lockingAgainAfterUnlockingPlaysAgain() {
    let (controller, played) = makeController()
    for _ in 0..<2 {
        controller.handle(.locked)
        controller.handle(.unlocked)
    }
    #expect(played().count == 4)
}

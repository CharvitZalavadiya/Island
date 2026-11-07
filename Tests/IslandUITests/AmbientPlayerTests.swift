import Testing
import Foundation
import IslandCore
@testable import IslandUI

@MainActor
private func makePlayer() -> (AmbientPlayer, SettingsStore) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("island-ui-tests-\(UUID().uuidString)/settings.json")
    let settings = SettingsStore(store: FileStore(url: url, defaultValue: Settings()))
    return (AmbientPlayer(settings: settings), settings)
}

@Test @MainActor func theChosenSoundAndVolumeAreRememberedAcrossLaunches() {
    let (player, settings) = makePlayer()
    #expect(player.sound == .rain)
    player.select(.sea)
    player.setVolume(0.8)
    #expect(settings.settings.ambientSound == "sea")
    #expect(settings.settings.ambientVolume == 0.8)
    let reopened = AmbientPlayer(settings: settings)
    #expect(reopened.sound == .sea && reopened.volume == 0.8)
}

@Test @MainActor func volumeStaysBetweenZeroAndOne() {
    let (player, _) = makePlayer()
    player.setVolume(7)
    #expect(player.volume == 1)
    player.setVolume(-3)
    #expect(player.volume == 0)
}

@Test func theVolumeCurveIsSilentAtZeroAndGentleBelowFull() {
    #expect(AmbientPlayer.gain(for: 0) == 0)
    #expect(AmbientPlayer.gain(for: 0.5) < 0.5 * 0.9)   // a curve, so the middle of the slider is quieter than half
    #expect(AmbientPlayer.gain(for: 1) <= 0.9)
}

@Test @MainActor func theEngineStartsAndStopsCleanlyWhileSilent() async throws {
    let (player, _) = makePlayer()
    player.setVolume(0)         // nothing audible while the test runs
    player.play()
    #expect(player.isPlaying)
    try await Task.sleep(nanoseconds: 150_000_000)
    player.select(.wind)        // switching sounds while playing
    try await Task.sleep(nanoseconds: 100_000_000)
    player.pause()
    #expect(!player.isPlaying)
    try await Task.sleep(nanoseconds: 600_000_000)   // the engine shuts down after the fade
    player.play()               // and can start again
    #expect(player.isPlaying)
    player.pause()
}

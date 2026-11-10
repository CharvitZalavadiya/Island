import Testing
import Foundation
import IslandCore
@testable import IslandUI

@MainActor private final class Reporting: NowPlayingReporting {
    private(set) var stopped = false
    func stop() { stopped = true }
}

@MainActor private final class Backend: NowPlayingBackend {
    private(set) var started = 0
    private(set) var handles: [Reporting] = []
    private var onReading: (@Sendable (NowPlayingReading) -> Void)?
    var running: Bool { handles.last.map { !$0.stopped } ?? false }

    func startReporting(
        onReading: @escaping @Sendable (NowPlayingReading) -> Void, onEnd: @escaping @Sendable () -> Void
    ) -> Result<NowPlayingReporting, NowPlayingBackendError> {
        started += 1
        self.onReading = onReading
        let handle = Reporting()
        handles.append(handle)
        return .success(handle)
    }
    func send(_ command: NowPlayingCommand) {}
    func seek(to seconds: TimeInterval) {}
    func report(_ reading: NowPlayingReading) { onReading?(reading) }
}

private func settle(_ milliseconds: UInt64 = 60) async { try? await Task.sleep(nanoseconds: milliseconds * 1_000_000) }

/// Waits (up to `timeout`) for something that should happen, instead of guessing how long it takes on a busy machine.
private func eventually(timeout: TimeInterval = 30, _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return await condition()
}

private let playingSong = NowPlayingTrack(title: "Song", duration: 200, elapsed: 10, timestamp: Date(), rate: 1, isPlaying: true)
private var pausedSong: NowPlayingTrack { var t = playingSong; t.isPlaying = false; t.rate = 0; return t }

@MainActor private struct Rig {
    let backend = Backend()
    let player: NowPlayingController
    let model: IslandModel
    let monitor: MediaActivityMonitor

    init(grace: TimeInterval = 0.1) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("island-media-\(UUID().uuidString).json")
        model = IslandModel(settings: SettingsStore(store: FileStore(url: url, defaultValue: Settings())))
        player = NowPlayingController(backend: backend)
        monitor = MediaActivityMonitor(player: player, model: model, grace: grace)
        monitor.start()
    }
}

@Test func mediaInTheMinimalViewIsOnByDefaultAndOlderFilesKeepWorking() throws {
    #expect(Settings().mediaInMinimalView)
    let older = try JSONDecoder().decode(Settings.self, from: Data(#"{"hoverOpens":false}"#.utf8))
    #expect(older.mediaInMinimalView && !older.hoverOpens)
    var off = Settings()
    off.mediaInMinimalView = false
    let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(off))
    #expect(!back.mediaInMinimalView)
}

@Test @MainActor func theWingsShowMediaWhilePlayingAndAskForTheHelper() async {
    let rig = Rig()
    #expect(rig.backend.started == 1)                       // on by default: the helper runs
    #expect(!rig.model.activities.contains(.media))         // nothing playing yet
    rig.backend.report(.track(playingSong))
    #expect(await eventually { rig.model.activities.contains(.media) })
}

@Test @MainActor func pausingTakesItAwayAfterAShortWhileNotAtOnce() async {
    let rig = Rig(grace: 0.4)
    rig.backend.report(.track(playingSong))
    #expect(await eventually { rig.model.activities.contains(.media) })
    rig.backend.report(.track(pausedSong))
    await settle(30)
    #expect(rig.model.activities.contains(.media))          // still there: it may be the gap between two songs
    #expect(await eventually { !rig.model.activities.contains(.media) })
}

@Test @MainActor func aGapBetweenSongsDoesNotMakeTheWingsBlink() async {
    let rig = Rig(grace: 0.6)
    rig.backend.report(.track(playingSong))
    #expect(await eventually { rig.model.activities.contains(.media) })
    rig.backend.report(.nothing)
    await settle(60)
    rig.backend.report(.track(playingSong))                 // the next song starts inside the grace period
    await settle(900)
    #expect(rig.model.activities.contains(.media))
}

@Test @MainActor func turningTheSettingOffRemovesItAtOnceAndStopsWatching() async {
    let rig = Rig()
    rig.backend.report(.track(playingSong))
    #expect(await eventually { rig.model.activities.contains(.media) })
    rig.model.settings.update { $0.mediaInMinimalView = false }
    #expect(await eventually { !rig.model.activities.contains(.media) && !rig.backend.running })   // and nothing watches any more
    rig.model.settings.update { $0.mediaInMinimalView = true }
    #expect(await eventually { rig.backend.running })        // turning it back on starts again
}

@Test @MainActor func theToolsTabKeepsTheHelperAliveWhenTheSettingIsOff() async {
    let rig = Rig()
    rig.player.start(for: .player)                           // the Tools tab is open
    rig.model.settings.update { $0.mediaInMinimalView = false }
    await settle(150)
    #expect(rig.backend.running)                             // the open tab still needs it
    rig.player.stop(for: .player)                            // and once it closes, nobody does
    #expect(await eventually { !rig.backend.running })
}

@Test @MainActor func closingTheToolsTabKeepsTheHelperForTheMinimalView() {
    let rig = Rig()
    rig.player.start(for: .player)
    rig.player.stop(for: .player)
    #expect(rig.backend.running)                             // the minimal view still wants it
}

@Test @MainActor func anActivityThatWasNotAddedByTheMonitorIsLeftAlone() async {
    let rig = Rig(grace: 0.05)
    rig.model.setActivity(.media, active: true)              // like --debug-wings
    rig.backend.report(.nothing)
    await settle(250)
    #expect(rig.model.activities.contains(.media))
}

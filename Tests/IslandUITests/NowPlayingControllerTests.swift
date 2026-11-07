import Testing
import Foundation
import IslandCore
@testable import IslandUI

@MainActor private final class FakeReporting: NowPlayingReporting {
    private(set) var stopped = false
    func stop() { stopped = true }
}

@MainActor private final class FakeBackend: NowPlayingBackend {
    var failure: NowPlayingBackendError?
    private(set) var reporting: [FakeReporting] = []
    private(set) var sent: [NowPlayingCommand] = []
    private(set) var seeks: [TimeInterval] = []
    private var onReading: (@Sendable (NowPlayingReading) -> Void)?
    private var onEnd: (@Sendable () -> Void)?

    func startReporting(
        onReading: @escaping @Sendable (NowPlayingReading) -> Void, onEnd: @escaping @Sendable () -> Void
    ) -> Result<NowPlayingReporting, NowPlayingBackendError> {
        if let failure { return .failure(failure) }
        self.onReading = onReading
        self.onEnd = onEnd
        let handle = FakeReporting()
        reporting.append(handle)
        return .success(handle)
    }

    func send(_ command: NowPlayingCommand) { sent.append(command) }
    func seek(to seconds: TimeInterval) { seeks.append(seconds) }
    func report(_ reading: NowPlayingReading) { onReading?(reading) }
    func end() { onEnd?() }
}

private func settle() async { try? await Task.sleep(nanoseconds: 50_000_000) }
private let epoch = Date(timeIntervalSince1970: 5000)
private let song = NowPlayingTrack(title: "Song", artist: "Band", duration: 300, elapsed: 30, timestamp: epoch, rate: 1, isPlaying: true)

@Test @MainActor func theControllerShowsWhatTheHelperReports() async {
    let backend = FakeBackend()
    let player = NowPlayingController(backend: backend, now: { epoch })
    player.start()
    #expect(player.status == .starting && player.track == nil)
    backend.report(.track(song))
    await settle()
    #expect(player.status == .running && player.track == song)
    backend.report(.nothing)
    await settle()
    #expect(player.track == nil && player.status == .running)
}

@Test @MainActor func playPauseShowsTheNewStateAtOnceAndNextIsPassedOn() {
    let backend = FakeBackend()
    let player = NowPlayingController(backend: backend, now: { epoch.addingTimeInterval(10) })
    player.start()
    backend.report(.track(song))
    player.send(.nextTrack)
    #expect(backend.sent == [.nextTrack])
}

@Test @MainActor func togglingPausesWithoutWaitingForTheSystem() async {
    let backend = FakeBackend()
    let player = NowPlayingController(backend: backend, now: { epoch.addingTimeInterval(10) })
    player.start()
    backend.report(.track(song))
    await settle()
    player.send(.togglePlayPause)
    #expect(backend.sent == [.togglePlayPause])
    #expect(player.track?.isPlaying == false && player.track?.elapsed == 40)
}

@Test @MainActor func leavingTheTabStopsTheHelperAndIgnoresLateReports() async {
    let backend = FakeBackend()
    let player = NowPlayingController(backend: backend)
    player.start()
    player.stop()
    #expect(backend.reporting[0].stopped && player.status == .stopped)
    backend.report(.track(song))                             // a report already on its way
    await settle()
    #expect(player.track == nil)
    player.start()                                           // coming back starts a fresh helper
    #expect(backend.reporting.count == 2)
}

@Test @MainActor func aMissingHelperAndAHelperThatDiesAreExplained() async {
    let missing = FakeBackend()
    missing.failure = NowPlayingBackendError(message: "The helper is missing.")
    let first = NowPlayingController(backend: missing)
    first.start()
    #expect(first.status == .unavailable("The helper is missing.") && !first.isAvailable)

    let backend = FakeBackend()
    let second = NowPlayingController(backend: backend)
    second.start()
    backend.report(.track(song))
    await settle()
    backend.end()
    await settle()
    #expect(!second.isAvailable && second.track == nil)
    second.start()                                           // reopening the tab tries again
    #expect(second.status == .starting && backend.reporting.count == 2)
}

@Test @MainActor func aSystemThatSharesNothingIsReportedAsUnavailable() async {
    let backend = FakeBackend()
    let player = NowPlayingController(backend: backend)
    player.start()
    backend.report(.unsupported)
    await settle()
    #expect(!player.isAvailable)
}

// MARK: Seeking

@Test @MainActor func clickingTheBarMovesThereAtOnceAndAStaleReportCannotPullItBack() async {
    var clock = epoch
    let backend = FakeBackend()
    let player = NowPlayingController(backend: backend, now: { clock })
    player.start()
    backend.report(.track(song))                              // 30 s into 300 s
    await settle()
    player.seek(to: 200)
    #expect(backend.seeks == [200] && player.track?.elapsed(at: clock) == 200)
    backend.report(.track(song))                              // a report made before the seek arrived: still 30 s
    await settle()
    #expect(player.track?.elapsed(at: clock) == 200)
    clock = clock.addingTimeInterval(3)                       // later, the system's word is final again
    var moved = song
    moved.elapsed = 203
    moved.timestamp = clock
    backend.report(.track(moved))
    await settle()
    #expect(player.track?.elapsed(at: clock) == 203)
}

@Test @MainActor func seekingStaysInsideTheTrackAndIsRefusedWhereTheAppForbidsIt() async {
    let backend = FakeBackend()
    let player = NowPlayingController(backend: backend, now: { epoch })
    player.start()
    backend.report(.track(song))
    await settle()
    player.seek(to: 9_999)
    player.seek(to: -5)
    #expect(backend.seeks == [300, 0])

    var live = song
    live.canSeek = false
    backend.report(.track(live))
    await settle()
    let before = backend.seeks
    player.seek(to: 100)
    #expect(backend.seeks == before)                          // not allowed: nothing is sent
}

@Test @MainActor func skippingJumpsTenSecondsFromWhereTheTrackIsNow() async {
    let backend = FakeBackend()
    let player = NowPlayingController(backend: backend, now: { epoch.addingTimeInterval(10) })
    player.start()
    backend.report(.track(song))                              // 30 s at epoch, so 40 s now
    await settle()
    player.skip(by: 10)
    player.skip(by: -10)
    #expect(backend.seeks == [50, 40])
}

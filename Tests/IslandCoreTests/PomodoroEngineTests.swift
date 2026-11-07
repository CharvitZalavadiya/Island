import Testing
import Foundation
@testable import IslandCore

final class FakeClock {
    var now = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

private let focusLength: TimeInterval = 25 * 60
private let shortLength: TimeInterval = 5 * 60
private let longLength: TimeInterval = 15 * 60

private func makeEngine(_ clock: FakeClock, autoChain: Bool = false) -> PomodoroEngine {
    PomodoroEngine(
        config: PomodoroConfig(
            focus: focusLength, shortBreak: shortLength, longBreak: longLength,
            longBreakEvery: 4, autoChain: autoChain),
        now: { clock.now })
}

@Test func configIsBuiltFromSettingsInMinutes() {
    var settings = Settings()
    settings.focusMinutes = 50
    settings.shortBreakMinutes = 10
    settings.longBreakMinutes = 20
    settings.longBreakEvery = 3
    settings.autoChain = true
    let config = PomodoroConfig(settings: settings)
    #expect(config.focus == 3000)
    #expect(config.shortBreak == 600)
    #expect(config.longBreak == 1200)
    #expect(config.longBreakEvery == 3)
    #expect(config.autoChain == true)
}

@Test func engineStartsIdleOnTheFocusPhase() {
    let engine = makeEngine(FakeClock())
    #expect(engine.status == .idle)
    #expect(engine.phase == .focus)
    #expect(engine.remaining == focusLength)
    #expect(engine.completedFocusCount == 0)
}

@Test func focusCountsDownAndFinishesOnce() {
    let clock = FakeClock()
    let engine = makeEngine(clock)
    engine.start()
    #expect(engine.status == .running)

    clock.advance(focusLength - 1)
    #expect(engine.tick() == [])
    #expect(engine.remaining == 1)

    clock.advance(1)
    #expect(engine.tick() == [.phaseFinished(.focus)])
    #expect(engine.tick() == [])
    #expect(engine.status == .idle)
    #expect(engine.phase == .shortBreak)
    #expect(engine.completedFocusCount == 1)
}

@Test func longBreakAfterEveryFourthFocus() {
    let clock = FakeClock()
    let engine = makeEngine(clock)
    for session in 1...4 {
        #expect(engine.phase == .focus)
        engine.start()
        clock.advance(focusLength)
        _ = engine.tick()
        #expect(engine.phase == (session == 4 ? .longBreak : .shortBreak))
        engine.start()
        clock.advance(session == 4 ? longLength : shortLength)
        #expect(engine.tick() == [.phaseFinished(session == 4 ? .longBreak : .shortBreak)])
    }
    #expect(engine.phase == .focus)
    #expect(engine.completedFocusCount == 4)
}

@Test func autoChainStartsTheNextPhaseAutomatically() {
    let clock = FakeClock()
    let engine = makeEngine(clock, autoChain: true)
    engine.start()
    clock.advance(focusLength)
    #expect(engine.tick() == [.phaseFinished(.focus), .phaseStarted(.shortBreak)])
    #expect(engine.status == .running)
    #expect(engine.phase == .shortBreak)
    #expect(engine.remaining == shortLength)
}

@Test func withoutAutoChainTheEngineWaitsForStart() {
    let clock = FakeClock()
    let engine = makeEngine(clock, autoChain: false)
    engine.start()
    clock.advance(focusLength)
    #expect(engine.tick() == [.phaseFinished(.focus)])
    #expect(engine.status == .idle)
}

@Test func pauseFreezesRemainingAndResumeContinues() {
    let clock = FakeClock()
    let engine = makeEngine(clock)
    engine.start()
    clock.advance(600)
    engine.pause()
    #expect(engine.status == .paused)

    clock.advance(1000)
    #expect(engine.remaining == focusLength - 600)
    #expect(engine.tick() == [])

    engine.resume()
    #expect(engine.status == .running)
    clock.advance(60)
    #expect(engine.remaining == focusLength - 660)
}

@Test func startingWhileRunningIsIgnored() {
    let clock = FakeClock()
    let engine = makeEngine(clock)
    engine.start()
    clock.advance(100)
    engine.start()
    #expect(engine.remaining == focusLength - 100)
}

@Test func stopwatchCountsUpAndNeverFinishes() {
    let clock = FakeClock()
    let engine = makeEngine(clock)
    engine.start(mode: .stopwatch)
    clock.advance(10 * 3600)
    #expect(engine.tick() == [])
    #expect(engine.status == .running)
    #expect(engine.elapsed == 10 * 3600)
}

@Test func stopwatchPauseKeepsElapsed() {
    let clock = FakeClock()
    let engine = makeEngine(clock)
    engine.start(mode: .stopwatch)
    clock.advance(30)
    engine.pause()
    clock.advance(500)
    #expect(engine.elapsed == 30)
    engine.resume()
    clock.advance(20)
    #expect(engine.elapsed == 50)
}

@Test func sleepingPastTheEndFinishesExactlyOnce() {
    let clock = FakeClock()
    let engine = makeEngine(clock)
    engine.start()
    clock.advance(3 * 3600)
    #expect(engine.tick() == [.phaseFinished(.focus)])
    #expect(engine.tick() == [])
    #expect(engine.completedFocusCount == 1)
}

@Test func clockMovingBackwardDoesNotExtendOrCrash() {
    let clock = FakeClock()
    let engine = makeEngine(clock)
    engine.start()
    clock.advance(-3600)
    #expect(engine.remaining >= 0)
    #expect(engine.remaining <= focusLength)
    #expect(engine.tick() == [])
}

@Test func tickWhileIdleOrPausedReturnsNothing() {
    let clock = FakeClock()
    let engine = makeEngine(clock)
    #expect(engine.tick() == [])
    engine.start()
    engine.pause()
    clock.advance(10 * 3600)
    #expect(engine.tick() == [])
}

@Test func resetReturnsToIdleFocusWithNoProgress() {
    let clock = FakeClock()
    let engine = makeEngine(clock)
    engine.start()
    clock.advance(focusLength)
    _ = engine.tick()
    engine.reset()
    #expect(engine.status == .idle)
    #expect(engine.phase == .focus)
    #expect(engine.completedFocusCount == 0)
    #expect(engine.remaining == focusLength)
}

@Test func skipMovesToTheNextPhaseWithoutCounting() {
    let clock = FakeClock()
    let engine = makeEngine(clock)
    engine.start()
    clock.advance(10)
    engine.skip()
    #expect(engine.phase == .shortBreak)
    #expect(engine.status == .idle)
    #expect(engine.completedFocusCount == 0)
}

import Testing
import Foundation
import IslandCore
@testable import IslandUI

private final class Clock {
    var now = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

private final class SoundCounter {
    var plays = 0
}

@MainActor
private struct Harness {
    let model: IslandModel
    let clock = Clock()
    let sound = SoundCounter()
    let controller: PomodoroController

    init(configure: (inout Settings) -> Void = { _ in }, minutesAreSeconds: Bool = false) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-ui-tests-\(UUID().uuidString)", isDirectory: true)
        let settings = SettingsStore(
            store: FileStore(url: directory.appendingPathComponent("settings.json"), defaultValue: Settings()))
        settings.update(configure)
        model = IslandModel(settings: settings)
        let clock = self.clock
        let sound = self.sound
        controller = PomodoroController(
            model: model, now: { clock.now }, playSound: { sound.plays += 1 },
            celebrationSeconds: 5, minutesAreSeconds: minutesAreSeconds)
    }

    func finishFocus() {
        controller.start()
        clock.advance(25 * 60)
        controller.tick()
    }
}

@Test @MainActor func startingMakesPomodoroLiveWithTheFocusMood() {
    let h = Harness()
    #expect(!h.model.activities.contains(.pomodoro))
    h.controller.start()
    #expect(h.model.activities.contains(.pomodoro))
    #expect(h.controller.snapshot.status == .running)
    #expect(h.controller.mood == .focus)
}

@Test @MainActor func finishingFocusPlaysTheSoundAndCelebrates() {
    let h = Harness()
    h.finishFocus()
    #expect(h.sound.plays == 1)
    #expect(h.controller.isCelebrating)
    #expect(h.controller.mood == .done)
    // The engine is idle now, but the wings stay up while the mascot celebrates.
    #expect(h.controller.snapshot.status == .idle)
    #expect(h.model.activities.contains(.pomodoro))
}

@Test @MainActor func endingTheCelebrationClearsTheWingsWhenIdle() {
    let h = Harness()
    h.finishFocus()
    h.controller.endCelebration()
    #expect(!h.controller.isCelebrating)
    #expect(!h.model.activities.contains(.pomodoro))
}

@Test @MainActor func breaksUseTheRestMood() {
    let h = Harness()
    h.finishFocus()
    h.controller.endCelebration()
    h.controller.start()
    #expect(h.controller.snapshot.phase == .shortBreak)
    #expect(h.controller.mood == .rest)
}

@Test @MainActor func finishingABreakPlaysTheSoundToo() {
    let h = Harness()
    h.finishFocus()
    h.controller.endCelebration()
    h.controller.start()
    h.clock.advance(5 * 60)
    h.controller.tick()
    #expect(h.sound.plays == 2)
}

@Test @MainActor func sleepingPastTheEndPlaysTheSoundOnce() {
    let h = Harness()
    h.controller.start()
    h.clock.advance(3 * 3600)
    h.controller.tick()
    h.controller.tick()
    #expect(h.sound.plays == 1)
}

@Test @MainActor func pausingKeepsTheWingsAndResetClearsThem() {
    let h = Harness()
    h.controller.start()
    h.controller.pause()
    #expect(h.controller.snapshot.status == .paused)
    #expect(h.model.activities.contains(.pomodoro))
    h.controller.reset()
    #expect(h.controller.snapshot.status == .idle)
    #expect(!h.model.activities.contains(.pomodoro))
}

@Test @MainActor func stopwatchModeStartsTheStopwatch() {
    let h = Harness()
    h.controller.stopwatchMode = true
    h.controller.start()
    #expect(h.controller.snapshot.mode == .stopwatch)
    h.clock.advance(90)
    h.controller.tick()
    #expect(h.controller.snapshot.elapsed == 90)
    #expect(h.controller.mood == .focus)
}

@Test @MainActor func theMascotFollowsTheSettingsWhenNotShuffling() {
    let h = Harness(configure: { $0.mascotID = "cat" })
    #expect(h.controller.mascotID == "cat")
    h.model.settings.update { $0.mascotID = "frog" }
    h.controller.settingsChanged()
    #expect(h.controller.mascotID == "frog")
}

@Test @MainActor func shufflePicksADifferentMascotAfterEachFinishedPhase() {
    let h = Harness(configure: { $0.shuffleMascots = true })
    var previous = h.controller.mascotID
    for _ in 1...5 {
        h.finishFocus()
        #expect(h.controller.mascotID != previous)
        previous = h.controller.mascotID
        h.controller.endCelebration()
        h.controller.skip()   // jump over the break
    }
}

@Test @MainActor func settingsChangesReachTheEngineAndAreUsedByTheNextSession() {
    let h = Harness()
    h.model.settings.update { $0.focusMinutes = 50 }
    h.controller.settingsChanged()
    h.controller.start()
    #expect(h.controller.snapshot.remaining == 50 * 60)
}

@Test @MainActor func fastPomodoroTreatsMinutesAsSeconds() {
    let h = Harness(minutesAreSeconds: true)
    h.controller.start()
    #expect(h.controller.snapshot.remaining == 25)
}

// MARK: Minutes from the island itself

@Test @MainActor func minusAndPlusChangeTheLengthOfTheCurrentFocusSession() {
    let h = Harness()
    #expect(h.controller.currentPhaseMinutes == 25)
    h.controller.adjustMinutes(by: 1)
    #expect(h.controller.currentPhaseMinutes == 26)
    #expect(h.controller.snapshot.remaining == 26 * 60)
    h.controller.adjustMinutes(by: -2)
    #expect(h.controller.currentPhaseMinutes == 24)
    #expect(h.model.settings.settings.focusMinutes == 24)
}

@Test @MainActor func inABreakItChangesTheBreakLengthNotTheFocusLength() {
    let h = Harness()
    h.finishFocus()
    h.controller.endCelebration()
    #expect(h.controller.snapshot.phase == .shortBreak)
    h.controller.adjustMinutes(by: 2)
    #expect(h.model.settings.settings.shortBreakMinutes == 7)
    #expect(h.model.settings.settings.focusMinutes == 25)
    #expect(h.controller.currentPhaseMinutes == 7)
}

@Test @MainActor func lengthsStayWithinTheirLimits() {
    let h = Harness()
    h.controller.adjustMinutes(by: 500)
    #expect(h.controller.currentPhaseMinutes == 180)
    h.controller.adjustMinutes(by: -500)
    #expect(h.controller.currentPhaseMinutes == 1)
}

@Test @MainActor func theLengthCannotBeChangedWhileRunningPausedOrInStopwatchMode() {
    let h = Harness()
    h.controller.start()
    h.controller.adjustMinutes(by: 5)
    #expect(h.model.settings.settings.focusMinutes == 25)
    h.controller.pause()
    h.controller.adjustMinutes(by: 5)
    #expect(h.model.settings.settings.focusMinutes == 25)
    h.controller.reset()
    h.controller.stopwatchMode = true
    h.controller.adjustMinutes(by: 5)
    #expect(h.model.settings.settings.focusMinutes == 25)
}

// MARK: Mascot choice from the island itself

@Test @MainActor func selectingAMascotSavesItAndShowsItAtOnce() {
    let h = Harness()
    h.controller.selectMascot("penguin")
    #expect(h.controller.mascotID == "penguin")
    #expect(h.model.settings.settings.mascotID == "penguin")
}

@Test @MainActor func selectingAnUnknownMascotIsIgnored() {
    let h = Harness()
    h.controller.selectMascot("not-a-mascot")
    #expect(h.controller.mascotID == "ghost")
    #expect(h.model.settings.settings.mascotID == "ghost")
}

@Test @MainActor func shuffleCanBeSwitchedFromTheCarouselAndReturnsToTheChosenMascot() {
    let h = Harness()
    #expect(!h.controller.shuffleOn)
    h.controller.selectMascot("cat")
    h.controller.setShuffle(true)
    #expect(h.controller.shuffleOn)
    #expect(h.model.settings.settings.shuffleMascots)
    h.finishFocus()
    #expect(h.controller.mascotID != "cat")
    h.controller.setShuffle(false)
    #expect(!h.controller.shuffleOn)
    #expect(h.controller.mascotID == "cat")
}

// MARK: The mascot only moves when that is worth the CPU

@Test @MainActor func theMascotMovesWhileRunningOrCelebratingButNotWhenIdleOrPaused() {
    let h = Harness()
    #expect(!h.controller.mascotMoves)
    h.controller.start()
    #expect(h.controller.mascotMoves)
    h.controller.pause()
    #expect(!h.controller.mascotMoves)
    h.controller.resume()
    h.clock.advance(25 * 60)
    h.controller.tick()
    #expect(h.controller.mascotMoves)      // celebrating
    h.controller.endCelebration()
    #expect(!h.controller.mascotMoves)
}

@Test @MainActor func theStopwatchMakesTheMascotMoveToo() {
    let h = Harness()
    h.controller.stopwatchMode = true
    h.controller.start()
    #expect(h.controller.mascotMoves)
}

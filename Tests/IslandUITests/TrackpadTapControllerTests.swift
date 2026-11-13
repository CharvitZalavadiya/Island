import CoreGraphics
import Foundation
import Testing
import IslandCore
@testable import IslandUI

// Taps on the trackpad, tried without a trackpad: made-up fingers tap, and what comes out is which action ran (with which app or
// Shortcut), what the little indicator said, and what the Tap gestures popup was told. The recognizer itself is tried in
// IslandCoreTests/TrackpadTapTests.

private let double3 = TrackpadTapTrigger(fingers: 3, taps: 2)
private let triple3 = TrackpadTapTrigger(fingers: 3, taps: 3)
private let double4 = TrackpadTapTrigger(fingers: 4, taps: 2)

private final class Clock: @unchecked Sendable {
    var time: TimeInterval = 1
}

/// A timer the test winds by hand.
private final class Timers: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [@Sendable () -> Void] = []
    func add(_ work: @escaping @Sendable () -> Void) { lock.lock(); waiting.append(work); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return waiting.count }
    func fire() {
        lock.lock()
        let due = waiting
        waiting = []
        lock.unlock()
        for work in due { work() }
    }
}

private final class FakeFreeze: PointerFreezing, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    var holds: Int { lock.lock(); defer { lock.unlock() }; return entries.filter { $0.hasPrefix("engage") }.count }
    func engage(at point: CGPoint?) { lock.lock(); entries.append("engage"); lock.unlock() }
    func release() { lock.lock(); entries.append("release"); lock.unlock() }
}

private final class FakeSource: TouchSource, @unchecked Sendable {
    private(set) var starts = 0
    private var handler: (@Sendable (TrackpadFrame) -> Void)?
    func start(_ handler: @escaping @Sendable (TrackpadFrame) -> Void) -> Result<TrackpadDevice, TouchSourceError> {
        starts += 1
        self.handler = handler
        return .success(TrackpadDevice(widthMM: 121.94, heightMM: 74.08, count: 1))
    }
    func stop() { handler = nil }
    var isRunning: Bool { handler != nil }
    func send(_ frame: TrackpadFrame) { handler?(frame) }
}

private final class FakeAudio: AudioSystem {
    private(set) var sets: [Float] = []
    func outputVolume() -> Float? { 0.5 }
    func setOutputVolume(_ value: Float) { sets.append(value) }
    func clients() -> [AudioClient] { [] }
}

private final class FakeBrightness: BrightnessControlling {
    func current() -> Float? { 0.5 }
    func set(_ value: Float) {}
}

@MainActor private final class FakeSeeker: TrackSeeking {
    func listen(_ on: Bool) {}
    var seekState: (elapsed: TimeInterval, duration: TimeInterval?)? { nil }
    func seek(to seconds: TimeInterval) {}
}

@MainActor private final class FakeFeedback: TrackpadFeedback {
    private(set) var shown: [String] = []
    func show(symbol: String, fraction: Double?, text: String) { shown.append(text) }
}

@MainActor private final class FakeRunner: TrackpadActionPerforming {
    struct Call: Equatable {
        var action: TrackpadTapAction
        var app: String?
        var shortcut: String?
    }
    private(set) var calls: [Call] = []
    var result = TapActionResult.done
    var hasAccessibility = true
    private(set) var asked = 0
    func perform(_ action: TrackpadTapAction, app: String?, shortcut: String?) -> TapActionResult {
        calls.append(Call(action: action, app: app, shortcut: shortcut))
        return result
    }
    func requestAccessibility() { asked += 1 }
}

@MainActor private struct Rig {
    let controller: TrackpadController
    let settings: SettingsStore
    let source = FakeSource()
    let freeze = FakeFreeze()
    let audio = FakeAudio()
    let feedback = FakeFeedback()
    let runner = FakeRunner()
    let clock = Clock()
    let timers = Timers()

    init(edges: Bool = true, tweak: (inout IslandCore.Settings) -> Void = { _ in }, shortcuts: [String] = []) {
        var initial = IslandCore.Settings()
        initial.trackpadEnabled = edges
        tweak(&initial)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("trackpad-taps-\(UUID())/settings.json")
        settings = SettingsStore(store: FileStore(url: url, defaultValue: initial))
        let clock = self.clock, timers = self.timers
        let pipeline = TrackpadPipeline(
            config: .init(activeEdges: initial.trackpadActiveEdges, edgeMM: initial.trackpadEdgeMM, wantedTaps: initial.trackpadWantedTaps),
            freeze: freeze, readCursor: { CGPoint(x: 640, y: 300) }, clock: { clock.time }, after: { _, work in timers.add(work) })
        controller = TrackpadController(
            settings: settings, seeker: FakeSeeker(), source: source, freeze: freeze, system: audio, brightness: FakeBrightness(),
            feedback: feedback, runner: runner, shortcutLister: { shortcuts }, pipeline: pipeline, now: { clock.time })
    }

    /// One tap with `count` fingers in the middle of the pad, then `gap` seconds.
    func tap(_ count: Int, then gap: TimeInterval = 0.1) {
        source.send(fingers(count))
        clock.time += 0.06
        source.send(fingers(count))
        clock.time += 0.06
        source.send(TrackpadFrame(touches: [], widthMM: 121.94, heightMM: 74.08))
        clock.time += gap
    }

    /// Lets what was handed to the main queue run.
    func settle() async throws { try await Task.sleep(nanoseconds: 40_000_000) }
}

private func fingers(_ count: Int) -> TrackpadFrame {
    TrackpadFrame(
        touches: (0..<count).map { TrackpadTouch(id: $0 + 1, x: (30 + 15 * Double($0)) / 121.94, y: 37 / 74.08) },
        widthMM: 121.94, heightMM: 74.08)
}

// MARK: Doing what a tap was set to do

@Test @MainActor func aDoubleTapDoesWhatItWasSetToDoAndSaysSo() async throws {
    let rig = Rig(tweak: { $0.trackpadTapActions = ["3-2": "mute"] })
    rig.controller.start()
    rig.tap(3)
    rig.tap(3)
    try await rig.settle()
    #expect(rig.runner.calls == [.init(action: .mute, app: nil, shortcut: nil)])
    #expect(rig.feedback.shown == ["Mute"])
}

@Test @MainActor func whenADoubleAndATripleTapAreBothSetTheDoubleWaitsForAThirdAndTheTripleDoesNotAlsoDoTheDouble() async throws {
    let rig = Rig(tweak: { $0.trackpadTapActions = ["3-2": "mute", "3-3": "lockScreen"] })
    rig.controller.start()
    rig.tap(3)
    rig.tap(3)
    try await rig.settle()
    #expect(rig.runner.calls.isEmpty)                                         // waiting to see whether a third comes
    #expect(rig.timers.count >= 1)                                            // and a timer is running for that
    rig.clock.time += 0.5
    rig.timers.fire()
    try await rig.settle()
    #expect(rig.runner.calls.map(\.action) == [.mute])                        // nothing came: it was a double tap

    rig.tap(3)
    rig.tap(3)
    rig.tap(3)
    try await rig.settle()
    #expect(rig.runner.calls.map(\.action) == [.mute, .lockScreen])           // a triple tap is only a triple tap
}

@Test @MainActor func anAppOrAShortcutIsPassedOnWithTheTapItWasChosenFor() async throws {
    let rig = Rig(tweak: {
        $0.trackpadTapActions = ["3-2": "openApp", "4-2": "shortcut"]
        $0.trackpadTapApps = ["3-2": "/System/Applications/Notes.app"]
        $0.trackpadTapShortcuts = ["4-2": "Do Not Disturb"]
    })
    rig.controller.start()
    rig.tap(3)
    rig.tap(3)
    rig.tap(4)
    rig.tap(4)
    try await rig.settle()
    #expect(rig.runner.calls == [
        .init(action: .openApp, app: "/System/Applications/Notes.app", shortcut: nil),
        .init(action: .shortcut, app: nil, shortcut: "Do Not Disturb"),
    ])
}

@Test @MainActor func aTapWithNothingSetDoesNothing() async throws {
    let rig = Rig(tweak: { $0.trackpadTapActions = ["4-2": "paste"] })
    rig.controller.start()
    rig.tap(3)
    rig.tap(3)
    try await rig.settle()
    #expect(rig.runner.calls.isEmpty && rig.feedback.shown.isEmpty)
}

@Test @MainActor func whenTappingIsSwitchedOffNothingRuns() async throws {
    let rig = Rig(tweak: {
        $0.trackpadTapActions = ["3-2": "mute"]
        $0.trackpadTapsEnabled = false
    })
    rig.controller.start()
    rig.tap(3)
    rig.tap(3)
    try await rig.settle()
    #expect(rig.runner.calls.isEmpty)
}

@Test @MainActor func anActionThatNeedsAPermissionOrCannotRunSaysSoInTheIndicator() async throws {
    let rig = Rig(tweak: { $0.trackpadTapActions = ["3-2": "copy"] })
    rig.controller.start()
    rig.runner.result = .needsAccessibility
    rig.tap(3)
    rig.tap(3)
    try await rig.settle()
    #expect(rig.feedback.shown == ["Allow Island in Accessibility first"])

    rig.runner.result = .unavailable("Choose an app first")
    rig.tap(3)
    rig.tap(3)
    try await rig.settle()
    #expect(rig.feedback.shown.last == "Choose an app first")
}

// MARK: What is read, and when

@Test @MainActor func theTrackpadIsReadForTapsOnlyWhenOneIsSetOrThePopupIsOpen() {
    let nothing = Rig(edges: false)
    nothing.controller.start()
    #expect(nothing.source.starts == 0)                                      // edges off, no tap set, popup closed

    let assigned = Rig(edges: false, tweak: { $0.trackpadTapActions = ["4-2": "mute"] })
    assigned.controller.start()
    #expect(assigned.source.isRunning)

    let off = Rig(edges: false, tweak: {
        $0.trackpadTapActions = ["4-2": "mute"]
        $0.trackpadTapsEnabled = false
    })
    off.controller.start()
    #expect(off.source.starts == 0)

    nothing.controller.setTapAction(.mute, for: double4)                      // choosing one starts reading
    #expect(nothing.source.isRunning)
    nothing.controller.setTapsEnabled(false)
    #expect(!nothing.source.isRunning)
}

@Test @MainActor func whileTheTapPopupIsOpenEveryTapIsNoticedEvenOnesThatDoNothing() async throws {
    let rig = Rig(edges: false)
    rig.controller.start()
    rig.controller.setTapPreviewing(true)
    rig.tap(3)
    rig.tap(3)
    try await rig.settle()
    #expect(rig.controller.lastTap == nil)                                    // a triple tap is possible, so it waits a moment
    rig.clock.time += 0.5
    rig.timers.fire()
    try await rig.settle()
    #expect(rig.controller.lastTap?.trigger == double3)                       // shown in the popup...
    #expect(rig.runner.calls.isEmpty && rig.feedback.shown.isEmpty)           // ...but nothing is done
    let first = rig.controller.lastTap?.id
    rig.tap(3)
    rig.tap(3)
    rig.clock.time += 0.5
    rig.timers.fire()
    try await rig.settle()
    #expect(rig.controller.lastTap?.id != first)                              // the same tap again is noticed again
    rig.controller.setTapPreviewing(false)
}

@Test @MainActor func theSlidePopupFollowsFingersButNotTaps() async throws {
    let rig = Rig(edges: false)
    rig.controller.start()
    rig.controller.setPreviewing(true)                                        // the Slide gestures popup
    #expect(rig.source.isRunning)
    rig.tap(3)
    rig.tap(3)
    rig.clock.time += 0.5
    rig.timers.fire()
    try await rig.settle()
    #expect(rig.controller.lastTap == nil && rig.runner.calls.isEmpty)        // taps are only followed for the Tap gestures popup
    rig.controller.setPreviewing(false)
    #expect(!rig.source.isRunning)
}

@Test @MainActor func tapsAndSlidesDoNotGetInEachOthersWay() async throws {
    let rig = Rig(tweak: { $0.trackpadTapActions = ["3-2": "mute"] })
    rig.controller.start()
    // a slide up the right edge with one finger: no tap
    for y in [20.0, 24, 30, 40] {
        rig.clock.time += 0.02
        rig.source.send(TrackpadFrame(touches: [TrackpadTouch(id: 1, x: 118 / 121.94, y: y / 74.08)], widthMM: 121.94, heightMM: 74.08))
    }
    rig.source.send(TrackpadFrame(touches: [], widthMM: 121.94, heightMM: 74.08))
    try await rig.settle()
    #expect(rig.runner.calls.isEmpty && !rig.audio.sets.isEmpty)              // the volume changed, no action ran
    // a three-finger double tap: no edge gesture, the pointer is not held
    let holds = rig.freeze.holds
    rig.tap(3)
    rig.tap(3)
    try await rig.settle()
    #expect(rig.runner.calls.map(\.action) == [.mute] && rig.freeze.holds == holds)
}

// MARK: What is set

@Test @MainActor func theChoicesForTapsAreSaved() async {
    let rig = Rig(shortcuts: ["Focus on", "Lights"])
    rig.controller.setTapAction(.openApp, for: triple3)
    rig.controller.setTapApp("/Applications/Safari.app", for: triple3)
    rig.controller.setTapShortcut("Focus on", for: double4)
    let saved = rig.settings.settings
    #expect(saved.trackpadTapAction(for: triple3) == .openApp && saved.trackpadTapApp(for: triple3) == "/Applications/Safari.app")
    #expect(saved.trackpadTapShortcut(for: double4) == "Focus on")
    #expect(rig.controller.tapAction(for: triple3) == .openApp && rig.controller.tapApp(for: triple3) == "/Applications/Safari.app")
    rig.controller.setTapApp(nil, for: triple3)
    #expect(rig.controller.tapApp(for: triple3) == nil)
    await rig.controller.loadShortcuts()
    #expect(rig.controller.shortcutNames == ["Focus on", "Lights"])
    rig.controller.setTapsEnabled(false)
    #expect(!rig.controller.isTapsEnabled && !rig.settings.settings.trackpadTapsEnabled)
}

@Test @MainActor func switchingTapsOffAndBackOnKeepsWhatWasChosen() {
    let rig = Rig(edges: false, tweak: { $0.trackpadTapActions = ["3-2": "mute"] })
    rig.controller.start()
    rig.controller.setTapsEnabled(false)
    rig.controller.setTapsEnabled(true)
    #expect(rig.controller.tapAction(for: double3) == .mute && rig.source.isRunning)
}
